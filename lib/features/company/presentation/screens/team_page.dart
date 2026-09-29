import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/csv_export.dart';
import '../../../../core/widgets/charts.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../../admin/presentation/screens/member_profile_page.dart';
import '../../../auth/data/models/user_role.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../insights/data/insights.dart';
import '../../../insights/data/insights_repository.dart';
import '../../data/models/company.dart';
import '../../data/models/company_invitation.dart';
import '../../data/models/team_member.dart';
import '../../data/repository/company_repository.dart';
import '../providers/company_provider.dart';
import '../providers/team_controller.dart';
import '../widgets/company_details_form.dart';
import '../widgets/invite_member_dialog.dart';

enum _MemberFilter { all, working, onBreak, admins, inactive }

enum _Sort { name, today, week, month, lastSeen }

enum _Period { today, week, month }

/// Company administration: live overview, members, invitations, reports and
/// the company profile.
///
/// Company admins see their own company from the sidebar. Platform admins
/// open any company from the platform console ([platformView] = true).
/// All data and mutations live in [TeamController].
class TeamPage extends StatelessWidget {
  final Company company;
  final bool platformView;

  /// Extra header actions (the platform console adds a status pill here).
  final List<Widget> extraActions;

  const TeamPage({
    super.key,
    required this.company,
    this.platformView = false,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(company.id),
      create: (context) => TeamController(
        repository: context.read<CompanyRepository>(),
        company: company,
      ),
      child: DefaultTabController(
        length: 5,
        child: _TeamView(
          platformView: platformView,
          extraActions: extraActions,
        ),
      ),
    );
  }
}

/// User-facing team actions: confirmations, snackbars, navigation.
class _TeamActions {
  final BuildContext context;
  _TeamActions(this.context);

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

class _TeamView extends StatelessWidget {
  final bool platformView;
  final List<Widget> extraActions;

  const _TeamView({required this.platformView, required this.extraActions});

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamController>();
    final company = team.company;
    final actions = _TeamActions(context);
    final gutter = context.gutter;
    final updatedAt = team.updatedAt;
    final canInvite = company.isApproved;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 8),
          child: PageHeader(
            eyebrow: platformView ? 'Company' : 'Team admin',
            title: company.name,
            subtitle:
                '${team.members.length} members · ${team.workingCount} working now · ${company.status.label}${updatedAt == null ? '' : ' · updated ${formatTime(updatedAt)}'}',
            actions: [
              ...extraActions,
              IconButton(
                tooltip: 'Refresh',
                onPressed: team.isLoading ? null : team.load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (canInvite)
                GradientButton(
                  label: 'Invite',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: actions.invite,
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter - 8),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Overview'),
              Tab(text: 'Members (${team.members.length})'),
              Tab(
                text:
                    'Invitations${team.openInvitationCount > 0 ? ' (${team.openInvitationCount})' : ''}',
              ),
              const Tab(text: 'Reports'),
              const Tab(text: 'Company'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: team.isLoading && team.members.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : team.error != null
              ? ErrorState(
                  title: 'Could not load the team',
                  error: team.error,
                  onRetry: team.load,
                )
              : TabBarView(
                  children: [
                    _OverviewTab(
                      members: team.members,
                      invitations: team.invitations,
                      onRefresh: team.load,
                      onOpen: actions.openMember,
                      onInvite: canInvite ? actions.invite : null,
                      onShowInvitations: actions.showInvitations,
                    ),
                    KeepAlivePage(
                      child: _MembersTab(
                        members: team.members,
                        onRefresh: team.load,
                        onOpen: actions.openMember,
                        menu: actions.memberMenu,
                        onInvite: canInvite ? actions.invite : null,
                      ),
                    ),
                    _InvitationsTab(
                      invitations: team.invitations,
                      onRefresh: team.load,
                      onInvite: canInvite ? actions.invite : null,
                      onCopy: actions.copyInvite,
                      onResend: actions.resend,
                      onRevoke: actions.revoke,
                    ),
                    KeepAlivePage(
                      child: _ReportsTab(
                        company: company,
                        members: team.members,
                        onOpen: actions.openMember,
                      ),
                    ),
                    _CompanyTab(platformView: platformView),
                  ],
                ),
        ),
      ],
    );

    if (!platformView) {
      return Scaffold(backgroundColor: Colors.transparent, body: body);
    }
    return AuroraBackground(
      animate: false,
      intensity: 0.55,
      child: Scaffold(
        backgroundColor: Colors.transparent,

        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassBar(child: SizedBox.expand()),
          leading: const BackButton(),
          title: const Text('Company'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: context.colors.border),
          ),
        ),
        body: body,
      ),
    );
  }
}

