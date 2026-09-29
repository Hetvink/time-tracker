import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../../admin/presentation/screens/member_profile_page.dart';
import '../../../../../auth/data/models/user_role.dart';
import '../../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../data/models/company.dart';
import '../../../../data/models/company_invitation.dart';
import '../../../../data/models/team_member.dart';
import '../../../providers/company_provider.dart';
import '../../../providers/team_controller.dart';
import '../../../widgets/invite_member_dialog.dart';

class TeamActions {
  final BuildContext context;
  TeamActions(this.context);

  TeamController get _team => context.read<TeamController>();
  Company get _company => _team.company;

  void _report(String? error, String success) {
    if (!context.mounted) return;
    showSnack(context, error ?? success, error: error != null);
  }

  Future<void> invite() async {
    final sent = await showInviteMemberDialog(
      context,
      repository: _team.repository,
      companyId: _company.id,
      companyName: _company.name,
    );
    if (sent && context.mounted) {
      await _team.load(silent: true);
      if (context.mounted) DefaultTabController.of(context).animateTo(2);
    }
  }

  void showInvitations() => DefaultTabController.of(context).animateTo(2);

  List<(IconData, String, VoidCallback, bool)> actionsFor(TeamMember m) {
    final isMe = m.id == context.read<AuthProvider>().userId;
    return [
      (
        m.isAdmin ? Icons.person_rounded : Icons.shield_rounded,
        m.isAdmin ? 'Make member' : 'Make admin',
        () => toggleRole(m, isMe),
        false,
      ),
      if (!isMe)
        (
          m.isActive ? Icons.person_off_rounded : Icons.person_add_rounded,
          m.isActive ? 'Deactivate' : 'Reactivate',
          () => toggleActive(m),
          m.isActive,
        ),
      if (!isMe)
        (
          Icons.person_remove_rounded,
          'Remove from company',
          () => remove(m),
          true,
        ),
    ];
  }

  Future<void> toggleRole(TeamMember m, bool isMe) async {
    final newRole = m.isAdmin ? UserRole.member : UserRole.admin;
    final company = context.read<CompanyProvider>();
    final error = await _team.setRole(m, newRole);
    _report(
      error,
      '${m.displayName} is now ${newRole == UserRole.admin ? 'an admin' : 'a member'}',
    );
    if (error == null && isMe) company.load();
  }

  Future<void> toggleActive(TeamMember m) async {
    if (m.isActive &&
        !await confirmAction(
          context,
          title: 'Deactivate ${m.displayName}?',
          message:
              'They will lose access and their desktop app stops tracking until reactivated.',
          confirmLabel: 'Deactivate',
          destructive: true,
        )) {
      return;
    }
    if (!context.mounted) return;
    final error = await _team.setActive(m, !m.isActive);
    _report(error, m.isActive ? 'Member deactivated' : 'Member reactivated');
  }

  Future<void> remove(TeamMember m) async {
    if (!await confirmAction(
      context,
      title: 'Remove ${m.displayName}?',
      message:
          'They leave ${_company.name}. Their tracked history stays with the company.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      return;
    }
    if (!context.mounted) return;
    _report(await _team.remove(m), 'Member removed');
  }

  Future<void> resend(CompanyInvitation inv) async => _report(
    await _team.resendInvitation(inv),
    'Invitation sent again to ${inv.email}',
  );

  Future<void> revoke(CompanyInvitation inv) async =>
      _report(await _team.revokeInvitation(inv), 'Invitation revoked');

  Future<void> copyInvite(CompanyInvitation inv) async {
    final url = _team.inviteUrlFor(inv);
    if (url == null) {
      showSnack(
        context,
        'Set WEB_APP_URL in .env to build invite links.',
        error: true,
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showSnack(context, 'Invite link copied');
  }

  void openMember(TeamMember m) {
    MemberProfilePage.open(
      context,
      m,
      actions: [
        for (final (icon, label, action, destructive) in actionsFor(m))
          (
            icon,
            label,
            () {
              Navigator.of(context).pop();
              action();
            },
            destructive,
          ),
      ],
    );
  }

  Widget memberMenu(TeamMember m) {
    final actions = actionsFor(m);
    return PopupMenuButton<int>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (i) => i < 0 ? openMember(m) : actions[i].$3(),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: -1,
          child: Row(
            children: [
              Icon(Icons.insights_rounded, size: 18),
              SizedBox(width: 12),
              Text('View activity'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (final (i, (icon, label, _, destructive)) in actions.indexed)
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
    );
  }
}
