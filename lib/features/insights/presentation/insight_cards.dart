import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/charts.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/insights.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Cards that render an [Insights] object. Shared by the personal pages and
/// the admin member profile.

String _tod(TimeOfDay? t) => t == null
    ? '—'
    : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Headline numbers for a period.
class InsightKpis extends StatelessWidget {
  final Insights insights;
  final Duration goal;
  final bool singleDay;

  const InsightKpis({
    super.key,
    required this.insights,
    this.goal = const Duration(hours: 8),
    this.singleDay = false,
  });

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final (start, end) = i.averageStartEnd;
    final spark = i.dailyHours;
    return AdaptiveGrid(
      phoneMinItemWidth: 150,
      minItemWidth: 200,
      spacing: 14,
      children: [
        KpiCard.duration(
          label: singleDay ? 'Worked' : 'Total worked',
          duration: i.total,
          icon: Icons.timer_rounded,
          color: AppColors.primary,
          caption: singleDay
              ? '${(i.total.inSeconds / (goal.inSeconds == 0 ? 1 : goal.inSeconds) * 100).round()}% of ${formatHm(goal)} goal'
              : '${i.activeDays} active of ${i.dayCount} days',
          spark: singleDay ? null : spark,
        ),
        KpiCard.duration(
          label: singleDay ? 'Breaks' : 'Avg per active day',
          duration: singleDay ? i.breakTotal : i.averagePerActiveDay,
          icon: singleDay ? Icons.coffee_rounded : Icons.speed_rounded,
          color: singleDay ? AppColors.warning : AppColors.cyan,
          caption: singleDay
              ? '${i.sessionsInRange.fold(0, (a, s) => a + s.breaks.length)} breaks taken'
              : 'Goal ${formatHm(goal)} per day',
        ),
        KpiCard(
          label: AppStrings.sessions,
          numeric: i.sessionCount.toDouble(),
          format: (v) => v.round().toString(),
          icon: Icons.layers_rounded,
          color: AppColors.violet,
          caption: 'Longest ${formatHm(i.longestSession)}',
        ),
        KpiCard(
          label: singleDay ? 'First in → last out' : 'Typical day',
          value: '${_tod(start)} → ${_tod(end)}',
          icon: Icons.wb_twilight_rounded,
          color: AppColors.success,
          caption: singleDay
              ? (i.isWorkingNow ? 'Still working' : 'Day complete')
              : '${i.streak} day streak',
        ),
      ],
    );
  }
}

/// Bars of hours per day with a goal line.
class DailyTrendCard extends StatelessWidget {
  final Insights insights;
  final Duration goal;
  final ValueChanged<DateTime>? onDayTap;
  final String title;

  const DailyTrendCard({
    super.key,
    required this.insights,
    this.goal = const Duration(hours: 8),
    this.onDayTap,
    this.title = 'Daily hours',
  });

  @override
  Widget build(BuildContext context) {
    final entries = insights.daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final today = DateUtils.dateOnly(DateTime.now());
    final long = entries.length > 14;
    final best = insights.bestDay;
    return AppCard(
      title: title,
      subtitle: best == null
          ? 'No tracked time yet'
          : 'Best: ${DateFormat('EEE d MMM').format(best.key)} · ${formatHm(best.value)}',
      icon: Icons.bar_chart_rounded,
      actions: [
        if (goal > Duration.zero)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: LegendDot(color: AppColors.success, label: AppStrings.goal),
          ),
      ],
      child: HoursBarChart(
        goal: goal.inMinutes / 60,
        onTap: onDayTap == null ? null : (i) => onDayTap!(entries[i].key),
        data: [
          for (final e in entries)
            BarDatum(
              long ? '${e.key.day}' : DateFormat('E').format(e.key),
              e.value.inMinutes / 60,
              tooltip:
                  '${DateFormat('d MMM').format(e.key)} · ${formatHm(e.value)}',
              highlight: e.key == today,
            ),
        ],
      ),
    );
  }
}

