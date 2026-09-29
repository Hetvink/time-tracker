import 'package:flutter/material.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/company_invitation.dart';
import '../../../../data/models/team_member.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class Attention extends StatelessWidget {
  final List<TeamMember> members;
  final List<CompanyInvitation> invitations;
  final ValueChanged<TeamMember> onOpen;
  final VoidCallback onShowInvitations;

  const Attention({
    super.key,
    required this.members,
    required this.invitations,
    required this.onOpen,
    required this.onShowInvitations,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final quiet = members
        .where(
          (m) =>
              m.isActive &&
              !m.isWorking &&
              (m.lastSeenAt == null ||
                  now.difference(m.lastSeenAt!).inDays >= 3),
        )
        .toList();
    final expiring = invitations
        .where((i) => i.isOpen && i.expiresAt.difference(now).inDays < 2)
        .toList();
    final deactivated = members.where((m) => !m.isActive).toList();

    final rows = <Widget>[
      for (final m in quiet.take(5))
        AttentionRow(
          icon: Icons.hourglass_disabled_rounded,
          color: AppColors.warning,
          title: m.displayName,
          subtitle: m.lastSeenAt == null
              ? 'Has never tracked time'
              : 'No tracking for ${now.difference(m.lastSeenAt!).inDays} days',
          onTap: () => onOpen(m),
        ),
      for (final i in expiring.take(3))
        AttentionRow(
          icon: Icons.schedule_send_rounded,
          color: AppColors.info,
          title: i.email,
          subtitle:
              'Invitation expires ${formatRelative(i.expiresAt).replaceAll(' ago', '')} — resend?',
          onTap: onShowInvitations,
        ),
      for (final m in deactivated.take(3))
        AttentionRow(
          icon: Icons.person_off_rounded,
          color: AppColors.danger,
          title: m.displayName,
          subtitle: AppStrings.accountDeactivated,
          onTap: () => onOpen(m),
        ),
    ];
    return AppCard(
      title: AppStrings.needsAttention,
      subtitle: rows.isEmpty
          ? 'All good'
          : '${rows.length} item${rows.length == 1 ? '' : 's'}',
      icon: Icons.notifications_active_rounded,
      bodyPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: rows.isEmpty
          ? const SizedBox(
              height: 200,
              child: EmptyState(
                icon: Icons.verified_rounded,
                title: AppStrings.everythingLooksHealthy,
                color: AppColors.success,
              ),
            )
          : Column(children: rows),
    );
  }
}

class AttentionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const AttentionRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: IconBadge(icon: icon, color: color, size: 36),
      title: Text(
        title,
        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: context.text.bodySmall),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: context.colors.textSubtle,
      ),
    );
  }
}

// =============================================================================
// Members
// =============================================================================

/// Search / filter / sort / view-mode state of the Members tab.
