import 'package:flutter/material.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../../auth/data/models/user_role.dart';
import '../../../../data/models/company_invitation.dart';

class InvitationsTab extends StatefulWidget {
  final List<CompanyInvitation> invitations;
  final Future<void> Function() onRefresh;
  final VoidCallback? onInvite;
  final ValueChanged<CompanyInvitation> onCopy;
  final ValueChanged<CompanyInvitation> onResend;
  final ValueChanged<CompanyInvitation> onRevoke;

  const InvitationsTab({
    super.key,
    required this.invitations,
    required this.onRefresh,
    required this.onInvite,
    required this.onCopy,
    required this.onResend,
    required this.onRevoke,
  });

  @override
  State<InvitationsTab> createState() => InvitationsTabState();
}

class InvitationsTabState extends State<InvitationsTab> {
  /// Show only invitations that are still waiting.
  final _openOnly = ValueNotifier(false);

  @override
  void dispose() {
    _openOnly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _openOnly,
    builder: (context, openOnly, _) => _build(context, openOnly),
  );

  Widget _build(BuildContext context, bool openOnly) {
    if (widget.invitations.isEmpty) {
      return EmptyState(
        icon: Icons.mark_email_unread_rounded,
        title: 'No invitations yet',
        message:
            'Invite people by e-mail. They join by opening the link and signing in.',
        action: widget.onInvite == null
            ? null
            : GradientButton(
                label: 'Invite members',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: widget.onInvite,
              ),
      );
    }
    final list = widget.invitations
        .where((i) => !openOnly || i.isOpen)
        .toList();
    final open = widget.invitations.where((i) => i.isOpen).length;
    final accepted = widget.invitations
        .where((i) => i.status == InvitationStatus.accepted)
        .length;
    final gutter = context.gutter;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        children: [
          ContentWidth(
            child: AdaptiveGrid(
              phoneMinItemWidth: 150,
              minItemWidth: 200,
              maxColumns: 3,
              spacing: 14,
              children: [
                KpiCard(
                  label: 'Sent',
                  numeric: widget.invitations.length.toDouble(),
                  format: (v) => '${v.round()}',
                  icon: Icons.outgoing_mail,
                  color: AppColors.primary,
                ),
                KpiCard(
                  label: 'Waiting',
                  numeric: open.toDouble(),
                  format: (v) => '${v.round()}',
                  icon: Icons.hourglass_top_rounded,
                  color: AppColors.warning,
                ),
                KpiCard(
                  label: 'Accepted',
                  numeric: accepted.toDouble(),
                  format: (v) => '${v.round()}',
                  icon: Icons.how_to_reg_rounded,
                  color: AppColors.success,
                  caption:
                      '${(accepted / widget.invitations.length * 100).round()}% acceptance',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ContentWidth(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedTabs<bool>(
                items: [
                  (false, 'All · ${widget.invitations.length}'),
                  (true, 'Waiting · $open'),
                ],
                value: openOnly,
                onChanged: (v) => _openOnly.value = v,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ContentWidth(
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    InvitationRow(
                      invitation: list[i],
                      onCopy: () => widget.onCopy(list[i]),
                      onResend: () => widget.onResend(list[i]),
                      onRevoke: () => widget.onRevoke(list[i]),
                    ),
                  ],
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: EmptyState(
                        icon: Icons.inbox_rounded,
                        title: 'No waiting invitations',
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

class InvitationRow extends StatelessWidget {
  final CompanyInvitation invitation;
  final VoidCallback onCopy;
  final VoidCallback onResend;
  final VoidCallback onRevoke;

  const InvitationRow({
    super.key,
    required this.invitation,
    required this.onCopy,
    required this.onResend,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final inv = invitation;
    final (label, color) = switch (inv.status) {
      InvitationStatus.pending when inv.isExpired => (
        'Expired',
        AppColors.idle,
      ),
      InvitationStatus.pending => ('Waiting', AppColors.warning),
      InvitationStatus.accepted => ('Joined', AppColors.success),
      InvitationStatus.declined => ('Declined', AppColors.danger),
      InvitationStatus.revoked => ('Revoked', AppColors.idle),
      InvitationStatus.expired => ('Expired', AppColors.idle),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          IconBadge(icon: Icons.mail_outline_rounded, color: color, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      inv.email,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    StatusPill(label: label, color: color),
                    if (inv.role == UserRole.admin)
                      const StatusPill(
                        label: 'Admin',
                        color: AppColors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  inv.isOpen
                      ? 'Sent ${formatRelative(inv.createdAt)} · expires ${formatDate(inv.expiresAt)}'
                      : 'Sent ${formatDate(inv.createdAt)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          if (inv.isOpen) ...[
            IconButton(
              tooltip: 'Copy invite link',
              onPressed: onCopy,
              icon: const Icon(Icons.link_rounded),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) => v == 'resend' ? onResend() : onRevoke(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'resend', child: Text('Resend e-mail')),
                PopupMenuItem(
                  value: 'revoke',
                  child: Text(
                    'Revoke',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ] else if (inv.status != InvitationStatus.accepted)
            TextButton(onPressed: onResend, child: const Text('Invite again')),
        ],
      ),
    );
  }
}