/// When during the day work happens.
class HourlyCard extends StatelessWidget {
  final Insights insights;
  final bool perDay;

  const HourlyCard({super.key, required this.insights, this.perDay = false});

  @override
  Widget build(BuildContext context) {
    final h = insights.hourly;
    var peak = 0;
    for (var i = 1; i < 24; i++) {
      if (h[i] > h[peak]) peak = i;
    }
    final days = perDay
        ? 1
        : (insights.activeDays == 0 ? 1 : insights.activeDays);
    return AppCard(
      title: AppStrings.hourByHour,
      subtitle: h[peak] == Duration.zero
          ? 'No activity'
          : 'Most active around ${peak.toString().padLeft(2, '0')}:00',
      icon: Icons.schedule_rounded,
      child: HoursBarChart(
        height: 180,
        color: AppColors.cyan,
        axisLabel: (v) => '${v.round()}m',
        labelEvery: 3,
        data: [
          for (var i = 0; i < 24; i++)
            BarDatum(
              i.toString().padLeft(2, '0'),
              h[i].inMinutes / days,
              tooltip:
                  '${formatHm(h[i] ~/ days)}${perDay ? '' : ' avg per active day'}',
              highlight: i == peak && h[peak] > Duration.zero,
            ),
        ],
      ),
    );
  }
}

class WeekdayCard extends StatelessWidget {
  final Insights insights;
  const WeekdayCard({super.key, required this.insights});

  @override
  Widget build(BuildContext context) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final w = insights.weekday;
    // Average per occurrence of that weekday in the range
    final counts = List.filled(7, 0);
    for (final d in insights.daily.keys) {
      counts[d.weekday - 1]++;
    }
    return AppCard(
      title: AppStrings.weekdayRhythm,
      subtitle: AppStrings.averageHoursPerWeekday,
      icon: Icons.view_week_rounded,
      child: HoursBarChart(
        height: 180,
        color: AppColors.violet,
        data: [
          for (var i = 0; i < 7; i++)
            BarDatum(
              names[i],
              counts[i] == 0 ? 0 : w[i].inMinutes / 60 / counts[i],
              tooltip:
                  '${formatHm(counts[i] == 0 ? Duration.zero : w[i] ~/ counts[i])} avg',
              highlight: i == DateTime.now().weekday - 1,
            ),
        ],
      ),
    );
  }
}

/// Donut + ranked list of apps.
class AppUsageCard extends StatefulWidget {
  final Insights insights;
  final int limit;
  final String title;

  const AppUsageCard({
    super.key,
    required this.insights,
    this.limit = 6,
    this.title = 'Apps & tools',
  });

  @override
  State<AppUsageCard> createState() => _AppUsageCardState();
}

class _AppUsageCardState extends State<AppUsageCard> {
  /// Expanded to show every row.
  final _all = ValueNotifier(false);

  @override
  void dispose() {
    _all.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _all,
    builder: (context, all, _) => _build(context, all),
  );

