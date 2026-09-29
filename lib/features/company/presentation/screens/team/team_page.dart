import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/company.dart';
import '../../../data/repository/company_repository.dart';
import '../../providers/team_controller.dart';
import 'widgets/team_view.dart';

enum MemberFilter { all, working, onBreak, admins, inactive }

enum Sort { name, today, week, month, lastSeen }

enum Period { today, week, month }

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
        child: TeamView(platformView: platformView, extraActions: extraActions),
      ),
    );
  }
}

/// User-facing team actions: confirmations, snackbars, navigation.
