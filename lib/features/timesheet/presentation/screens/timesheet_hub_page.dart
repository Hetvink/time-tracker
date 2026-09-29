import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/csv_export.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../../insights/data/insights.dart' show prettySource;
import '../../../insights/presentation/insight_views.dart' show showMonthPicker;
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tracking/presentation/providers/activity_tracking_provider.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../../data/models/daily_timesheet.dart';
import '../providers/monthly_timesheet_controller.dart';
import '../widgets/activity_timesheet_view.dart';

/// Official monthly timesheet (stored session totals) plus the hour-by-hour
/// calendar grid.
class TimesheetHubPage extends StatelessWidget {
  const TimesheetHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    return ChangeNotifierProvider(
      create: (context) =>
          MonthlyTimesheetController(context.read<AttendanceProvider>()),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 8),
                child: const PageHeader(
                  eyebrow: 'Records',
                  title: 'Timesheet',
                  subtitle:
                      'Your official monthly hours, day by day, ready to export.',
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Monthly timesheet'),
                    Tab(text: 'Calendar grid'),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(
                child: TabBarView(
                  // The grid scrolls sideways, so no swiping between tabs.
                  physics: NeverScrollableScrollPhysics(),
                  children: [
                    KeepAlivePage(child: _MonthlyTimesheet()),
                    _CalendarGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Monthly timesheet
// -----------------------------------------------------------------------------

class _MonthlyTimesheet extends StatelessWidget {
  const _MonthlyTimesheet();

  Future<void> _export(
    BuildContext context,
    DateTime month,
    List<DailyTimeSheet> days,
  ) => exportCsv(
    context,
    filename: 'timesheet-${DateFormat('yyyy-MM').format(month)}.csv',
    header: const [
      'Date',
      'Weekday',
      'Sessions',
      'First in',
      'Last out',
      'Worked (h)',
      'Breaks (min)',
      'Worked while asleep (min)',
    ],
    rows: [
      for (final d in [...days]..sort((a, b) => a.date.compareTo(b.date)))
        [
          DateFormat('yyyy-MM-dd').format(d.date),
          DateFormat('EEEE').format(d.date),
          d.sessions.length,
          d.sessions.isEmpty ? '' : formatTime(_first(d)),
          d.sessions.isEmpty ? '' : formatTime(_last(d)),
          (d.totalWorkTime.inMinutes / 60).toStringAsFixed(2),
          d.totalBreakTime.inMinutes,
          d.totalWorkDuringSleepTime.inMinutes,
        ],
    ],
  );

  static DateTime _first(DailyTimeSheet d) => d.sessions
      .map((s) => s.checkInTime)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  static DateTime? _last(DailyTimeSheet d) {
    DateTime? last;
    for (final s in d.sessions) {
      final t = s.checkOutTime;
      if (t == null) return null; // still running
      if (last == null || t.isAfter(last)) last = t;
    }
    return last;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonthlyTimesheetController>();
    final gutter = context.gutter;
    final month = c.month;
    final days = c.days;
    final goal = Duration(
      minutes: context.watch<SettingsProvider>().dailyGoalMinutes,
    );

    final items = <Widget>[
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PeriodStepper(
            label: DateFormat('MMMM y').format(month),
            onPrevious: () => c.shift(-1),
            onNext: c.isCurrentMonth ? null : () => c.shift(1),
            onTapLabel: () async {
              final m = await showMonthPicker(context, month);
              if (m != null) c.setMonth(m);
            },
            onToday: c.isCurrentMonth ? null : c.currentMonth,
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: days == null || days.isEmpty
                    ? null
                    : () => _export(context, month, days),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Export CSV'),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: c.isLoading ? null : c.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
      if (c.error != null && days == null)
        ErrorState(error: c.error, onRetry: c.refresh)
      else if (days == null) ...[
        const SkeletonCard(height: 140),
        const SkeletonCard(height: 360),
      ] else if (days.isEmpty)
        EmptyState(
          icon: Icons.event_note_rounded,
          title: 'No records for ${DateFormat('MMMM y').format(month)}',
          message: 'Tracked days appear here once the desktop app syncs.',
        )
      else ...[
        _Summary(days: days, goal: goal),
        _DaysTable(days: days, goal: goal),
      ],
    ];

    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (context, i) => ContentWidth(child: items[i]),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final List<DailyTimeSheet> days;
  final Duration goal;
  const _Summary({required this.days, required this.goal});

  @override
  Widget build(BuildContext context) {
    Duration sum(Duration Function(DailyTimeSheet d) f) =>
        days.fold(Duration.zero, (a, d) => a + f(d));
    final worked = sum((d) => d.totalWorkTime);
    final breaks = sum((d) => d.totalBreakTime);
    final sleep = sum((d) => d.totalWorkDuringSleepTime);
    final active = days.where((d) => d.totalWorkTime > Duration.zero).length;
    final atGoal = days.where((d) => d.totalWorkTime >= goal).length;
    return AdaptiveGrid(
      phoneMinItemWidth: 150,
      minItemWidth: 190,
      maxColumns: 5,
      spacing: 14,
      children: [
        KpiCard.duration(
          label: 'Total worked',
          duration: worked,
          icon: Icons.work_history_rounded,
          color: AppColors.primary,
          caption: '$active days worked',
        ),
        KpiCard.duration(
          label: 'Daily average',
          duration: active == 0 ? Duration.zero : worked ~/ active,
          icon: Icons.speed_rounded,
          color: AppColors.cyan,
          caption: 'Goal ${formatHm(goal)}',
        ),
        KpiCard.duration(
          label: 'Breaks',
          duration: breaks,
          icon: Icons.coffee_rounded,
          color: AppColors.warning,
        ),
        KpiCard(
          label: 'Days at goal',
          numeric: atGoal.toDouble(),
          format: (v) => '${v.round()} / $active',
          icon: Icons.flag_rounded,
          color: AppColors.success,
        ),
        if (sleep > Duration.zero)
          KpiCard.duration(
            label: 'Worked while asleep',
            duration: sleep,
            icon: Icons.bedtime_rounded,
            color: AppColors.pink,
          ),
      ],
    );
  }
}

class _DaysTable extends StatelessWidget {
  final List<DailyTimeSheet> days;
  final Duration goal;
  const _DaysTable({required this.days, required this.goal});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = context.screenWidth < 760;
    final head = context.text.labelMedium?.copyWith(color: colors.textMuted);
    final num = context.text.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final today = DateUtils.dateOnly(DateTime.now());

    return AppCard(
      title: 'Daily breakdown',
      subtitle: 'Tap a day to see its sessions',
      icon: Icons.table_rows_rounded,
      bodyPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('Date', style: head)),
                  Expanded(flex: 5, child: Text('Sessions', style: head)),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Breaks',
                      style: head,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Worked',
                      style: head,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('Progress', style: head),
                    ),
                  ),
                ],
              ),
            ),
          for (final d in days)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _showDay(context, d),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: DateUtils.isSameDay(d.date, today)
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                  border: Border(
                    top: BorderSide(
                      color: colors.border.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: compact
                    ? Row(
                        children: [
                          _DateBadge(date: d.date),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatHm(d.totalWorkTime),
                                  style: num?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '${d.sessions.length} sessions · ${formatHm(d.totalBreakTime)} breaks',
                                  style: context.text.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                _GoalBar(worked: d.totalWorkTime, goal: goal),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colors.textSubtle,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                _DateBadge(date: d.date),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    DateFormat('EEEE').format(d.date),
                                    style: context.text.bodyMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final s in d.sessions.take(4))
                                  StatusPill(
                                    label:
                                        '${formatTime(s.checkInTime)}–${s.checkOutTime == null ? 'now' : formatTime(s.checkOutTime)}',
                                    color: s.isClosed
                                        ? AppColors.primary
                                        : AppColors.success,
                                  ),
                                if (d.sessions.length > 4)
                                  StatusPill(
                                    label: '+${d.sessions.length - 4}',
                                    color: colors.textMuted,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHm(d.totalBreakTime),
                              style: num,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHm(d.totalWorkTime),
                              style: num?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: _GoalBar(
                                worked: d.totalWorkTime,
                                goal: goal,
                              ),
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

  void _showDay(BuildContext context, DailyTimeSheet d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              DateFormat('EEEE, d MMMM y').format(d.date),
              style: ctx.text.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatHm(d.totalWorkTime)} worked · ${formatHm(d.totalBreakTime)} breaks',
              style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.textMuted),
            ),
            const SizedBox(height: 16),
            for (final (n, s) in d.sessions.indexed) ...[
              SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Session ${n + 1}', style: ctx.text.titleMedium),
                        const Spacer(),
                        StatusPill(
                          label: s.isClosed ? 'Closed' : 'Running',
                          color: s.isClosed
                              ? AppColors.primary
                              : AppColors.success,
                          dot: !s.isClosed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InfoRow(
                      icon: Icons.login_rounded,
                      label: 'Check in',
                      value:
                          '${formatTime(s.checkInTime)} · ${prettySource(s.checkInSource.name)}',
                    ),
                    InfoRow(
                      icon: Icons.logout_rounded,
                      label: 'Check out',
                      value: s.checkOutTime == null
                          ? '—'
                          : '${formatTime(s.checkOutTime)} · ${prettySource(s.checkOutSource?.name)}',
                    ),
                    InfoRow(
                      icon: Icons.timer_rounded,
                      label: 'Worked',
                      value: formatHm(s.workDuration),
                      valueColor: AppColors.primary,
                    ),
                    for (final b in s.breaks)
                      InfoRow(
                        icon: Icons.coffee_rounded,
                        label:
                            'Break ${formatTime(b.startTime)} – ${b.endTime == null ? 'now' : formatTime(b.endTime)}',
                        value: formatHm(b.duration),
                        valueColor: AppColors.warning,
                      ),
                    if (s.continuationReason != null)
                      InfoRow(
                        icon: Icons.link_rounded,
                        label: 'Continued',
                        value: s.continuationReason!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final DateTime date;
  const _DateBadge({required this.date});

  @override
  Widget build(BuildContext context) {
    final weekend = date.weekday >= 6;
    final color = weekend ? AppColors.violet : AppColors.primary;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            '${date.day}',
            style: context.text.titleMedium?.copyWith(height: 1.1),
          ),
        ],
      ),
    );
  }
}

class _GoalBar extends StatelessWidget {
  final Duration worked;
  final Duration goal;
  const _GoalBar({required this.worked, required this.goal});

  @override
  Widget build(BuildContext context) {
    final ratio = goal.inSeconds == 0 ? 0.0 : worked.inSeconds / goal.inSeconds;
    final color = ratio >= 1
        ? AppColors.success
        : ratio >= 0.5
        ? AppColors.warning
        : AppColors.danger;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: context.colors.surfaceHover,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 38,
          child: Text(
            '${(ratio * 100).round()}%',
            style: context.text.bodySmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Calendar grid (hour × day matrix)
// -----------------------------------------------------------------------------

class _CalendarGrid extends StatefulWidget {
  const _CalendarGrid();

  @override
  State<_CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<_CalendarGrid> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ActivityTrackingProvider>().refreshMonth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ActivityTrackingProvider>();
    final stats = provider.monthStats;
    final gutter = context.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label:
                    'Worked ${formatSeconds((stats['total_work_seconds'] as num?)?.toInt() ?? 0)}',
                color: AppColors.primary,
                icon: Icons.work_outline_rounded,
              ),
              StatusPill(
                label:
                    'Breaks ${formatSeconds((stats['total_break_seconds'] as num?)?.toInt() ?? 0)}',
                color: AppColors.warning,
                icon: Icons.coffee_rounded,
              ),
              TextButton.icon(
                onPressed: provider.refreshMonth,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: ActivityTimesheetView(
                  month: provider.currentMonth,
                  monthStats: stats,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
