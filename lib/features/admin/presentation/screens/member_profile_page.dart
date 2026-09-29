import 'package:flutter/material.dart';

import '../../../../core/widgets/ui_kit.dart';
import '../../../company/data/models/team_member.dart';
import '../../../insights/presentation/insight_views.dart';

/// Admin view of one member: profile header + full analytics.
class MemberProfilePage extends StatelessWidget {
  final TeamMember member;

  /// Admin actions shown in the header menu (label → action).
  final List<(IconData, String, VoidCallback, bool destructive)> actions;

  const MemberProfilePage({
    super.key,
    required this.member,
    this.actions = const [],
  });

  static Future<void> open(
    BuildContext context,
    TeamMember member, {
    List<(IconData, String, VoidCallback, bool)> actions = const [],
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberProfilePage(member: member, actions: actions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      animate: false,
      intensity: 0.55,
      child: Scaffold(
        backgroundColor: Colors.transparent,

        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassBar(child: SizedBox.expand()),
          leading: const BackButton(),
          title: Text(member.displayName),
          actions: [
            if (actions.isNotEmpty)
              PopupMenuButton<int>(
                tooltip: 'Manage member',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (i) => actions[i].$3(),
                itemBuilder: (_) => [
                  for (final (i, (icon, label, _, destructive))
                      in actions.indexed)
                    PopupMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: destructive ? AppColors.danger : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            label,
                            style: destructive
                                ? const TextStyle(color: AppColors.danger)
                                : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: context.colors.border),
          ),
        ),
        body: InsightsTabs(
          userId: member.id,
          userName: member.displayName,
          header: _ProfileHeader(member: member),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final TeamMember member;
  const _ProfileHeader({required this.member});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final (label, color) = memberStatus(m);
    final gutter = context.gutter;
    final phone = context.isPhone;

    final identity = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.auroraGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20,
              ),
            ],
          ),
          child: UserAvatar(
            name: m.displayName,
            imageUrl: m.avatarUrl,
            radius: phone ? 30 : 38,
            statusColor: color,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.displayName,
                style: context.text.headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              SelectableText(
                m.email,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusPill(label: label, color: color, dot: true),
                  StatusPill(
                    label: m.isAdmin ? 'Admin' : 'Member',
                    color: m.isAdmin ? AppColors.warning : AppColors.primary,
                    icon: m.isAdmin
                        ? Icons.shield_rounded
                        : Icons.person_rounded,
                  ),
                  if (m.joinedAt != null)
                    StatusPill(
                      label: 'Joined ${formatDate(m.joinedAt)}',
                      color: AppColors.idle,
                      icon: Icons.event_rounded,
                    ),
                  StatusPill(
                    label: 'Last login ${formatRelative(m.lastLoginAt)}',
                    color: AppColors.idle,
                    icon: Icons.login_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final stats = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MiniStat(
          label: 'Today',
          value: formatHm(m.today),
          color: AppColors.primary,
        ),
        _MiniStat(
          label: 'This week',
          value: formatHm(m.week),
          color: AppColors.cyan,
        ),
        _MiniStat(
          label: 'This month',
          value: formatHm(m.month),
          color: AppColors.violet,
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 12),
      child: ContentWidth(
        child: SurfaceCard(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.16),
              AppColors.cyan.withValues(alpha: 0.05),
            ],
          ),
          padding: EdgeInsets.all(phone ? 16 : 24),
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth < 820
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, const SizedBox(height: 16), stats],
                  )
                : Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 20),
                      stats,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.text.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status label + colour for a team member.
(String, Color) memberStatus(TeamMember m) {
  if (!m.isActive) return ('Deactivated', AppColors.danger);
  if (m.isOnBreak) return ('On break', AppColors.warning);
  if (m.isWorking) {
    final since = m.sessionStartedAt;
    return (
      since == null ? 'Working' : 'Working since ${formatTime(since)}',
      AppColors.success,
    );
  }
  return (
    m.lastSeenAt == null
        ? 'No tracking yet'
        : 'Seen ${formatRelative(m.lastSeenAt)}',
    AppColors.idle,
  );
}
