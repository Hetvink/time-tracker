import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';

class Summary extends StatelessWidget {
  final List<DailyTimeSheet> days;
  final Duration goal;
  const Summary({super.key, required this.days, required this.goal});

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
