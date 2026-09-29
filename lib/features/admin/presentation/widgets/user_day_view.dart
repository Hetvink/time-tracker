import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:time_trak/theme/macos_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../data/repository/admin_repository.dart';
import '../providers/admin_dashboard_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class UserDayView extends StatelessWidget {
  final String userId;

  const UserDayView({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final adminRepo = context.read<AdminRepository>();

    return Consumer<AdminDashboardProvider>(
      builder: (context, adminProvider, child) {
        final selectedDate = adminProvider.selectedDate;

        return FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(
            '$userId-${selectedDate.toIso8601String()}-${adminProvider.refreshKey}',
          ),
          future: adminRepo.getUserDayActivity(
            userId: userId,
            date: selectedDate,
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

            final dayActivity = snapshot.data ?? {};
            return _buildView(context, adminProvider, dayActivity);
          },
        );
      },
    );
  }

  Widget _buildView(
    BuildContext context,
    AdminDashboardProvider adminProvider,
    Map<String, dynamic> dayActivity,
  ) {
    final selectedDate = adminProvider.selectedDate;
    final sessions = dayActivity['sessions'] as List<dynamic>? ?? [];
    final statistics = dayActivity['statistics'] as Map<String, dynamic>? ?? {};

    final totalWork = statistics['total_work_seconds'] as int? ?? 0;
    final totalBreak = statistics['total_break_seconds'] as int? ?? 0;
    final sessionCount = statistics['session_count'] as int? ?? 0;

    return Column(
      children: [
        // ── Compact date header ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: MacOSTheme.darkSidebar,
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              // Prev day
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white70),
                onPressed: () {
                  adminProvider.setSelectedDate(
                    selectedDate.subtract(const Duration(days: 1)),
                  );
                },
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Clickable date selector
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    adminProvider.setSelectedDate(picked);
                  }
                },
                child: Container(
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMMM dd, yyyy').format(selectedDate),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Next day
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
                onPressed:
                    selectedDate.isBefore(
                      DateTime.now().subtract(const Duration(days: 1)),
                    )
                    ? () => adminProvider.setSelectedDate(
                        selectedDate.add(const Duration(days: 1)),
                      )
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const Spacer(),
              if (sessionCount > 0) ...[
                _inlineStat(
                  'Work',
                  _formatDuration(Duration(seconds: totalWork)),
                  const Color(0xFF007AFF),
                ),
                const SizedBox(width: 20),
                _inlineStat(
                  'Break',
                  _formatDuration(Duration(seconds: totalBreak)),
                  const Color(0xFFFF9500),
                ),
                const SizedBox(width: 20),
                _inlineStat(
                  'Sessions',
                  '$sessionCount',
                  const Color(0xFF34C759),
                ),
              ],
            ],
          ),
        ),
        // ── Content ────────────────────────────────────────────────────────
        Expanded(child: _buildContent(context, sessions, statistics)),
      ],
    );
  }

  Widget _inlineStat(String label, String value, Color color) {
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
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<dynamic> sessions,
    Map<String, dynamic> statistics,
  ) {
    if (sessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.white30),
            SizedBox(height: 16),
            Text(
              'No activity for this day',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: MacOSTheme.darkBackground,
            child: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              indicatorColor: Color(0xFF007AFF),
              labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'Sessions'),
                Tab(text: 'Mixed Activities'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSessionsTab(context, sessions),
                _buildMixedActivitiesTab(context, sessions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SESSIONS TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSessionsTab(BuildContext context, List<dynamic> sessions) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sessions table
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
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
                            _colHdr('Status', width: 100),
                            _colHdrFlex('Time Range', flex: 3),
                            _colHdrFlex('Work Time', flex: 2),
                            _colHdrFlex('Breaks', flex: 2),
                            _colHdrFlex('Top Apps', flex: 3),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFF252540)),
                      // Session rows
                      ...sessions.map(
                        (s) => _buildSessionRow(
                          context,
                          s as Map<String, dynamic>,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionRow(BuildContext context, Map<String, dynamic> session) {
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
    final breaks = session['break_periods'] as List<dynamic>? ?? [];
    final rawActivities = session['app_activities'] as List<dynamic>? ?? [];
    final appActivities = _groupAppActivities(rawActivities);

    final timeFmt = DateFormat('hh:mm a');
    final statusColor = isClosed
        ? const Color(0xFF34C759)
        : const Color(0xFFFF9500);

    final breakDuration = breaks.fold<Duration>(Duration.zero, (acc, b) {
      final start = DateTime.parse(b['break_start_time']);
      final end = b['break_end_time'] != null
          ? DateTime.parse(b['break_end_time'])
          : start;
      return acc + end.difference(start);
    });

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: EdgeInsets.zero,
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white30,
        title: Row(
          children: [
            // Status
            SizedBox(
              width: 100,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isClosed ? Icons.check_circle : Icons.pending,
                      color: statusColor,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isClosed ? 'Done' : 'Active',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Time range
            Expanded(
              flex: 3,
              child: Text(
                '${timeFmt.format(checkIn)} → ${checkOut != null ? timeFmt.format(checkOut) : 'Ongoing'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
            ),
            // Work time
            Expanded(
              flex: 2,
              child: Text(
                _formatDuration(Duration(seconds: totalWork)),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Breaks
            Expanded(
              flex: 2,
              child: Text(
                breaks.isEmpty
                    ? '—'
                    : '${breaks.length} (${_formatDuration(breakDuration)})',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ),
            // Top apps
            Expanded(
              flex: 3,
              child: appActivities.isEmpty
                  ? Text(
                      '—',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 13,
                      ),
                    )
                  : Text(
                      appActivities
                          .take(2)
                          .map((a) => a['app_name'] as String)
                          .join(', '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
        children: [
          Container(
            color: const Color(0xFF161628),
            child: _buildSessionDetail(session, appActivities),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDetail(
    Map<String, dynamic> session,
    List<Map<String, dynamic>> appActivities,
  ) {
    final breaks = session['break_periods'] as List<dynamic>? ?? [];
    final sleepPeriods =
        session['work_during_sleep_periods'] as List<dynamic>? ?? [];
    final timeFmt = DateFormat('hh:mm a');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breaks
          if (breaks.isNotEmpty)
            Expanded(
              child: _detailSection(
                Icons.coffee,
                Colors.orange,
                '${breaks.length} Break${breaks.length > 1 ? 's' : ''}',
                breaks.map((b) {
                  final start = DateTime.parse(b['break_start_time']).toLocal();
                  final end = b['break_end_time'] != null
                      ? DateTime.parse(b['break_end_time']).toLocal()
                      : null;
                  final dur = end != null
                      ? end.difference(start)
                      : Duration.zero;
                  return '${timeFmt.format(start)} – ${end != null ? timeFmt.format(end) : 'Ongoing'} (${_formatDuration(dur)})';
                }).toList(),
              ),
            ),
          if (breaks.isNotEmpty &&
              (sleepPeriods.isNotEmpty || appActivities.isNotEmpty))
            const SizedBox(width: 20),

          // Sleep Work
          if (sleepPeriods.isNotEmpty)
            Expanded(
              child: _detailSection(
                Icons.bedtime,
                Colors.redAccent,
                'Work During Sleep',
                sleepPeriods.map((sp) {
                  DateTime sleepStart;
                  DateTime wakeTime;
                  if (sp['sleep_start_time_utc'] != null) {
                    sleepStart = DateTime.parse(
                      sp['sleep_start_time_utc'],
                    ).toLocal();
                  } else {
                    sleepStart = DateTime.parse(sp['sleep_start_time'] ?? '');
                  }
                  if (sp['wake_time_utc'] != null) {
                    wakeTime = DateTime.parse(sp['wake_time_utc']).toLocal();
                  } else {
                    wakeTime = DateTime.parse(sp['wake_time'] ?? '');
                  }
                  final dur = wakeTime.difference(sleepStart);
                  return '${timeFmt.format(sleepStart)} – ${timeFmt.format(wakeTime)} (${_formatDuration(dur)})';
                }).toList(),
              ),
            ),
          if (sleepPeriods.isNotEmpty && appActivities.isNotEmpty)
            const SizedBox(width: 20),

          // Top apps
          if (appActivities.isNotEmpty)
            Expanded(
              flex: 2,
              child: _detailSection(
                Icons.apps,
                Colors.blue,
                '${appActivities.length} Apps Used',
                appActivities
                    .take(6)
                    .map(
                      (a) =>
                          '${a['app_name']}  ·  ${_formatDuration(Duration(seconds: a['duration_seconds'] as int))}',
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailSection(
    IconData icon,
    Color color,
    String title,
    List<String> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              item,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MIXED ACTIVITIES TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMixedActivitiesTab(
    BuildContext context,
    List<dynamic> sessions,
  ) {
    // Collect ALL app activities across all sessions
    final allRaw = <dynamic>[];
    for (var s in sessions) {
      final acts =
          (s as Map<String, dynamic>)['app_activities'] as List<dynamic>? ?? [];
      allRaw.addAll(acts);
    }

    final grouped = _groupAppActivities(allRaw);
    if (grouped.isEmpty) {
      return const Center(
        child: Text(
          'No app activities for this day',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
      );
    }

    final totalSeconds = grouped.fold<int>(
      0,
      (sum, a) => sum + (a['duration_seconds'] as int),
    );
    final maxDur = grouped.isNotEmpty
        ? (grouped.first['duration_seconds'] as int)
        : 1;

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
                        _colHdrFlex('App Name', flex: 4),
                        _colHdrFlex('Duration', flex: 2),
                        _colHdrFlex('Usage', flex: 3),
                        _colHdrFlex('Windows'),
                        const SizedBox(width: 32),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF252540)),
                  ...grouped.asMap().entries.map(
                    (e) => _buildMixedAppRow(
                      context,
                      e.key,
                      e.value,
                      maxDur,
                      totalSeconds,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMixedAppRow(
    BuildContext context,
    int idx,
    Map<String, dynamic> activity,
    int maxDur,
    int totalSeconds,
  ) {
    final appName = activity['app_name'] as String;
    final dur = activity['duration_seconds'] as int;
    final windows = activity['windows'] as List<Map<String, dynamic>>? ?? [];
    final barPct = (dur / maxDur).clamp(0.0, 1.0);
    final sharePct = totalSeconds > 0 ? (dur / totalSeconds * 100) : 0.0;
    final color = _getAppColor(idx);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: EdgeInsets.zero,
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white30,
        title: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.apps, color: color, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _formatDurationDetailed(Duration(seconds: dur)),
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: barPct,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          color.withValues(alpha: 0.7),
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${sharePct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${windows.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        children: [
          if (windows.isNotEmpty)
            Container(
              color: const Color(0xFF161628),
              child: Column(
                children: windows.asMap().entries.map((e) {
                  final i = e.key;
                  final win = e.value;
                  final title = (win['title'] as String?)?.trim() ?? '';
                  final winDur = win['duration_seconds'] as int;
                  final winPct = dur > 0 ? (winDur / dur) : 0.0;

                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.crop_square,
                          size: 11,
                          color: color.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title.isEmpty ? 'General Usage' : title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          _formatDurationDetailed(Duration(seconds: winDur)),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 38,
                          child: Text(
                            '${(winPct * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _colHdr(String label, {required double width}) {
    return SizedBox(
      width: width,
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

  Widget _colHdrFlex(String label, {int flex = 1}) {
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

  List<Map<String, dynamic>> _groupAppActivities(List<dynamic> rawActivities) {
    final Map<String, Map<String, dynamic>> appMap = {};
    final Map<String, String> displayNames = {};

    for (var activity in rawActivities) {
      final rawAppName = (activity['app_name'] as String? ?? 'Unknown').trim();
      final appKey = rawAppName.toLowerCase();
      final windowTitle = (activity['window_title'] as String? ?? '').trim();
      final duration = activity['duration_seconds'] as int? ?? 0;
      if (duration <= 0) continue;

      if (!appMap.containsKey(appKey)) {
        appMap[appKey] = {'total_duration': 0, 'windows': <String, int>{}};
        displayNames[appKey] = rawAppName;
      }

      appMap[appKey]!['total_duration'] =
          (appMap[appKey]!['total_duration'] as int) + duration;
      (appMap[appKey]!['windows'] as Map<String, int>)[windowTitle] =
          ((appMap[appKey]!['windows'] as Map<String, int>)[windowTitle] ?? 0) +
          duration;
    }

    final list = appMap.entries.map((entry) {
      final data = entry.value;
      final totalDur = data['total_duration'] as int;
      final windowsMap = data['windows'] as Map<String, int>;
      final windowsList =
          windowsMap.entries
              .map((w) => {'title': w.key, 'duration_seconds': w.value})
              .toList()
            ..sort(
              (a, b) => (b['duration_seconds'] as int).compareTo(
                a['duration_seconds'] as int,
              ),
            );

      return {
        'app_name': displayNames[entry.key] ?? entry.key,
        'duration_seconds': totalDur,
        'windows': windowsList,
      };
    }).toList();

    list.sort(
      (a, b) => (b['duration_seconds'] as int).compareTo(
        a['duration_seconds'] as int,
      ),
    );
    return list;
  }

  Color _getAppColor(int index) {
    const colors = [
      Color(0xFF007AFF),
      Color(0xFF34C759),
      Color(0xFFFF9500),
      Color(0xFF5856D6),
      Color(0xFFFF2D55),
      Color(0xFF5AC8FA),
      Color(0xFFFFCC00),
      Color(0xFFFF3B30),
      Color(0xFF30B0C7),
      Color(0xFFAF52DE),
    ];
    return colors[index % colors.length];
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatDurationDetailed(Duration d) {
    if (d.inSeconds <= 0) return '0s';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final parts = <String>[];
    if (h > 0) parts.add('${h}h');
    if (m > 0 || h > 0) parts.add('${m}m');
    if (s > 0 || (h == 0 && m == 0)) parts.add('${s}s');
    return parts.join(' ');
  }
}
