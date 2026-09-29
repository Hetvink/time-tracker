import 'package:flutter/material.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/team_member.dart';

class LiveBoard extends StatelessWidget {
  final List<TeamMember> working;
  final List<TeamMember> onBreak;
  final ValueChanged<TeamMember> onOpen;

  const LiveBoard({
    super.key,
    required this.working,
    required this.onBreak,
    required this.onOpen,
  });

  // Session timers tick every second while anyone is working.
  @override
  Widget build(BuildContext context) =>
      Ticking(active: working.isNotEmpty, builder: _build);

  Widget _build(BuildContext context) {
    final all = [...working, ...onBreak];
    return AppCard(
      title: 'Live board',
      subtitle: '${working.length} working · ${onBreak.length} on break',
      icon: Icons.sensors_rounded,
      actions: [
        if (working.isNotEmpty) const PulseDot(color: AppColors.success),
      ],
      child: all.isEmpty
          ? const SizedBox(
              height: 200,
              child: EmptyState(
                icon: Icons.nights_stay_rounded,
                title: 'Nobody is tracking right now',
                color: AppColors.idle,
              ),
            )
          : AdaptiveGrid(
              minItemWidth: 190,
              maxColumns: 3,
              spacing: 12,
              children: [
                for (final m in all)
                  TiltCard(
                    onTap: () => onOpen(m),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color:
                              (m.isOnBreak
                                      ? AppColors.warning
                                      : AppColors.success)
                                  .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            name: m.displayName,
                            imageUrl: m.avatarUrl,
                            radius: 20,
                            statusColor: m.isOnBreak
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.displayName,
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  m.isOnBreak
                                      ? 'On break'
                                      : m.sessionStartedAt == null
                                      ? 'Working'
                                      : formatClock(
                                          DateTime.now().difference(
                                            m.sessionStartedAt!,
                                          ),
                                        ),
                                  style: context.text.bodySmall?.copyWith(
                                    color: m.isOnBreak
                                        ? AppColors.warning
                                        : AppColors.success,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Today ${formatHm(m.today)}',
                                  style: context.text.bodySmall,
                                ),
                              ],
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