class _CompanyTab extends StatelessWidget {
  final bool platformView;
  const _CompanyTab({required this.platformView});

  Future<void> _leave(BuildContext context, Company company) async {
    final provider = context.read<CompanyProvider>();
    if (!await confirmAction(
      context,
      title: 'Leave ${company.name}?',
      message: 'You will lose access to the team dashboard.',
      confirmLabel: 'Leave',
      destructive: true,
    )) {
      return;
    }
    final error = await provider.leaveCompany();
    if (error != null && context.mounted) {
      showSnack(context, error, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = context.read<TeamController>();
    final company = team.company;
    return CenteredScroll(
      maxWidth: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            title: 'Company profile',
            subtitle: 'Shown to members and platform admins',
            icon: Icons.business_rounded,
            child: CompanyDetailsForm(
              key: ValueKey(company.id),
              initial: CompanyDetails.fromCompany(company),
              submitLabel: 'Save changes',
              onSubmit: (details) async {
                final companyProvider = context.read<CompanyProvider>();
                final error = await team.updateProfile(details);
                if (error != null) return error;
                if (context.mounted) {
                  showSnack(context, 'Company profile saved');
                }
                // Refresh the header / sidebar name
                await companyProvider.load();
                return null;
              },
            ),
          ),
          const SizedBox(height: 18),
          AppCard(
            title: 'Details',
            icon: Icons.info_outline_rounded,
            child: Column(
              children: [
                InfoRow(label: 'Status', value: company.status.label),
                InfoRow(
                  label: 'Workspace ID',
                  value: company.slug.isEmpty ? company.id : company.slug,
                ),
                InfoRow(label: 'Created', value: formatDate(company.createdAt)),
                if (company.reviewedAt != null)
                  InfoRow(
                    label: 'Approved',
                    value: formatDate(company.reviewedAt),
                  ),
              ],
            ),
          ),
          if (!platformView) ...[
            const SizedBox(height: 18),
            SurfaceCard(
              color: AppColors.danger.withValues(alpha: 0.06),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Danger zone',
                          style: context.text.titleMedium?.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Leave this company. A company must always keep at least one admin.',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Leave company'),
                    onPressed: () => _leave(context, company),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Overview
// =============================================================================

class _OverviewTab extends StatelessWidget {
  final List<TeamMember> members;
  final List<CompanyInvitation> invitations;
  final Future<void> Function() onRefresh;
  final ValueChanged<TeamMember> onOpen;
  final VoidCallback? onInvite;
  final VoidCallback onShowInvitations;

  const _OverviewTab({
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
        title: 'No members yet',
        message: 'Invite your team to start tracking time together.',
        action: onInvite == null
            ? null
            : GradientButton(
                label: 'Invite members',
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
            label: 'Members',
            numeric: members.length.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.groups_rounded,
            color: AppColors.primary,
            caption: deactivated == 0
                ? 'All active'
                : '$deactivated deactivated',
          ),
          KpiCard(
            label: 'Working now',
            numeric: working.length.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.bolt_rounded,
            color: AppColors.success,
            caption:
                '${(working.length / (active.isEmpty ? 1 : active.length) * 100).round()}% of team',
          ),
          KpiCard(
            label: 'On break',
            numeric: onBreak.length.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.coffee_rounded,
            color: AppColors.warning,
          ),
          KpiCard.duration(
            label: 'Team today',
            duration: today,
            icon: Icons.today_rounded,
            color: AppColors.cyan,
            caption:
                'Avg ${formatHm(today ~/ (active.isEmpty ? 1 : active.length))}/person',
          ),
          KpiCard.duration(
            label: 'Team this week',
            duration: week,
            icon: Icons.date_range_rounded,
            color: AppColors.violet,
          ),
          KpiCard.duration(
            label: 'Team this month',
            duration: month,
            icon: Icons.calendar_month_rounded,
            color: AppColors.pink,
          ),
        ],
      ),
      SplitPanes(
        primary: _LiveBoard(working: working, onBreak: onBreak, onOpen: onOpen),
        secondary: AppCard(
          title: 'Status mix',
          subtitle: 'Right now',
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
        primary: _Leaderboard(members: members, onOpen: onOpen),
        secondary: _Attention(
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
class _LiveBoard extends StatelessWidget {
  final List<TeamMember> working;
  final List<TeamMember> onBreak;
  final ValueChanged<TeamMember> onOpen;

  const _LiveBoard({
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

class _Leaderboard extends StatelessWidget {
  final List<TeamMember> members;
  final ValueChanged<TeamMember> onOpen;
  const _Leaderboard({required this.members, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final sorted = [...members]..sort((a, b) => b.week.compareTo(a.week));
    final top = sorted.take(10).toList();
    return AppCard(
      title: 'This week',
      subtitle: 'Hours per member',
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

class _Attention extends StatelessWidget {
  final List<TeamMember> members;
  final List<CompanyInvitation> invitations;
  final ValueChanged<TeamMember> onOpen;
  final VoidCallback onShowInvitations;

  const _Attention({
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
        _AttentionRow(
          icon: Icons.hourglass_disabled_rounded,
          color: AppColors.warning,
          title: m.displayName,
          subtitle: m.lastSeenAt == null
              ? 'Has never tracked time'
              : 'No tracking for ${now.difference(m.lastSeenAt!).inDays} days',
          onTap: () => onOpen(m),
        ),
      for (final i in expiring.take(3))
        _AttentionRow(
          icon: Icons.schedule_send_rounded,
          color: AppColors.info,
          title: i.email,
          subtitle:
              'Invitation expires ${formatRelative(i.expiresAt).replaceAll(' ago', '')} — resend?',
          onTap: onShowInvitations,
        ),
      for (final m in deactivated.take(3))
        _AttentionRow(
          icon: Icons.person_off_rounded,
          color: AppColors.danger,
          title: m.displayName,
          subtitle: 'Account deactivated',
          onTap: () => onOpen(m),
        ),
    ];
    return AppCard(
      title: 'Needs attention',
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
                title: 'Everything looks healthy',
                color: AppColors.success,
              ),
            )
          : Column(children: rows),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AttentionRow({
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
class _MemberListController extends ChangeNotifier {
  String _query = '';
  _MemberFilter _filter = _MemberFilter.all;
  _Sort _sort = _Sort.name;
  bool _grid = false;

  String get query => _query;
  _MemberFilter get filter => _filter;
  _Sort get sort => _sort;
  bool get grid => _grid;

  void setQuery(String v) {
    _query = v;
    notifyListeners();
  }

  void setFilter(_MemberFilter f) {
    _filter = f;
    notifyListeners();
  }

  void setSort(_Sort s) {
    _sort = s;
    notifyListeners();
  }

  void setGrid(bool g) {
    _grid = g;
    notifyListeners();
  }

  List<TeamMember> visible(List<TeamMember> members) {
    final q = _query.trim().toLowerCase();
    final list = members.where((m) {
      final matchesQuery =
          q.isEmpty ||
          m.displayName.toLowerCase().contains(q) ||
          m.email.toLowerCase().contains(q);
      final matchesFilter = switch (_filter) {
        _MemberFilter.all => true,
        _MemberFilter.working => m.isWorking && !m.isOnBreak,
        _MemberFilter.onBreak => m.isOnBreak,
        _MemberFilter.admins => m.isAdmin,
        _MemberFilter.inactive => !m.isActive,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    list.sort(switch (_sort) {
      _Sort.name => (a, b) => a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      ),
      _Sort.today => (a, b) => b.today.compareTo(a.today),
      _Sort.week => (a, b) => b.week.compareTo(a.week),
      _Sort.month => (a, b) => b.month.compareTo(a.month),
      _Sort.lastSeen =>
        (a, b) =>
            (b.isWorking ? DateTime.now() : b.lastSeenAt ?? DateTime(2000))
                .compareTo(
                  a.isWorking ? DateTime.now() : a.lastSeenAt ?? DateTime(2000),
                ),
    });
    return list;
  }
}

class _MembersTab extends StatelessWidget {
  final List<TeamMember> members;
  final Future<void> Function() onRefresh;
  final ValueChanged<TeamMember> onOpen;
  final Widget Function(TeamMember) menu;
  final VoidCallback? onInvite;

  const _MembersTab({
    required this.members,
    required this.onRefresh,
    required this.onOpen,
    required this.menu,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => _MemberListController(),
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final c = context.watch<_MemberListController>();
    final visible = c.visible(members);
    final gutter = context.gutter;
    final showGrid = c.grid || context.isPhone;
    int count(_MemberFilter f) => switch (f) {
      _MemberFilter.all => members.length,
      _MemberFilter.working =>
        members.where((m) => m.isWorking && !m.isOnBreak).length,
      _MemberFilter.onBreak => members.where((m) => m.isOnBreak).length,
      _MemberFilter.admins => members.where((m) => m.isAdmin).length,
      _MemberFilter.inactive => members.where((m) => !m.isActive).length,
    };

    final toolbar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SearchField(hint: 'Search name or e-mail', onChanged: c.setQuery),
            PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              initialValue: c.sort,
              onSelected: c.setSort,
              itemBuilder: (_) => [
                for (final (s, l) in const [
                  (_Sort.name, 'Name'),
                  (_Sort.today, 'Hours today'),
                  (_Sort.week, 'Hours this week'),
                  (_Sort.month, 'Hours this month'),
                  (_Sort.lastSeen, 'Recently active'),
                ])
                  PopupMenuItem(value: s, child: Text(l)),
              ],
              child: Chip(
                avatar: const Icon(Icons.sort_rounded, size: 16),
                label: Text(
                  'Sort: ${switch (c.sort) {
                    _Sort.name => 'Name',
                    _Sort.today => 'Today',
                    _Sort.week => 'Week',
                    _Sort.month => 'Month',
                    _Sort.lastSeen => 'Recent',
                  }}',
                ),
              ),
            ),
            if (!context.isPhone)
              SegmentedTabs<bool>(
                items: const [(false, 'Table'), (true, 'Cards')],
                value: c.grid,
                onChanged: c.setGrid,
              ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in _MemberFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${switch (f) {
                        _MemberFilter.all => 'All',
                        _MemberFilter.working => 'Working',
                        _MemberFilter.onBreak => 'On break',
                        _MemberFilter.admins => 'Admins',
                        _MemberFilter.inactive => 'Deactivated',
                      }} · ${count(f)}',
                    ),
                    selected: c.filter == f,
                    onSelected: (_) => c.setFilter(f),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final Widget list;
    if (visible.isEmpty) {
      list = EmptyState(
        icon: Icons.person_search_rounded,
        title: members.isEmpty ? 'No members yet' : 'No matches',
        message: members.isEmpty
            ? 'Invite your team to start tracking.'
            : 'Try a different search or filter.',
        action: members.isEmpty && onInvite != null
            ? GradientButton(
                label: 'Invite members',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: onInvite,
              )
            : null,
      );
    } else if (showGrid) {
      list = AdaptiveGrid(
        minItemWidth: 260,
        spacing: 14,
        children: [
          for (final m in visible)
            _MemberCard(member: m, onOpen: () => onOpen(m), menu: menu(m)),
        ],
      );
    } else {
      list = SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const _MemberHeaderRow(),
            for (final m in visible) ...[
              const Divider(height: 1),
              _MemberRow(member: m, onOpen: () => onOpen(m), menu: menu(m)),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        children: [
          ContentWidth(child: toolbar),
          const SizedBox(height: 18),
          ContentWidth(child: list),
        ],
      ),
    );
  }
}

class _MemberHeaderRow extends StatelessWidget {
  const _MemberHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelMedium?.copyWith(
      color: context.colors.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Member', style: style)),
          Expanded(flex: 3, child: Text('Status', style: style)),
          Expanded(
            flex: 2,
            child: Text('Today', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('This week', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('This month', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _MemberRow extends StatefulWidget {
  final TeamMember member;
  final VoidCallback onOpen;
  final Widget menu;

  const _MemberRow({
    required this.member,
    required this.onOpen,
    required this.menu,
  });

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  final _hover = ValueNotifier(false);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _hover,
    builder: (context, hover, _) => _build(context, hover),
  );

  Widget _build(BuildContext context, bool hover) {
    final m = widget.member;
    final (status, color) = memberStatus(m);
    final num = context.text.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      child: InkWell(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: hover
              ? context.colors.surfaceHover.withValues(alpha: 0.5)
              : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    UserAvatar(
                      name: m.displayName,
                      imageUrl: m.avatarUrl,
                      statusColor: color,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  m.displayName,
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (m.isAdmin) ...[
                                const SizedBox(width: 6),
                                const StatusPill(
                                  label: 'Admin',
                                  color: AppColors.warning,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            m.email,
                            style: context.text.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    if (m.isWorking)
                      PulseDot(color: color, size: 7)
                    else
                      const SizedBox(width: 4),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        status,
                        style: context.text.bodyMedium?.copyWith(
                          color: color == AppColors.idle
                              ? context.colors.textMuted
                              : color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatHm(m.today),
                  style: num?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatHm(m.week),
                  style: num,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatHm(m.month),
                  style: num,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              widget.menu,
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onOpen;
  final Widget menu;

  const _MemberCard({
    required this.member,
    required this.onOpen,
    required this.menu,
  });

  @override
  Widget build(BuildContext context) {
    final m = member;
    final (status, color) = memberStatus(m);
    Widget stat(String label, Duration d) => Expanded(
      child: Column(
        children: [
          Text(
            formatHm(d),
            style: context.text.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
    return TiltCard(
      onTap: onOpen,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: m.displayName,
                  imageUrl: m.avatarUrl,
                  radius: 22,
                  statusColor: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.displayName,
                        style: context.text.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        m.email,
                        style: context.text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                menu,
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPill(label: status, color: color, dot: true),
                if (m.isAdmin)
                  const StatusPill(
                    label: 'Admin',
                    color: AppColors.warning,
                    icon: Icons.shield_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  stat('Today', m.today),
                  stat('Week', m.week),
                  stat('Month', m.month),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Invitations
// =============================================================================

class _InvitationsTab extends StatefulWidget {
  final List<CompanyInvitation> invitations;
  final Future<void> Function() onRefresh;
  final VoidCallback? onInvite;
  final ValueChanged<CompanyInvitation> onCopy;
  final ValueChanged<CompanyInvitation> onResend;
  final ValueChanged<CompanyInvitation> onRevoke;

  const _InvitationsTab({
    required this.invitations,
    required this.onRefresh,
    required this.onInvite,
    required this.onCopy,
    required this.onResend,
    required this.onRevoke,
  });

  @override
  State<_InvitationsTab> createState() => _InvitationsTabState();
}

class _InvitationsTabState extends State<_InvitationsTab> {
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
                    _InvitationRow(
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

class _InvitationRow extends StatelessWidget {
  final CompanyInvitation invitation;
  final VoidCallback onCopy;
  final VoidCallback onResend;
  final VoidCallback onRevoke;

  const _InvitationRow({
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

// =============================================================================
// Reports
// =============================================================================

class _MemberMonthRow {
  final TeamMember member;
  final Insights insights;
  const _MemberMonthRow(this.member, this.insights);
}

class _ReportsTab extends StatefulWidget {
  final Company company;
  final List<TeamMember> members;
  final ValueChanged<TeamMember> onOpen;

  const _ReportsTab({
    required this.company,
    required this.members,
    required this.onOpen,
  });

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

/// Report period plus the on-demand detailed monthly report.
class _ReportsController extends ChangeNotifier {
  final InsightsRepository repository;
  _ReportsController(this.repository);

  _Period _period = _Period.week;
  List<_MemberMonthRow>? _detail;
  bool _loadingDetail = false;
  int _progress = 0;
  bool _disposed = false;

  _Period get period => _period;
  List<_MemberMonthRow>? get detail => _detail;
  bool get loadingDetail => _loadingDetail;
  int get progress => _progress;

  void setPeriod(_Period p) {
    _period = p;
    _notify();
  }

  /// Loads month insights for each member, four at a time.
  /// Returns an error message or null.
  Future<String?> loadDetail(List<TeamMember> members) async {
    final now = DateTime.now();
    _loadingDetail = true;
    _progress = 0;
    _notify();
    final rows = <_MemberMonthRow>[];
    try {
      for (var i = 0; i < members.length; i += 4) {
        final batch = members.skip(i).take(4).toList();
        final results = await Future.wait([
          for (final m in batch)
            repository.load(
              userId: m.id,
              from: DateTime(now.year, now.month),
              to: DateTime(now.year, now.month + 1),
              activities: false,
            ),
        ]);
        for (var j = 0; j < batch.length; j++) {
          rows.add(_MemberMonthRow(batch[j], results[j]));
        }
        _progress = rows.length;
        _notify();
      }
      rows.sort((a, b) => b.insights.total.compareTo(a.insights.total));
      _detail = rows;
      return null;
    } catch (e) {
      return friendlyError(e);
    } finally {
      _loadingDetail = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _ReportsTabState extends State<_ReportsTab> {
  late final _reports = _ReportsController(context.read<InsightsRepository>());

  _Period get _period => _reports.period;
  List<_MemberMonthRow>? get _detail => _reports.detail;
  bool get _loadingDetail => _reports.loadingDetail;
  int get _progress => _reports.progress;

  @override
  void dispose() {
    _reports.dispose();
    super.dispose();
  }

  Duration _value(TeamMember m) => switch (_period) {
    _Period.today => m.today,
    _Period.week => m.week,
    _Period.month => m.month,
  };

  String get _periodLabel => switch (_period) {
    _Period.today => 'today',
    _Period.week => 'this week',
    _Period.month => 'this month',
  };

  Future<void> _loadDetail() async {
    final error = await _reports.loadDetail(widget.members);
    if (error != null && mounted) showSnack(context, error, error: true);
  }

  Future<void> _exportSummary(List<TeamMember> sorted) => exportCsv(
    context,
    filename:
        'team-${widget.company.slug.isEmpty ? 'report' : widget.company.slug}-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
    header: const [
      'Member',
      'E-mail',
      'Role',
      'Status',
      'Today (h)',
      'This week (h)',
      'This month (h)',
      'Last seen',
    ],
    rows: [
      for (final m in sorted)
        [
          m.displayName,
          m.email,
          m.role.value,
          memberStatus(m).$1,
          (m.today.inMinutes / 60).toStringAsFixed(2),
          (m.week.inMinutes / 60).toStringAsFixed(2),
          (m.month.inMinutes / 60).toStringAsFixed(2),
          m.lastSeenAt?.toIso8601String() ?? '',
        ],
    ],
  );

  Future<void> _exportDetail() {
    String tod(TimeOfDay? t) => t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return exportCsv(
      context,
      filename:
          'team-month-${DateFormat('yyyy-MM').format(DateTime.now())}.csv',
      header: const [
        'Member',
        'E-mail',
        'Worked (h)',
        'Active days',
        'Avg per day (h)',
        'Sessions',
        'Breaks (h)',
        'Usual start',
        'Usual finish',
        'Longest session (h)',
      ],
      rows: [
        for (final r in _detail!)
          [
            r.member.displayName,
            r.member.email,
            (r.insights.total.inMinutes / 60).toStringAsFixed(2),
            r.insights.activeDays,
            (r.insights.averagePerActiveDay.inMinutes / 60).toStringAsFixed(2),
            r.insights.sessionCount,
            (r.insights.breakTotal.inMinutes / 60).toStringAsFixed(2),
            tod(r.insights.averageStartEnd.$1),
            tod(r.insights.averageStartEnd.$2),
            (r.insights.longestSession.inMinutes / 60).toStringAsFixed(2),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _reports,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final sorted = [...widget.members]
      ..sort((a, b) => _value(b).compareTo(_value(a)));
    final total = sorted.fold(Duration.zero, (a, m) => a + _value(m));
    final max = sorted.isEmpty ? Duration.zero : _value(sorted.first);
    final tracked = sorted.where((m) => _value(m) > Duration.zero).length;
    final gutter = context.gutter;

    final items = <Widget>[
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedTabs<_Period>(
            items: const [
              (_Period.today, 'Today'),
              (_Period.week, 'This week'),
              (_Period.month, 'This month'),
            ],
            value: _period,
            onChanged: _reports.setPeriod,
          ),
          OutlinedButton.icon(
            onPressed: sorted.isEmpty ? null : () => _exportSummary(sorted),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Export summary'),
          ),
        ],
      ),
      AdaptiveGrid(
        phoneMinItemWidth: 150,
        minItemWidth: 200,
        spacing: 14,
        children: [
          KpiCard.duration(
            label: 'Team total $_periodLabel',
            duration: total,
            icon: Icons.functions_rounded,
            color: AppColors.primary,
          ),
          KpiCard.duration(
            label: 'Average per member',
            duration: tracked == 0 ? Duration.zero : total ~/ tracked,
            icon: Icons.person_rounded,
            color: AppColors.cyan,
            caption: '$tracked of ${sorted.length} tracked',
          ),
          KpiCard(
            label: 'Top performer',
            value: sorted.isEmpty || max == Duration.zero
                ? '—'
                : sorted.first.displayName,
            icon: Icons.emoji_events_rounded,
            color: AppColors.warning,
            caption: max == Duration.zero ? null : formatHm(max),
          ),
        ],
      ),
      AppCard(
        title: 'Ranking $_periodLabel',
        subtitle: 'Tap a member for their full analytics',
        icon: Icons.leaderboard_rounded,
        bodyPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            for (final (i, m) in sorted.indexed)
              InkWell(
                onTap: () => widget.onOpen(m),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          i < 3 && _value(m) > Duration.zero
                              ? ['🥇', '🥈', '🥉'][i]
                              : '${i + 1}',
                          style: context.text.titleSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      UserAvatar(
                        name: m.displayName,
                        imageUrl: m.avatarUrl,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ShareBar(
                          label: m.displayName,
                          trailing:
                              '${formatHm(_value(m))} · ${total.inSeconds == 0 ? 0 : (_value(m).inSeconds / total.inSeconds * 100).round()}%',
                          fraction: max.inSeconds == 0
                              ? 0
                              : _value(m).inSeconds / max.inSeconds,
                          color: AppColors.chartAt(i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      AppCard(
        title: 'Detailed monthly report',
        subtitle:
            'Active days, averages, usual hours and sessions for ${DateFormat('MMMM').format(DateTime.now())}',
        icon: Icons.analytics_rounded,
        actions: [
          if (_detail != null)
            TextButton.icon(
              onPressed: _exportDetail,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('CSV'),
            ),
        ],
        child: _detail == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Builds a per-member breakdown from every session this month. Takes a few seconds for larger teams.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loadingDetail) ...[
                    LinearProgressIndicator(
                      value: widget.members.isEmpty
                          ? null
                          : _progress / widget.members.length,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Loaded $_progress of ${widget.members.length} members…',
                      style: context.text.bodySmall,
                    ),
                  ] else
                    GradientButton(
                      label: 'Build report',
                      icon: Icons.auto_graph_rounded,
                      onPressed: widget.members.isEmpty ? null : _loadDetail,
                    ),
                ],
              )
            : _DetailTable(rows: _detail!, onOpen: widget.onOpen),
      ),
    ];

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, i) => ContentWidth(child: items[i]),
    );
  }
}

class _DetailTable extends StatelessWidget {
  final List<_MemberMonthRow> rows;
  final ValueChanged<TeamMember> onOpen;
  const _DetailTable({required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    String tod(TimeOfDay? t) => t == null
        ? '—'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final head = context.text.labelMedium?.copyWith(
      color: context.colors.textMuted,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: head,
        columnSpacing: 28,
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Member')),
          DataColumn(label: Text('Worked'), numeric: true),
          DataColumn(label: Text('Days'), numeric: true),
          DataColumn(label: Text('Avg / day'), numeric: true),
          DataColumn(label: Text('Sessions'), numeric: true),
          DataColumn(label: Text('Breaks'), numeric: true),
          DataColumn(label: Text('Usual hours')),
          DataColumn(label: Text('Streak'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              onSelectChanged: (_) => onOpen(r.member),
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        name: r.member.displayName,
                        imageUrl: r.member.avatarUrl,
                        radius: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.member.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    formatHm(r.insights.total),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text('${r.insights.activeDays}')),
                DataCell(Text(formatHm(r.insights.averagePerActiveDay))),
                DataCell(Text('${r.insights.sessionCount}')),
                DataCell(Text(formatHm(r.insights.breakTotal))),
                DataCell(
                  Text(
                    '${tod(r.insights.averageStartEnd.$1)} – ${tod(r.insights.averageStartEnd.$2)}',
                  ),
                ),
                DataCell(Text('${r.insights.streak}d')),
              ],
            ),
        ],
      ),
    );
  }
}
