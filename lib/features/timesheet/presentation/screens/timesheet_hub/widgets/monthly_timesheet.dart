import 'package:time_trak/features/insights/presentation/insight_views.dart'
    show showMonthPicker;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/utils/csv_export.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/settings/presentation/providers/settings_provider.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';
import 'package:time_trak/features/timesheet/presentation/providers/monthly_timesheet_controller.dart';

import 'summary.dart';
import 'days_table.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class MonthlyTimesheet extends StatelessWidget {
  const MonthlyTimesheet({super.key});

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
                label: const Text(AppStrings.exportCsv),
              ),
              IconButton(
                tooltip: AppStrings.refresh,
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
        Summary(days: days, goal: goal),
        DaysTable(days: days, goal: goal),
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
