import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:time_trak/theme/macos_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/repository/admin_repository.dart';
import '../providers/admin_dashboard_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class UserMonthlySummaryDashboard extends StatelessWidget {
  final String userId;

  const UserMonthlySummaryDashboard({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final adminRepo = context.read<AdminRepository>();

    return Consumer<AdminDashboardProvider>(
      builder: (context, adminProvider, child) {
        final year = adminProvider.selectedYear;
        final month = adminProvider.selectedMonth;

        return FutureBuilder<List<dynamic>>(
          key: ValueKey('$userId-$year-$month-${adminProvider.refreshKey}'),
          future: Future.wait([
            adminRepo.getUserMonthSummary(
              userId: userId,
              year: year,
              month: month,
            ),
            adminRepo.getUserAppActivityBreakdown(
              userId: userId,
              startDate: DateTime(year, month),
              endDate: DateTime(year, month + 1),
            ),
            adminRepo.getUserMonthlyAppActivityWithWindows(
              userId: userId,
              year: year,
              month: month,
            ),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _errorView(
                () => adminProvider.refreshData(),
                '${snapshot.error}',
              );
            }

            final results = snapshot.data ?? [{}, [], []];
            final monthSummary = results[0] as Map<String, dynamic>;
            final appBreakdown = (results[1] as List<dynamic>)
                .cast<Map<String, dynamic>>();
            final rawMonthlyActivities = results[2] as List<dynamic>;

            return _buildDashboard(
              context,
              adminProvider,
              monthSummary,
              appBreakdown,
              rawMonthlyActivities,
            );
          },
        );
      },
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    AdminDashboardProvider adminProvider,
    Map<String, dynamic> monthSummary,
    List<Map<String, dynamic>> appBreakdown,
    List<dynamic> rawMonthlyActivities,
  ) {
    final year = adminProvider.selectedYear;
    final month = adminProvider.selectedMonth;
    final monthName = DateFormat('MMMM yyyy').format(DateTime(year, month));

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // ── Compact header with month picker + tab bar ──────────────────────
          Container(
            decoration: BoxDecoration(
              color: MacOSTheme.darkSidebar,
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Column(
              children: [
                // Month picker row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          final prevM = month == 1 ? 12 : month - 1;
                          final prevY = month == 1 ? year - 1 : year;
                          adminProvider.setSelectedYearMonth(prevY, prevM);
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
                          horizontal: 18,
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
                              Icons.calendar_month,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              monthName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white70,
                        ),
                        onPressed:
                            (year < DateTime.now().year ||
                                (year == DateTime.now().year &&
                                    month < DateTime.now().month))
                            ? () {
                                final nextM = month == 12 ? 1 : month + 1;
                                final nextY = month == 12 ? year + 1 : year;
                                adminProvider.setSelectedYearMonth(
                                  nextY,
                                  nextM,
                                );
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
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 18,
                        ),
                        onPressed: () => adminProvider.refreshData(),
                        tooltip: AppStrings.refresh,
                      ),
                    ],
                  ),
                ),
                // Tab bar
                const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white38,
                  indicatorColor: Color(0xFF007AFF),
                  labelStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(fontSize: 14),
                  tabs: [
                    Tab(text: 'Summary'),
                    Tab(text: 'Mixed Sessions'),
                  ],
                ),
              ],
            ),
          ),

          // ── Content ────────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              children: [
                _buildSummaryTab(context, monthSummary, appBreakdown),
                _buildMixedSessionsTab(context, rawMonthlyActivities),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SUMMARY TAB  – two-column layout: stat cards 3×2 | chart  +  app table below
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSummaryTab(
    BuildContext context,
    Map<String, dynamic> monthSummary,
    List<Map<String, dynamic>> appBreakdown,
  ) {
    if (monthSummary.isEmpty) {
      return const Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.white60, fontSize: 16),
        ),
      );
    }

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
                // Row 1: stat cards + chart
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 860) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: 2-col stat grid
                          SizedBox(
                            width: 380,
                            child: _buildStatCardGrid(monthSummary),
                          ),
                          const SizedBox(width: 24),
                          // Right: daily trend chart
                          Expanded(child: _buildDailyTrendChart(monthSummary)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildStatCardGrid(monthSummary),
                        const SizedBox(height: 24),
                        _buildDailyTrendChart(monthSummary),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                // App breakdown table
                _buildAppBreakdownTable(appBreakdown),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCardGrid(Map<String, dynamic> monthSummary) {
    final totalWork = monthSummary['total_work_seconds'] as int? ?? 0;
    final normalWork = monthSummary['normal_work_seconds'] as int? ?? 0;
    final sleepWork =
        monthSummary['total_work_during_sleep_seconds'] as int? ?? 0;
    final totalBreak = monthSummary['total_break_seconds'] as int? ?? 0;
    final totalSessions = monthSummary['total_sessions'] as int? ?? 0;
    final avgSession = monthSummary['average_session_seconds'] as int? ?? 0;

    final cards = [
      _SumCard(
        'Normal Work',
        _formatDuration(Duration(seconds: normalWork)),
        Icons.computer,
        const Color(0xFF007AFF),
        'Active Work',
      ),
      _SumCard(
        'Sleep Work',
        _formatDuration(Duration(seconds: sleepWork)),
        Icons.nightlight_round,
        const Color(0xFFFFCC00),
        'Automated',
      ),
      _SumCard(
        'Total Work',
        _formatDuration(Duration(seconds: totalWork)),
        Icons.access_time_filled,
        const Color(0xFF32D74B),
        'Normal + Sleep',
      ),
      _SumCard(
        'Total Break',
        _formatDuration(Duration(seconds: totalBreak)),
        Icons.coffee,
        const Color(0xFFFF9500),
        null,
      ),
      _SumCard(
        'Sessions',
        totalSessions.toString(),
        Icons.event_note,
        const Color(0xFF5856D6),
        null,
      ),
      _SumCard(
        'Avg Session',
        _formatDuration(Duration(seconds: avgSession)),
        Icons.trending_up,
        const Color(0xFFBF5AF2),
        null,
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) {
        return SizedBox(
          width: 180,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(c.icon, color: c.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        c.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (c.sub != null)
                        Text(
                          c.sub!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDailyTrendChart(Map<String, dynamic> monthSummary) {
    final dailyWorkSeconds =
        monthSummary['daily_work_seconds'] as Map<String, dynamic>? ?? {};

    if (dailyWorkSeconds.isEmpty) {
      return _emptyCard('No daily trend data available');
    }

    final sortedDates = dailyWorkSeconds.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDates.length; i++) {
      final dateKey = sortedDates[i];
      final seconds = dailyWorkSeconds[dateKey] as int;
      spots.add(FlSpot(i.toDouble(), seconds / 3600.0));
    }

    final maxY = spots.isEmpty
        ? 0.0
        : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final targetMaxY = maxY * 1.2;
    final verticalInterval = targetMaxY > 5
        ? (targetMaxY / 5).ceilToDouble()
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Daily Work Hours Trend',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                sortedDates.isNotEmpty
                    ? DateFormat(
                        'MMMM yyyy',
                      ).format(DateTime.parse(sortedDates.first))
                    : '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: verticalInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.05),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (sortedDates.length / 7).ceilToDouble(),
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= sortedDates.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat(
                              'dd',
                            ).format(DateTime.parse(sortedDates[i])),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: verticalInterval,
                      getTitlesWidget: (value, _) {
                        if ((value - value.round()).abs() > 0.001) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          '${value.round()}h',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (sortedDates.length - 1).toDouble(),
                minY: 0,
                maxY: targetMaxY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((spot) {
                      return LineTooltipItem(
                        _formatDuration(
                          Duration(seconds: (spot.y * 3600).round()),
                        ),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                    getTooltipColor: (_) => const Color(0xFF252540),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF007AFF),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 3,
                        color: const Color(0xFF007AFF),
                        strokeWidth: 1.5,
                        strokeColor: const Color(0xFF1E1E30),
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBreakdownTable(List<Map<String, dynamic>> appBreakdown) {
    if (appBreakdown.isEmpty) {
      return _emptyCard('No app activity data available');
    }

    final totalSeconds = appBreakdown.fold<int>(
      0,
      (sum, app) => sum + (app['total_duration_seconds'] as int),
    );
    final maxDur = appBreakdown.isNotEmpty
        ? (appBreakdown.first['total_duration_seconds'] as int)
        : 1;

    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const SizedBox(width: 32),
                _colHdr('App Name', flex: 4),
                _colHdr('Duration', flex: 2),
                _colHdr('Share', flex: 3),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF252540)),
          ...appBreakdown.take(10).toList().asMap().entries.map((e) {
            final idx = e.key;
            final app = e.value;
            final appName = app['app_name'] as String;
            final dur = app['total_duration_seconds'] as int;
            final pct = totalSeconds > 0 ? (dur / totalSeconds) : 0.0;
            final barPct = (dur / maxDur).clamp(0.0, 1.0);
            final color = _getAppColor(idx);

            return Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF252540))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      appName,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _formatDuration(Duration(seconds: dur)),
                      style: const TextStyle(
                        color: Colors.white,
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
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.06,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                color.withValues(alpha: 0.7),
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 42,
                          child: Text(
                            '${(pct * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MIXED SESSIONS TAB – compact DataTable with expandable window rows
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMixedSessionsTab(
    BuildContext context,
    List<dynamic> rawMonthlyActivities,
  ) {
    if (rawMonthlyActivities.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apps, size: 64, color: Colors.white30),
            SizedBox(height: 16),
            Text(
              'No app activities recorded for this month',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final grouped = _groupAppActivities(rawMonthlyActivities);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick stats strip
                Row(
                  children: [
                    _miniStat(
                      Icons.apps,
                      '${grouped.length} Apps',
                      const Color(0xFF007AFF),
                    ),
                    const SizedBox(width: 24),
                    _miniStat(
                      Icons.access_time,
                      _formatDuration(Duration(seconds: totalSeconds)),
                      const Color(0xFF34C759),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // App table
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
                      // Table header
                      Container(
                        color: Colors.white.withValues(alpha: 0.04),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            _colHdr('App Name', flex: 4),
                            _colHdr('Duration', flex: 2),
                            _colHdr('Usage', flex: 3),
                            _colHdr('Windows'),
                            const SizedBox(width: 32),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFF252540)),
                      ...grouped.asMap().entries.map((e) {
                        return _buildMixedAppRow(
                          context,
                          e.key,
                          e.value,
                          maxDur,
                          totalSeconds,
                        );
                      }),
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
            // App name
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.apps, color: color, size: 15),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Duration
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
            // Bar + %
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
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            // Window count
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
                  final title =
                      (win['title'] as String?)?.trim() ?? 'General Usage';
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
                      vertical: 10,
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
                          size: 12,
                          color: color.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title.isEmpty ? 'General Usage' : title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _colHdr(String label, {int flex = 1}) {
    final w = Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
    return Expanded(flex: flex, child: w);
  }

  Widget _miniStat(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _errorView(VoidCallback retry, [String? message]) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          const Text(
            'Error loading data',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            message ?? 'An error occurred while loading data',
            style: TextStyle(color: Colors.red.shade300),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: retry, child: const Text(AppStrings.retry)),
        ],
      ),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          msg,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
          ),
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

      final appData = appMap[appKey]!;
      appData['total_duration'] = (appData['total_duration'] as int) + duration;
      (appData['windows'] as Map<String, int>)[windowTitle] =
          ((appData['windows'] as Map<String, int>)[windowTitle] ?? 0) +
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

class _SumCard {
  final String title, value;
  final String? sub;
  final IconData icon;
  final Color color;
  const _SumCard(this.title, this.value, this.icon, this.color, this.sub);
}
