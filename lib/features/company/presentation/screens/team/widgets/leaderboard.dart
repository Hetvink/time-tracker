import 'package:flutter/material.dart';

import '../../../../../../core/widgets/charts.dart';
import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/team_member.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class Leaderboard extends StatelessWidget {
  final List<TeamMember> members;
  final ValueChanged<TeamMember> onOpen;
  const Leaderboard({super.key, required this.members, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final sorted = [...members]..sort((a, b) => b.week.compareTo(a.week));
    final top = sorted.take(10).toList();
    return AppCard(
      title: AppStrings.thisWeek,
      subtitle: AppStrings.hoursPerMember,
      icon: Icons.leaderboard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoursBarChart(
            labelEvery: 1,
            onTap: (i) => onOpen(top[i]),
            data: [
              for (final (i, m) in top.indexed)
                BarDatum(
                  m.displayName.split(' ').first.length > 8
                      ? '${m.displayName.split(' ').first.substring(0, 7)}…'
                      : m.displayName.split(' ').first,
                  m.week.inMinutes / 60,
                  tooltip: '${m.displayName} · ${formatHm(m.week)}',
                  highlight: i == 0 && m.week > Duration.zero,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
