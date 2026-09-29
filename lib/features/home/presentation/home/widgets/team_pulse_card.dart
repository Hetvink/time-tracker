import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/routes/navigation_provider.dart';
import 'package:time_trak/features/company/data/models/team_member.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class TeamPulseCard extends StatelessWidget {
  /// Null while loading.
  final List<TeamMember>? members;
  const TeamPulseCard({super.key, required this.members});

  @override
  Widget build(BuildContext context) {
    final loaded = members != null;
    return Builder(
      builder: (context) {
        final members = this.members ?? const <TeamMember>[];
        final working = members
            .where((m) => m.isWorking && !m.isOnBreak)
            .toList();
        final onBreak = members.where((m) => m.isOnBreak).length;
        final top = [...members]..sort((a, b) => b.today.compareTo(a.today));
        final teamToday = members.fold(Duration.zero, (a, m) => a + m.today);
        return AppCard(
          title: AppStrings.teamPulse,
          subtitle: loaded
              ? '${working.length} working · $onBreak on break · ${formatHm(teamToday)} today'
              : 'Loading team…',
          icon: Icons.groups_rounded,
          actions: [
            TextButton.icon(
              onPressed: () =>
                  context.read<NavigationProvider>().selectIndex(NavIndex.team),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text(AppStrings.openTeam),
            ),
          ],
          child: !loaded
              ? const Skeleton(height: 90)
              : members.isEmpty
              ? Text(
                  'No members yet — invite your team from the Team page.',
                  style: context.text.bodyMedium,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final m in [
                            ...working,
                            ...members.where((m) => !working.contains(m)),
                          ].take(14))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Tooltip(
                                message:
                                    '${m.displayName} · ${m.isOnBreak
                                        ? 'on break'
                                        : m.isWorking
                                        ? 'working'
                                        : 'offline'}',
                                child: UserAvatar(
                                  name: m.displayName,
                                  imageUrl: m.avatarUrl,
                                  radius: 20,
                                  statusColor: m.isOnBreak
                                      ? AppColors.warning
                                      : m.isWorking
                                      ? AppColors.success
                                      : AppColors.idle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final (n, m) in top.take(3).indexed)
                      ShareBar(
                        label: '${['🥇', '🥈', '🥉'][n]}  ${m.displayName}',
                        trailing: formatHm(m.today),
                        fraction: top.first.today.inSeconds == 0
                            ? 0
                            : m.today.inSeconds / top.first.today.inSeconds,
                        color: AppColors.chartAt(n),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
