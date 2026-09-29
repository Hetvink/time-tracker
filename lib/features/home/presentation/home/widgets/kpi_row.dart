import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/insights/data/insights.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class KpiRow extends StatelessWidget {
  final Insights? insights;
  final Duration goal;
  final bool loading;
  const KpiRow({
    super.key,
    required this.insights,
    required this.goal,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(now.year, now.month);

    Duration sum(bool Function(DateTime d) test) => i == null
        ? Duration.zero
        : i.daily.entries
              .where((e) => test(e.key))
              .fold(Duration.zero, (a, e) => a + e.value);

    final week = sum((d) => !d.isBefore(weekStart));
    final lastWeekSameSpan = sum(
      (d) =>
          !d.isBefore(weekStart.subtract(const Duration(days: 7))) &&
          d.isBefore(today.subtract(const Duration(days: 6))),
    );
    final month = sum((d) => !d.isBefore(monthStart));
    final monthDays = i == null
        ? 0
        : i.daily.entries
              .where(
                (e) => !e.key.isBefore(monthStart) && e.value > Duration.zero,
              )
              .length;
    final weekSpark = i == null
        ? null
        : [
            for (var d = 0; d < 7; d++)
              (i.daily[weekStart.add(Duration(days: d))] ?? Duration.zero)
                      .inMinutes /
                  60,
          ];
    final delta = lastWeekSameSpan.inSeconds == 0
        ? null
        : (week.inSeconds - lastWeekSameSpan.inSeconds) /
              lastWeekSameSpan.inSeconds;
    final weekTarget = goal * math.min(5, today.weekday);

    return AdaptiveGrid(
      phoneMinItemWidth: 150,
      minItemWidth: 210,
      spacing: 14,
      children: [
        KpiCard.duration(
          label: AppStrings.thisWeek,
          duration: week,
          icon: Icons.date_range_rounded,
          color: AppColors.primary,
          delta: delta,
          caption: 'Target so far ${formatHm(weekTarget)}',
          spark: weekSpark,
          loading: loading,
        ),
        KpiCard.duration(
          label: DateFormat('MMMM').format(now),
          duration: month,
          icon: Icons.calendar_month_rounded,
          color: AppColors.cyan,
          caption: '$monthDays working days',
          loading: loading,
        ),
        KpiCard.duration(
          label: AppStrings.dailyAverage,
          duration: monthDays == 0 ? Duration.zero : month ~/ monthDays,
          icon: Icons.speed_rounded,
          color: AppColors.violet,
          caption: 'Goal ${formatHm(goal)}',
          loading: loading,
        ),
        KpiCard(
          label: AppStrings.sessionsThisMonth,
          numeric:
              (i?.sessions.where((s) => !s.start.isBefore(monthStart)).length ??
                      0)
                  .toDouble(),
          format: (v) => '${v.round()}',
          icon: Icons.layers_rounded,
          color: AppColors.success,
          caption: i == null ? null : 'Longest ${formatHm(i.longestSession)}',
          loading: loading,
        ),
      ],
    );
  }
}
