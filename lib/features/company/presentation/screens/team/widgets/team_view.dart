import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../providers/team_controller.dart';
import 'overview_tab.dart';
import 'invitations_tab.dart';
import 'company_tab.dart';
import 'members_tab.dart';
import 'team_actions.dart';
import 'reports_tab.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class TeamView extends StatelessWidget {
  final bool platformView;
  final List<Widget> extraActions;

  const TeamView({
    super.key,
    required this.platformView,
    required this.extraActions,
  });

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamController>();
    final company = team.company;
    final actions = TeamActions(context);
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
                tooltip: AppStrings.refresh,
                onPressed: team.isLoading ? null : team.load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (canInvite)
                GradientButton(
                  label: AppStrings.invite,
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
                  title: AppStrings.couldNotLoadTheTeam,
                  error: team.error,
                  onRetry: team.load,
                )
              : TabBarView(
                  children: [
                    OverviewTab(
                      members: team.members,
                      invitations: team.invitations,
                      onRefresh: team.load,
                      onOpen: actions.openMember,
                      onInvite: canInvite ? actions.invite : null,
                      onShowInvitations: actions.showInvitations,
                    ),
                    KeepAlivePage(
                      child: MembersTab(
                        members: team.members,
                        onRefresh: team.load,
                        onOpen: actions.openMember,
                        menu: actions.memberMenu,
                        onInvite: canInvite ? actions.invite : null,
                      ),
                    ),
                    InvitationsTab(
                      invitations: team.invitations,
                      onRefresh: team.load,
                      onInvite: canInvite ? actions.invite : null,
                      onCopy: actions.copyInvite,
                      onResend: actions.resend,
                      onRevoke: actions.revoke,
                    ),
                    KeepAlivePage(
                      child: ReportsTab(
                        company: company,
                        members: team.members,
                        onOpen: actions.openMember,
                      ),
                    ),
                    CompanyTab(platformView: platformView),
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
          title: const Text(AppStrings.company),
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