  Widget _build(BuildContext context, bool all) {
    final apps = widget.insights.apps;
    final total = widget.insights.appTotal;
    if (apps.isEmpty) {
      return AppCard(
        title: widget.title,
        icon: Icons.apps_rounded,
        child: const SizedBox(
          height: 180,
          child: EmptyState(
            icon: Icons.apps_outage_rounded,
            title: AppStrings.noAppActivity,
            message: 'App usage appears once the desktop tracker records it.',
          ),
        ),
      );
    }
    final top = apps.take(widget.limit).toList();
    final rest = total - top.fold(Duration.zero, (a, u) => a + u.total);
    final slices = [
      for (var i = 0; i < top.length; i++)
        DonutSlice(
          top[i].name,
          top[i].total.inSeconds.toDouble(),
          AppColors.chartAt(i),
        ),
      if (rest > Duration.zero)
        DonutSlice('Other', rest.inSeconds.toDouble(), AppColors.idle),
    ];
    final listed = all ? apps : top;

    final donut = DonutChart(
      slices: slices,
      centerValue: formatHoursShort(total),
      centerLabel: '${apps.length} apps',
      size: 180,
    );
    final list = Column(
      children: [
        for (var i = 0; i < listed.length; i++)
          ShareBar(
            label: listed[i].name,
            trailing: formatHm(listed[i].total),
            fraction: total.inSeconds == 0
                ? 0
                : listed[i].total.inSeconds / total.inSeconds,
            color: i < widget.limit ? AppColors.chartAt(i) : AppColors.idle,
            sublabel: listed[i].topWindows.isEmpty
                ? null
                : listed[i].topWindows.first.key,
          ),
      ],
    );

    return AppCard(
      title: widget.title,
      subtitle:
          'Top 3 apps hold ${(widget.insights.focusScore * 100).round()}% of time',
      icon: Icons.apps_rounded,
      actions: [
        if (apps.length > widget.limit)
          TextButton(
            onPressed: () => _all.value = !all,
            child: Text(all ? 'Show less' : 'All ${apps.length}'),
          ),
      ],
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 520
            ? Column(children: [donut, const SizedBox(height: 16), list])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  donut,
                  const SizedBox(width: 24),
                  Expanded(child: list),
                ],
              ),
      ),
    );
  }
}

/// Expandable list of sessions with their breaks.
class SessionsCard extends StatefulWidget {
  final Insights insights;
  final int limit;
  final String title;

  const SessionsCard({
    super.key,
    required this.insights,
    this.limit = 8,
    this.title = 'Sessions',
  });

  @override
  State<SessionsCard> createState() => _SessionsCardState();
}

class _SessionsCardState extends State<SessionsCard> {
  /// Expanded to show every row.
  final _all = ValueNotifier(false);

  @override
  void dispose() {
    _all.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _all,
    builder: (context, all, _) => _build(context, all),
  );

  Widget _build(BuildContext context, bool all) {
    final sessions = widget.insights.sessionsInRange;
    final shown = all ? sessions : sessions.take(widget.limit).toList();
    return AppCard(
      title: widget.title,
      subtitle: '${sessions.length} in this period',
      icon: Icons.layers_rounded,
      bodyPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      actions: [
        if (sessions.length > widget.limit)
          TextButton(
            onPressed: () => _all.value = !all,
            child: Text(all ? 'Show less' : 'Show all'),
          ),
      ],
      child: sessions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.event_busy_rounded,
                title: AppStrings.noSessions,
                message: 'Nothing was tracked in this period.',
              ),
            )
          : Column(children: [for (final s in shown) _SessionTile(session: s)]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionInfo session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final colors = context.colors;
    final sameDay = DateUtils.isSameDay(s.start, s.end);
    final color = s.onBreak
        ? AppColors.warning
        : s.isOpen
        ? AppColors.success
        : AppColors.primary;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        leading: Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                '${DateFormat('EEE d MMM').format(s.start)} · ${formatTime(s.start)} – ${s.isOpen ? 'now' : formatTime(s.end)}${sameDay ? '' : ' (+1)'}',
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (s.isOpen) ...[
              const SizedBox(width: 8),
              StatusPill(
                label: s.onBreak ? 'On break' : 'Live',
                color: color,
                dot: true,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${formatHm(s.work)} worked · ${s.breaks.length} break${s.breaks.length == 1 ? '' : 's'} (${formatHm(s.breakTime)})',
          style: context.text.bodySmall,
        ),
        children: [
          InfoRow(
            label: AppStrings.checkedIn,
            value: '${formatTime(s.start)} · ${prettySource(s.checkInSource)}',
            icon: Icons.login_rounded,
          ),
          InfoRow(
            label: AppStrings.checkedOut,
            value: s.isOpen
                ? 'Still running'
                : '${formatTime(s.end)} · ${prettySource(s.checkOutSource)}',
            icon: Icons.logout_rounded,
          ),
          InfoRow(
            label: AppStrings.span,
            value: formatHm(s.span),
            icon: Icons.straighten_rounded,
          ),
          if (s.sleepTime > Duration.zero)
            InfoRow(
              label: AppStrings.workedWhileMachineSlept,
              value: formatHm(s.sleepTime),
              icon: Icons.bedtime_rounded,
              valueColor: AppColors.pink,
            ),
          if (s.breaks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Breaks',
                style: context.text.labelMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
            for (final b in s.breaks)
              InfoRow(
                label:
                    '${formatTime(b.start)} – ${b.open ? 'now' : formatTime(b.end)}${b.note == null ? '' : ' · ${b.note}'}',
                value: formatHm(b.duration),
                icon: Icons.coffee_rounded,
                valueColor: AppColors.warning,
              ),
          ],
        ],
      ),
    );
  }
}

