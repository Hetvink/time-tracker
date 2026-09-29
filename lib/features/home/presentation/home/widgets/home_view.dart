import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/routes/navigation_provider.dart';
import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';
import 'package:time_trak/features/insights/data/insights.dart';
import 'package:time_trak/features/home/presentation/home_controller.dart';
import 'package:time_trak/features/insights/presentation/insight_cards.dart';
import 'package:time_trak/features/settings/presentation/providers/settings_provider.dart';

import 'hero.dart';
import 'kpi_row.dart';
import 'week_card.dart';
import 'team_pulse_card.dart';
import 'platform_snapshot_card.dart';
import 'get_started_card.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HomeController>();
    final company = context.watch<CompanyProvider>();
    final auth = context.watch<AuthProvider>();
    final name =
        company.context?.user?.displayName ??
        auth.user?.email?.split('@').first ??
        '';
    final goal = Duration(
      minutes: context.watch<SettingsProvider>().dailyGoalMinutes,
    );
    final i = c.insights;
    final loading = i == null && c.error == null;

    return AppPage(
      eyebrow: DateFormat('EEEE, d MMMM').format(DateTime.now()),
      title:
          '${greeting()}${name.isEmpty ? '' : ', ${name.split(' ').first}'} 👋',
      subtitle: 'Here is how your day is going.',
      onRefresh: c.refresh,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: c.isLoading ? null : c.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        FilledButton.icon(
          onPressed: () =>
              context.read<NavigationProvider>().selectIndex(NavIndex.activity),
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Full analytics'),
        ),
      ],
      children: [
        if (c.error != null)
          ErrorState(error: c.error, onRetry: c.refresh)
        else ...[
          HomeHero(insights: i, goal: goal),
          KpiRow(insights: i, goal: goal, loading: loading),
          if (i != null && i.sessions.isEmpty) const GetStartedCard(),
          if (i != null) ...[
            SplitPanes(
              primary: WeekCard(insights: i, goal: goal),
              secondary: HabitsCard(insights: i, goal: goal),
            ),
            if (company.isCompanyAdmin) TeamPulseCard(members: c.team),
            if (company.isSuperAdmin)
              PlatformSnapshotCard(stats: c.platformStats),
            SplitPanes(
              primary: AppUsageCard(insights: _today(i), title: 'Apps today'),
              secondary: SessionsCard(
                insights: i,
                limit: 5,
                title: 'Recent sessions',
              ),
            ),
          ] else
            const SkeletonCard(height: 300),
        ],
      ],
    );
  }

  static Insights _today(Insights i) {
    final today = DateUtils.dateOnly(DateTime.now());
    return Insights(
      from: today,
      to: today.add(const Duration(days: 1)),
      sessions: i.sessions,
      activities: i.activities,
      computedAt: i.computedAt,
    );
  }
}

// -----------------------------------------------------------------------------
// Hero
// -----------------------------------------------------------------------------
