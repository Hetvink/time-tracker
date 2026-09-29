import 'package:flutter/material.dart';

import '../../../../../../core/widgets/charts.dart';
import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/company_invitation.dart';
import '../../../../data/models/team_member.dart';
import 'attention.dart';
import 'leaderboard.dart';
import 'live_board.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class OverviewTab extends StatelessWidget {
  final List<TeamMember> members;
  final List<CompanyInvitation> invitations;
  final Future<void> Function() onRefresh;
  final ValueChanged<TeamMember> onOpen;
  final VoidCallback? onInvite;
  final VoidCallback onShowInvitations;

  const OverviewTab({
    super.key,
    required this.members,
    required this.invitations,
    required this.onRefresh,
    required this.onOpen,
    required this.onInvite,
    required this.onShowInvitations,
  });

  @override
  Widget build(BuildContext context) {
    final active = members.where((m) => m.isActive).toList();
    final working = active.where((m) => m.isWorking && !m.isOnBreak).toList()
      ..sort(
        (a, b) => (a.sessionStartedAt ?? DateTime.now()).compareTo(
          b.sessionStartedAt ?? DateTime.now(),
        ),
      );
    final onBreak = active.where((m) => m.isOnBreak).toList();
    final offline = active.length - working.length - onBreak.length;
    final deactivated = members.length - active.length;
    Duration sum(Duration Function(TeamMember) f) =>
        members.fold(Duration.zero, (a, m) => a + f(m));
    final today = sum((m) => m.today);
    final week = sum((m) => m.week);
    final month = sum((m) => m.month);

    if (members.isEmpty) {
      return EmptyState(
        icon: Icons.group_add_rounded,
        title: AppStrings.noMembersYet,
        message: 'Invite your team to start tracking time together.',
        action: onInvite == null
            ? null
            : GradientButton(
                label: AppStrings.inviteMembers,
                icon: Icons.person_add_alt_1_rounded,
                onPressed: onInvite,
              ),
      );
    }

    final items = <Widget>[
      AdaptiveGrid(
        phoneMinItemWidth: 150,
        minItemWidth: 190,
        maxColumns: 6,
        spacing: 14,
        children: [
          KpiCard(
            label: AppStrings.members2,
            numeric: members.length.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.groups_rounded,
            color: AppColors.primary,
            caption: deactivated == 0
                ? 'All active'
                : '$deactivated deactivated',
          ),
          KpiCard(
            label: AppStrings.workingNow,
            numeric: working.length.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.bolt_rounded,
            color: AppColors.success,
            caption:
                '${(working.length / (active.isEmpty ? 1 : active.length) * 100).round()}% of team',
          ),
          KpiCard(
            label: AppStrings.onBreak,
            numeric: onBreak.length.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.coffee_rounded,
            color: AppColors.warning,
          ),
          KpiCard.duration(
            label: AppStrings.teamToday,
            duration: today,
            icon: Icons.today_rounded,
            color: AppColors.cyan,
            caption:
                'Avg ${formatHm(today ~/ (active.isEmpty ? 1 : active.length))}/person',
          ),
          KpiCard.duration(
            label: AppStrings.teamThisWeek,
            duration: week,
            icon: Icons.date_range_rounded,
            color: AppColors.violet,
          ),
          KpiCard.duration(
            label: AppStrings.teamThisMonth,
            duration: month,
            icon: Icons.calendar_month_rounded,
            color: AppColors.pink,
          ),
        ],
      ),
      SplitPanes(
        primary: LiveBoard(working: working, onBreak: onBreak, onOpen: onOpen),
        secondary: AppCard(
          title: AppStrings.statusMix,
          subtitle: AppStrings.rightNow,
          icon: Icons.donut_large_rounded,
          child: Center(
            child: Column(
              children: [
                DonutChart(
                  size: 200,
                  centerValue: '${working.length}/${active.length}',
                  centerLabel: 'working',
                  slices: [
                    DonutSlice(
                      'Working',
                      working.length.toDouble(),
                      AppColors.success,
                    ),
                    DonutSlice(
                      'On break',
                      onBreak.length.toDouble(),
                      AppColors.warning,
                    ),
                    DonutSlice('Offline', offline.toDouble(), AppColors.idle),
                    DonutSlice(
                      'Deactivated',
                      deactivated.toDouble(),
                      AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    LegendDot(
                      color: AppColors.success,
                      label: 'Working ${working.length}',
                    ),
                    LegendDot(
                      color: AppColors.warning,
                      label: 'Break ${onBreak.length}',
                    ),
                    LegendDot(color: AppColors.idle, label: 'Offline $offline'),
                    if (deactivated > 0)
                      LegendDot(
                        color: AppColors.danger,
                        label: 'Deactivated $deactivated',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      SplitPanes(
        primary: Leaderboard(members: members, onOpen: onOpen),
        secondary: Attention(
          members: members,
          invitations: invitations,
          onOpen: onOpen,
          onShowInvitations: onShowInvitations,
        ),
      ),
    ];

    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (context, i) => ContentWidth(child: items[i]),
      ),
    );
  }
}

/// Grid of members who are working right now, with ticking timers.