/// Visual timeline for one day.
class DayTimelineCard extends StatelessWidget {
  final Insights insights;
  final DateTime day;

  const DayTimelineCard({super.key, required this.insights, required this.day});

  @override
  Widget build(BuildContext context) {
    final dayStart = DateUtils.dateOnly(day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    bool inDay(DateTime s, DateTime e) =>
        e.isAfter(dayStart) && s.isBefore(dayEnd);

    final segments = <TimelineSegment>[
      for (final s in insights.sessions)
        for (final w in s.workIntervals)
          if (inDay(w.start, w.end))
            TimelineSegment(w.start, w.end, SegmentKind.work),
      for (final s in insights.sessions)
        for (final b in s.breaks)
          if (inDay(b.start, b.end))
            TimelineSegment(
              b.start,
              b.end,
              SegmentKind.breakTime,
              label: b.note ?? 'Break',
            ),
      for (final s in insights.sessions)
        for (final z in s.sleep)
          if (inDay(z.start, z.end))
            TimelineSegment(z.start, z.end, SegmentKind.sleep),
    ];
    final appIndex = {
      for (var i = 0; i < insights.apps.length; i++) insights.apps[i].name: i,
    };
    final apps = [
      for (final a in insights.activities)
        if (inDay(a.start, a.end) && a.duration.inSeconds >= 20)
          TimelineSegment(
            a.start,
            a.end,
            SegmentKind.app,
            label: a.title == null ? a.app : '${a.app} — ${a.title}',
            color: AppColors.chartAt(appIndex[a.app] ?? 0),
          ),
    ];

    return AppCard(
      title: AppStrings.timeline,
      subtitle: DateFormat('EEEE d MMMM').format(day),
      icon: Icons.view_timeline_rounded,
      child: segments.isEmpty
          ? const SizedBox(
              height: 140,
              child: EmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: AppStrings.nothingTrackedThisDay,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DayTimelineBar(day: day, segments: segments, apps: apps),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    LegendDot(color: AppColors.primary, label: AppStrings.working),
                    LegendDot(color: AppColors.warning, label: AppStrings.breakText),
                    LegendDot(
                      color: AppColors.pink,
                      label: AppStrings.workedWhileAsleep,
                    ),
                    LegendDot(color: AppColors.cyan, label: AppStrings.appsThinLane),
                    LegendDot(color: AppColors.danger, label: AppStrings.now),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Chronological app log with search.
class ActivityLogCard extends StatefulWidget {
  final Insights insights;
  const ActivityLogCard({super.key, required this.insights});

  @override
  State<ActivityLogCard> createState() => _ActivityLogCardState();
}

class _ActivityLogCardState extends State<ActivityLogCard> {
  /// Search text and how many rows are revealed.
  final _filter = ValueNotifier<({String query, int shown})>((
    query: '',
    shown: 25,
  ));

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<({String query, int shown})>(
        valueListenable: _filter,
        builder: (context, f, _) => _build(context, f.query, f.shown),
      );

  Widget _build(BuildContext context, String query, int shown) {
    final colors = context.colors;
    final q = query.toLowerCase();
    final entries = widget.insights.activities
        .where(
          (a) =>
              q.isEmpty ||
              a.app.toLowerCase().contains(q) ||
              (a.title?.toLowerCase().contains(q) ?? false),
        )
        .toList()
        .reversed
        .toList();
    final appIndex = {
      for (var i = 0; i < widget.insights.apps.length; i++)
        widget.insights.apps[i].name: i,
    };
    return AppCard(
      title: AppStrings.activityLog,
      subtitle: '${widget.insights.activities.length} app switches',
      icon: Icons.receipt_long_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchField(
            hint: 'Filter by app or window',
            width: double.infinity,
            onChanged: (v) => _filter.value = (query: v, shown: 25),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: AppStrings.noMatchingActivity,
              ),
            )
          else ...[
            for (final a in entries.take(shown))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        formatTime(a.start),
                        style: context.text.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Container(
                      width: 3,
                      height: 34,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: AppColors.chartAt(appIndex[a.app] ?? 0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.app,
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (a.title != null)
                            Text(
                              a.title!,
                              style: context.text.bodySmall?.copyWith(
                                color: colors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(formatHm(a.duration), style: context.text.bodySmall),
                  ],
                ),
              ),
            if (entries.length > shown)
              Center(
                child: TextButton(
                  onPressed: () =>
                      _filter.value = (query: query, shown: shown + 50),
                  child: Text('Show more (${entries.length - shown} left)'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Month calendar shaded by hours.
class HeatmapCard extends StatelessWidget {
  final Insights insights;
  final int year;
  final int month;
  final Duration goal;
  final ValueChanged<DateTime>? onDayTap;

  const HeatmapCard({
    super.key,
    required this.insights,
    required this.year,
    required this.month,
    this.goal = const Duration(hours: 8),
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final values = <int, Duration>{
      for (final e in insights.daily.entries)
        if (e.key.year == year && e.key.month == month) e.key.day: e.value,
    };
    final metGoal = values.values.where((d) => d >= goal).length;
    return AppCard(
      title: AppStrings.calendar,
      subtitle:
          '$metGoal day${metGoal == 1 ? '' : 's'} hit the ${formatHm(goal)} goal',
      icon: Icons.calendar_month_rounded,
      child: Column(
        children: [
          CalendarHeatmap(
            year: year,
            month: month,
            values: values,
            goal: goal,
            onTap: onDayTap,
          ),
          const SizedBox(height: 14),
          const HeatLegend(),
        ],
      ),
    );
  }
}

/// Work-habit highlights.
class HabitsCard extends StatelessWidget {
  final Insights insights;
  final Duration goal;
  const HabitsCard({
    super.key,
    required this.insights,
    this.goal = const Duration(hours: 8),
  });

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final (start, end) = i.averageStartEnd;
    final best = i.bestDay;
    final goalDays = i.daily.values.where((d) => d >= goal).length;
    final breakShare = i.total.inSeconds == 0
        ? 0
        : (i.breakTotal.inSeconds /
                  (i.total.inSeconds + i.breakTotal.inSeconds) *
                  100)
              .round();
    return AppCard(
      title: AppStrings.workHabits,
      icon: Icons.psychology_rounded,
      child: Column(
        children: [
          InfoRow(
            icon: Icons.wb_sunny_rounded,
            label: AppStrings.usualStart,
            value: _tod(start),
          ),
          InfoRow(
            icon: Icons.nights_stay_rounded,
            label: AppStrings.usualFinish,
            value: _tod(end),
          ),
          InfoRow(
            icon: Icons.local_fire_department_rounded,
            label: AppStrings.currentStreak,
            value: '${i.streak} day${i.streak == 1 ? '' : 's'}',
            valueColor: AppColors.warning,
          ),
          InfoRow(
            icon: Icons.emoji_events_rounded,
            label: AppStrings.bestDay,
            value: best == null
                ? '—'
                : '${DateFormat('d MMM').format(best.key)} · ${formatHm(best.value)}',
          ),
          InfoRow(
            icon: Icons.flag_rounded,
            label: AppStrings.daysAtGoal,
            value: '$goalDays of ${i.activeDays}',
            valueColor: AppColors.success,
          ),
          InfoRow(
            icon: Icons.coffee_rounded,
            label: AppStrings.breakShare,
            value: '$breakShare%',
          ),
          InfoRow(
            icon: Icons.center_focus_strong_rounded,
            label: AppStrings.focusTop3Apps,
            value: '${(i.focusScore * 100).round()}%',
          ),
          if (i.sleepTotal > Duration.zero)
            InfoRow(
              icon: Icons.bedtime_rounded,
              label: AppStrings.workedWhileAsleep,
              value: formatHm(i.sleepTotal),
              valueColor: AppColors.pink,
            ),
        ],
      ),
    );
  }
}

/// Day-by-day table (wide) or list (phone) for a month or range.
class DailyTableCard extends StatelessWidget {
  final Insights insights;
  final Duration goal;
  final ValueChanged<DateTime>? onDayTap;

  const DailyTableCard({
    super.key,
    required this.insights,
    this.goal = const Duration(hours: 8),
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = insights.daily.keys.where((d) => !d.isAfter(today)).toList()
      ..sort((a, b) => b.compareTo(a));

    // Per-day aggregates from sessions
    final breaks = <DateTime, Duration>{};
    final counts = <DateTime, int>{};
    final firstIn = <DateTime, DateTime>{};
    final lastOut = <DateTime, DateTime>{};
    for (final s in insights.sessions) {
      final d = DateUtils.dateOnly(s.start);
      counts[d] = (counts[d] ?? 0) + 1;
      breaks[d] = (breaks[d] ?? Duration.zero) + s.breakTime;
      if (firstIn[d] == null || s.start.isBefore(firstIn[d]!)) {
        firstIn[d] = s.start;
      }
      if (lastOut[d] == null || s.end.isAfter(lastOut[d]!)) lastOut[d] = s.end;
    }

    Widget status(Duration worked) {
      if (worked == Duration.zero) {
        return StatusPill(label: AppStrings.off, color: colors.textSubtle);
      }
      if (worked >= goal) {
        return const StatusPill(
          label: AppStrings.goalMet,
          color: AppColors.success,
          icon: Icons.check_rounded,
        );
      }
      if (worked >= goal * 0.5) {
        return const StatusPill(label: AppStrings.partial, color: AppColors.warning);
      }
      return const StatusPill(label: AppStrings.short, color: AppColors.danger);
    }

    final compact = context.isPhone;
    final num = context.text.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final head = context.text.labelMedium?.copyWith(color: colors.textMuted);

    return AppCard(
      title: AppStrings.dayByDay,
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
                  Expanded(flex: 2, child: Text('In', style: head)),
                  Expanded(flex: 2, child: Text('Out', style: head)),
                  Expanded(flex: 2, child: Text('Sessions', style: head)),
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
                      child: Text('Status', style: head),
                    ),
                  ),
                ],
              ),
            ),
          for (final d in days)
            InkWell(
              onTap: onDayTap == null ? null : () => onDayTap!(d),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: d == today
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border(
                    top: BorderSide(
                      color: colors.border.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: compact
                    ? Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('EEE d MMM').format(d),
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  firstIn[d] == null
                                      ? 'No sessions'
                                      : '${formatTime(firstIn[d])} – ${formatTime(lastOut[d])} · ${counts[d]} sessions',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatHm(insights.daily[d]!),
                                style: num?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              status(insights.daily[d]!),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              DateFormat('EEE, d MMM').format(d),
                              style: context.text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(formatTime(firstIn[d]), style: num),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(formatTime(lastOut[d]), style: num),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('${counts[d] ?? 0}', style: num),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHm(breaks[d] ?? Duration.zero),
                              style: num,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHm(insights.daily[d]!),
                              style: num?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: status(insights.daily[d]!),
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
}
