import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/csv_export.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/insights.dart';
import '../data/insights_repository.dart';
import 'insight_cards.dart';
import 'insights_controllers.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Tabbed analytics for one user: Overview · Day · Month · Apps.
/// Used by "My activity" and by the admin member profile.
///
/// Each tab is driven by its own [InsightsController], provided here so the
/// period survives tab switches and "open this day" works across tabs.
class InsightsTabs extends StatelessWidget {
  final String userId;
  final String userName;
  final Duration goal;

  /// Rendered above the tab bar (e.g. a profile header).
  final Widget? header;
  final int initialTab;

  const InsightsTabs({
    super.key,
    required this.userId,
    required this.userName,
    this.goal = const Duration(hours: 8),
    this.header,
    this.initialTab = 0,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.read<InsightsRepository>();
    return MultiProvider(
      key: ValueKey(userId),
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              RangeInsightsController(repository: repo, userId: userId),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              DayInsightsController(repository: repo, userId: userId),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              MonthInsightsController(repository: repo, userId: userId),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AppsInsightsController(repository: repo, userId: userId),
        ),
      ],
      child: DefaultTabController(
        length: 4,
        initialIndex: initialTab,
        child: Builder(
          builder: (context) {
            // Jump to the Day tab showing [d].
            void openDay(DateTime d) {
              context.read<DayInsightsController>().setDay(d);
              DefaultTabController.of(context).animateTo(1);
            }

            final gutter = context.gutter;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?header,
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                  child: const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(
                        icon: Icon(Icons.insights_rounded, size: 18),
                        text: 'Overview',
                        iconMargin: EdgeInsets.zero,
                        height: 56,
                      ),
                      Tab(
                        icon: Icon(Icons.today_rounded, size: 18),
                        text: 'Day',
                        iconMargin: EdgeInsets.zero,
                        height: 56,
                      ),
                      Tab(
                        icon: Icon(Icons.calendar_month_rounded, size: 18),
                        text: 'Month',
                        iconMargin: EdgeInsets.zero,
                        height: 56,
                      ),
                      Tab(
                        icon: Icon(Icons.apps_rounded, size: 18),
                        text: 'Apps',
                        iconMargin: EdgeInsets.zero,
                        height: 56,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    children: [
                      KeepAlivePage(
                        child: RangeInsightsView(
                          goal: goal,
                          onOpenDay: openDay,
                        ),
                      ),
                      KeepAlivePage(child: DayInsightsView(goal: goal)),
                      KeepAlivePage(
                        child: MonthInsightsView(
                          userName: userName,
                          goal: goal,
                          onOpenDay: openDay,
                        ),
                      ),
                      const KeepAlivePage(child: AppsInsightsView()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared scaffolding
// -----------------------------------------------------------------------------

/// Scrollable column with toolbar, loading skeleton and pull-to-refresh,
/// rendering whatever state [controller] is in.
class _InsightScroll extends StatelessWidget {
  final InsightsController controller;
  final Widget toolbar;
  final List<Widget> Function(Insights i) children;

  const _InsightScroll({
    required this.controller,
    required this.toolbar,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    final data = controller.data;
    final List<Widget> body;
    if (controller.error != null && data == null) {
      body = [ErrorState(error: controller.error, onRetry: controller.refresh)];
    } else if (data == null) {
      body = const [
        _KpiSkeleton(),
        SkeletonCard(height: 280),
        SkeletonCard(height: 240),
      ];
    } else {
      body = children(data);
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 32),
        itemCount: body.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (context, i) => ContentWidth(
          child: i == 0 ? toolbar : (data != null ? body[i - 1] : body[i - 1]),
        ),
      ),
    );
  }
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton();

  @override
  Widget build(BuildContext context) => const AdaptiveGrid(
    phoneMinItemWidth: 150,
    minItemWidth: 200,
    spacing: 14,
    children: [
      SkeletonCard(height: 150),
      SkeletonCard(height: 150),
      SkeletonCard(height: 150),
      SkeletonCard(height: 150),
    ],
  );
}

Widget _toolbar(List<Widget> left, [List<Widget> right = const []]) {
  return Wrap(
    spacing: 10,
    runSpacing: 10,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: left,
      ),
      if (right.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: right,
        ),
    ],
  );
}

Widget _refreshButton(InsightsController c) => IconButton(
  tooltip: AppStrings.refresh,
  onPressed: c.isLoading ? null : c.refresh,
  icon: c.isLoading && c.data != null
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.refresh_rounded),
);

// -----------------------------------------------------------------------------
// Overview (range)
// -----------------------------------------------------------------------------

class RangeInsightsView extends StatelessWidget {
  final Duration goal;
  final ValueChanged<DateTime>? onOpenDay;

  const RangeInsightsView({super.key, required this.goal, this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RangeInsightsController>();
    return _InsightScroll(
      controller: c,
      toolbar: _toolbar(
        [
          SegmentedTabs<int>(
            items: const [
              (7, '7 days'),
              (14, '14 days'),
              (30, '30 days'),
              (90, '90 days'),
            ],
            value: c.period,
            onChanged: c.setPeriod,
          ),
        ],
        [_refreshButton(c)],
      ),
      children: (i) => [
        InsightKpis(insights: i, goal: goal),
        DailyTrendCard(
          insights: i,
          goal: goal,
          onDayTap: onOpenDay,
          title: 'Last ${c.period} days',
        ),
        SplitPanes(
          primary: AppUsageCard(insights: i),
          secondary: HabitsCard(insights: i, goal: goal),
        ),
        SplitPanes(
          primaryFlex: 1,
          secondaryFlex: 1,
          primary: HourlyCard(insights: i),
          secondary: WeekdayCard(insights: i),
        ),
        SessionsCard(insights: i, limit: 6, title: AppStrings.recentSessions),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Day
// -----------------------------------------------------------------------------

class DayInsightsView extends StatelessWidget {
  final Duration goal;
  const DayInsightsView({super.key, required this.goal});

  Future<void> _pick(BuildContext context, DayInsightsController c) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: c.period,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) c.setDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DayInsightsController>();
    final day = c.period;
    return _InsightScroll(
      controller: c,
      toolbar: _toolbar(
        [
          PeriodStepper(
            label: c.isToday
                ? 'Today · ${DateFormat('d MMM').format(day)}'
                : DateFormat(
                    context.isPhone ? 'EEE d MMM' : 'EEEE, d MMMM y',
                  ).format(day),
            onPrevious: () => c.shift(-1),
            onNext: c.isToday ? null : () => c.shift(1),
            onTapLabel: () => _pick(context, c),
            onToday: c.isToday ? null : c.today,
          ),
        ],
        [_refreshButton(c)],
      ),
      children: (i) => [
        InsightKpis(insights: i, goal: goal, singleDay: true),
        DayTimelineCard(insights: i, day: day),
        SplitPanes(
          primaryFlex: 1,
          secondaryFlex: 1,
          primary: HourlyCard(insights: i, perDay: true),
          secondary: AppUsageCard(insights: i, limit: 5),
        ),
        SessionsCard(insights: i),
        if (i.activities.isNotEmpty) ActivityLogCard(insights: i),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Month
// -----------------------------------------------------------------------------

class MonthInsightsView extends StatelessWidget {
  final String userName;
  final Duration goal;
  final ValueChanged<DateTime>? onOpenDay;

  const MonthInsightsView({
    super.key,
    required this.userName,
    required this.goal,
    this.onOpenDay,
  });

  Future<void> _export(BuildContext context, DateTime month, Insights i) {
    final days = i.daily.keys.toList()..sort();
    final byDay = <DateTime, List<SessionInfo>>{};
    for (final s in i.sessions) {
      byDay.putIfAbsent(DateUtils.dateOnly(s.start), () => []).add(s);
    }
    return exportCsv(
      context,
      filename:
          'timetrak-${userName.replaceAll(RegExp(r'\W+'), '_')}-${DateFormat('yyyy-MM').format(month)}.csv',
      header: const [
        'Date',
        'Weekday',
        'First in',
        'Last out',
        'Sessions',
        'Breaks (min)',
        'Worked (h)',
      ],
      rows: [
        for (final d in days)
          [
            DateFormat('yyyy-MM-dd').format(d),
            DateFormat('EEEE').format(d),
            byDay[d] == null
                ? ''
                : formatTime(
                    byDay[d]!
                        .map((s) => s.start)
                        .reduce((a, b) => a.isBefore(b) ? a : b),
                  ),
            byDay[d] == null
                ? ''
                : formatTime(
                    byDay[d]!
                        .map((s) => s.end)
                        .reduce((a, b) => a.isAfter(b) ? a : b),
                  ),
            byDay[d]?.length ?? 0,
            (byDay[d] ?? const <SessionInfo>[]).fold<int>(
              0,
              (a, s) => a + s.breakTime.inMinutes,
            ),
            (i.daily[d]!.inMinutes / 60).toStringAsFixed(2),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MonthInsightsController>();
    final month = c.period;
    final data = c.data;
    return _InsightScroll(
      controller: c,
      toolbar: _toolbar(
        [
          PeriodStepper(
            label: DateFormat('MMMM y').format(month),
            onPrevious: () => c.shift(-1),
            onNext: c.isCurrent ? null : () => c.shift(1),
            onTapLabel: () async {
              final picked = await showMonthPicker(context, month);
              if (picked != null) c.setMonth(picked);
            },
            onToday: c.isCurrent ? null : c.current,
          ),
        ],
        [
          OutlinedButton.icon(
            onPressed: data == null
                ? null
                : () => _export(context, month, data),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text(AppStrings.exportCsv),
          ),
          _refreshButton(c),
        ],
      ),
      children: (i) => [
        InsightKpis(insights: i, goal: goal),
        SplitPanes(
          primaryFlex: 2,
          secondaryFlex: 3,
          primary: HeatmapCard(
            insights: i,
            year: month.year,
            month: month.month,
            goal: goal,
            onDayTap: onOpenDay,
          ),
          secondary: DailyTrendCard(
            insights: i,
            goal: goal,
            onDayTap: onOpenDay,
          ),
        ),
        SplitPanes(
          primary: AppUsageCard(insights: i),
          secondary: HabitsCard(insights: i, goal: goal),
        ),
        DailyTableCard(insights: i, goal: goal, onDayTap: onOpenDay),
      ],
    );
  }
}

/// Simple month grid picker (the Material date picker has no month mode).
Future<DateTime?> showMonthPicker(
  BuildContext context,
  DateTime initial,
) async {
  final year = ValueNotifier(initial.year);
  final now = DateTime.now();
  final result = await showDialog<DateTime>(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: year,
      builder: (ctx, y, _) => AlertDialog(
        title: Row(
          children: [
            IconButton(
              onPressed: () => year.value--,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(child: Text('$y', textAlign: TextAlign.center)),
            IconButton(
              onPressed: y >= now.year ? null : () => year.value++,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.8,
            children: [
              for (var m = 1; m <= 12; m++)
                if (y == initial.year && m == initial.month)
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, DateTime(y, m)),
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(DateFormat('MMM').format(DateTime(y, m))),
                  )
                else
                  OutlinedButton(
                    onPressed: y > now.year || (y == now.year && m > now.month)
                        ? null
                        : () => Navigator.pop(ctx, DateTime(y, m)),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(DateFormat('MMM').format(DateTime(y, m))),
                  ),
            ],
          ),
        ),
      ),
    ),
  );
  year.dispose();
  return result;
}

// -----------------------------------------------------------------------------
// Apps
// -----------------------------------------------------------------------------

class AppsInsightsView extends StatelessWidget {
  const AppsInsightsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppsInsightsController>();
    return _InsightScroll(
      controller: c,
      toolbar: _toolbar(
        [
          SegmentedTabs<int>(
            items: const [(1, 'Today'), (7, '7 days'), (30, '30 days')],
            value: c.period,
            onChanged: c.setPeriod,
          ),
          SearchField(
            hint: 'Search apps and windows',
            onChanged: c.setQuery,
            width: 260,
          ),
        ],
        [_refreshButton(c)],
      ),
      children: (i) {
        final q = c.query.toLowerCase();
        final apps = i.apps
            .where(
              (a) =>
                  q.isEmpty ||
                  a.name.toLowerCase().contains(q) ||
                  a.windows.keys.any((w) => w.toLowerCase().contains(q)),
            )
            .toList();
        final total = i.appTotal;
        return [
          AdaptiveGrid(
            phoneMinItemWidth: 150,
            minItemWidth: 200,
            spacing: 14,
            children: [
              KpiCard.duration(
                label: AppStrings.timeInApps,
                duration: total,
                icon: Icons.apps_rounded,
                color: AppColors.primary,
              ),
              KpiCard(
                label: AppStrings.distinctApps,
                numeric: i.apps.length.toDouble(),
                format: (v) => '${v.round()}',
                icon: Icons.category_rounded,
                color: AppColors.cyan,
              ),
              KpiCard(
                label: AppStrings.appSwitches,
                numeric: i.activities.length.toDouble(),
                format: (v) => '${v.round()}',
                icon: Icons.swap_horiz_rounded,
                color: AppColors.violet,
              ),
              KpiCard(
                label: AppStrings.focusTop3,
                value: '${(i.focusScore * 100).round()}%',
                icon: Icons.center_focus_strong_rounded,
                color: AppColors.success,
              ),
            ],
          ),
          AppUsageCard(insights: i, limit: 8, title: AppStrings.shareOfTime),
          AppCard(
            title: AppStrings.appsAndWindows,
            subtitle:
                '${apps.length} apps${q.isEmpty ? '' : ' matching "${c.query}"'}',
            icon: Icons.web_asset_rounded,
            bodyPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: apps.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: AppStrings.noAppsFound,
                    ),
                  )
                : Column(
                    children: [
                      for (final a in apps)
                        _AppTile(
                          usage: a,
                          color: AppColors.chartAt(i.apps.indexOf(a)),
                          total: total,
                          filter: q,
                        ),
                    ],
                  ),
          ),
        ];
      },
    );
  }
}

class _AppTile extends StatelessWidget {
  final AppUsage usage;
  final Color color;
  final Duration total;
  final String filter;

  const _AppTile({
    required this.usage,
    required this.color,
    required this.total,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final windows = usage.topWindows
        .where(
          (w) =>
              filter.isEmpty ||
              w.key.toLowerCase().contains(filter) ||
              usage.name.toLowerCase().contains(filter),
        )
        .toList();
    final share = total.inSeconds == 0
        ? 0.0
        : usage.total.inSeconds / total.inSeconds;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        leading: IconBadge(icon: Icons.window_rounded, color: color, size: 36),
        title: Text(
          usage.name,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${(share * 100).toStringAsFixed(1)}% · ${usage.switches} switches · ${usage.windows.length} windows',
          style: context.text.bodySmall,
        ),
        trailing: Text(formatHm(usage.total), style: context.text.titleSmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final w in windows.take(30))
            ShareBar(
              label: w.key,
              trailing: formatHm(w.value),
              fraction: usage.total.inSeconds == 0
                  ? 0
                  : w.value.inSeconds / usage.total.inSeconds,
              color: color,
            ),
          if (windows.length > 30)
            Text(
              '+${windows.length - 30} more windows',
              style: context.text.bodySmall,
            ),
        ],
      ),
    );
  }
}
