import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/charts.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/routes/navigation_provider.dart';
import 'package:time_trak/features/insights/data/insights.dart';

class WeekCard extends StatelessWidget {
  final Insights insights;
  final Duration goal;
  const WeekCard({super.key, required this.insights, required this.goal});

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var d = 0; d < 7; d++) start.add(Duration(days: d))];
    final total = days.fold(
      Duration.zero,
      (a, d) => a + (insights.daily[d] ?? Duration.zero),
    );
    return AppCard(
      title: 'This week',
      subtitle: '${formatHm(total)} tracked · tap a day for details',
      icon: Icons.bar_chart_rounded,
      child: HoursBarChart(
        height: 240,
        goal: goal.inMinutes / 60,
        onTap: (_) =>
            context.read<NavigationProvider>().selectIndex(NavIndex.activity),
        data: [
          for (final d in days)
            BarDatum(
              DateFormat('E').format(d),
              (insights.daily[d] ?? Duration.zero).inMinutes / 60,
              tooltip:
                  '${DateFormat('d MMM').format(d)} · ${formatHm(insights.daily[d] ?? Duration.zero)}',
              highlight: d == today,
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Admin snapshots
// -----------------------------------------------------------------------------
