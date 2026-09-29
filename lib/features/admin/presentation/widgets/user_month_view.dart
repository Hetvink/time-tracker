import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:time_trak/theme/macos_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../data/repository/admin_repository.dart';
import '../providers/admin_dashboard_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class UserMonthView extends StatelessWidget {
  final String userId;

  const UserMonthView({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final adminRepo = context.read<AdminRepository>();

    return Consumer<AdminDashboardProvider>(
      builder: (context, adminProvider, child) {
        final year = adminProvider.selectedYear;
        final month = adminProvider.selectedMonth;
        final startOfMonth = DateTime(year, month);
        final endOfMonth = DateTime(year, month + 1);

        return FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey('$userId-$year-$month-${adminProvider.refreshKey}'),
          future: adminRepo.getUserSessions(
            userId: userId,
            startDate: startOfMonth,
            endDate: endOfMonth,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => adminProvider.refreshData(),
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                ),
              );
            }

            final sessions = snapshot.data ?? [];
            final Map<String, List<Map<String, dynamic>>> sessionsByDate = {};
            for (var session in sessions) {
              final checkInTime = session['check_in_time_utc'] != null
                  ? DateTime.parse(session['check_in_time_utc']).toLocal()
                  : DateTime.parse(session['check_in_time']);
              final dateKey = DateFormat('yyyy-MM-dd').format(checkInTime);
              sessionsByDate.putIfAbsent(dateKey, () => []).add(session);
            }

            return _buildView(context, adminProvider, sessions, sessionsByDate);
          },
        );
      },
    );
  }

  Widget _buildView(
    BuildContext context,
    AdminDashboardProvider adminProvider,
    List<Map<String, dynamic>> sessions,
    Map<String, List<Map<String, dynamic>>> sessionsByDate,
  ) {
    final year = adminProvider.selectedYear;
    final month = adminProvider.selectedMonth;

    final closedSessions = sessions
        .where((s) => s['is_closed'] == true)
        .toList();
    final totalWorkSeconds = closedSessions.fold(
      0,
      (sum, s) => sum + ((s['total_work_seconds'] as int?) ?? 0),
    );
    final totalSessions = closedSessions.length;
    final avgWorkSeconds = totalSessions > 0
        ? totalWorkSeconds ~/ totalSessions
        : 0;

    final monthName = DateFormat('MMMM yyyy').format(DateTime(year, month));

    return Column(
      children: [
        // ── Compact inline header ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: MacOSTheme.darkSidebar,
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              // Prev/Next navigator
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white70),
                onPressed: () {
                  final prevMonth = month == 1 ? 12 : month - 1;
                  final prevYear = month == 1 ? year - 1 : year;
                  adminProvider.setSelectedYearMonth(prevYear, prevMonth);
                },
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MacOSTheme.darkBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  monthName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
                onPressed:
                    (year < DateTime.now().year ||
                        (year == DateTime.now().year &&
                            month < DateTime.now().month))
                    ? () {
                        final nextM = month == 12 ? 1 : month + 1;
                        final nextY = month == 12 ? year + 1 : year;
                        adminProvider.setSelectedYearMonth(nextY, nextM);
                      }
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const Spacer(),
              _buildInlineStat(
                'Total Work',
                _formatDuration(Duration(seconds: totalWorkSeconds)),
                const Color(0xFF007AFF),
              ),
              const SizedBox(width: 20),
              _buildInlineStat(
                'Avg/Session',
                _formatDuration(Duration(seconds: avgWorkSeconds)),
                const Color(0xFF34C759),
              ),
              const SizedBox(width: 20),
              _buildInlineStat(
                'Sessions',
                '$totalSessions',
                const Color(0xFFFF9500),
              ),
            ],
          ),
        ),
        Expanded(child: _buildContent(context, sessions, sessionsByDate)),
      ],
    );
  }

  Widget _buildInlineStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Map<String, dynamic>> sessions,
    Map<String, List<Map<String, dynamic>>> sessionsByDate,
  ) {
    if (sessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 48,
              color: Colors.white38,
            ),
            SizedBox(height: 16),
            Text(
              'No sessions found for this month',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }

    final sortedDates = sessionsByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Header
                  Container(
                    color: Colors.white.withValues(alpha: 0.04),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        _buildColHeader('Date / Status', flex: 4),
                        _buildColHeader('Check-in', flex: 2),
                        _buildColHeader('Check-out', flex: 2),
                        _buildColHeader('Total Work', flex: 2),
                        _buildColHeader('Sessions'),
                        const SizedBox(width: 32),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF252540)),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedDates.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFF252540)),
                    itemBuilder: (context, index) {
                      final dateKey = sortedDates[index];
                      return _buildDayRow(
                        context,
                        dateKey,
                        sessionsByDate[dateKey]!,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDayRow(
    BuildContext context,
    String dateKey,
    List<Map<String, dynamic>> sessions,
  ) {
    final date = DateTime.parse(dateKey);
    int totalWork = 0;
    int sessionCount = 0;
    for (var s in sessions) {
      if (s['is_closed'] == true) {
        totalWork += (s['total_work_seconds'] as int?) ?? 0;
        sessionCount++;
      }
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white30,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF007AFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('dd').format(date),
                style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              Text(
                DateFormat('MMM').format(date),
                style: TextStyle(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.7),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                DateFormat('EEEE, MMMM dd').format(date),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('EEEE').format(date),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '$sessionCount',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _formatDuration(Duration(seconds: totalWork)),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        children: [
          Container(
            color: const Color(0xFF161628),
            child: Column(
              children: sessions.map((s) => _buildSessionRow(s)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> session) {
    final checkIn = session['check_in_time_utc'] != null
        ? DateTime.parse(session['check_in_time_utc']).toLocal()
        : DateTime.parse(session['check_in_time']);
    final checkOut = session['check_out_time_utc'] != null
        ? DateTime.parse(session['check_out_time_utc']).toLocal()
        : (session['check_out_time'] != null
              ? DateTime.parse(session['check_out_time'])
              : null);
    final totalWork = session['total_work_seconds'] as int? ?? 0;
    final isClosed = session['is_closed'] as bool? ?? false;
    final statusColor = isClosed
        ? const Color(0xFF34C759)
        : const Color(0xFFFF9500);
    final timeFmt = DateFormat('hh:mm a');

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF252540))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 56),
          Icon(
            isClosed ? Icons.check_circle : Icons.pending,
            color: statusColor,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${timeFmt.format(checkIn)} → ${checkOut != null ? timeFmt.format(checkOut) : 'Ongoing'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          Text(
            _formatDuration(Duration(seconds: totalWork)),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
