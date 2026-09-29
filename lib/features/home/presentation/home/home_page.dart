import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/features/company/data/repository/company_repository.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';
import 'package:time_trak/features/insights/data/insights_repository.dart';
import 'package:time_trak/features/home/presentation/home_controller.dart';

import 'widgets/home_view.dart';

/// At-a-glance home: live status, today vs goal, this week, apps, sessions,
/// plus team / platform snapshots for admins. State lives in [HomeController].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AuthProvider, String?>((a) => a.userId);
    final company = context.watch<CompanyProvider>();
    if (userId == null) return const SizedBox.shrink();
    final companyId = company.isCompanyAdmin ? company.company?.id : null;
    return ChangeNotifierProvider(
      // New controller when the user or their admin scope changes.
      key: ValueKey('$userId|$companyId|${company.isSuperAdmin}'),
      create: (context) => HomeController(
        insightsRepository: context.read<InsightsRepository>(),
        companyRepository: context.read<CompanyRepository>(),
        userId: userId,
        companyId: companyId,
        platformAdmin: company.isSuperAdmin,
      ),
      child: const HomeView(),
    );
  }
}

// -----------------------------------------------------------------------------
// Hero
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// KPIs
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Admin snapshots
// -----------------------------------------------------------------------------
