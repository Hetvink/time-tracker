import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/ui_kit.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../company/presentation/providers/company_provider.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import 'insight_views.dart';

/// The signed-in user's own analytics.
class MyActivityPage extends StatelessWidget {
  const MyActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AuthProvider, String?>((a) => a.userId);
    final name =
        context.select<CompanyProvider, String?>(
          (c) => c.context?.user?.displayName,
        ) ??
        'me';
    final goal = Duration(
      minutes: context.select<SettingsProvider, int>((s) => s.dailyGoalMinutes),
    );
    if (userId == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: InsightsTabs(
        userId: userId,
        userName: name,
        goal: goal,
        header: Padding(
          padding: EdgeInsets.fromLTRB(
            context.gutter,
            context.gutter,
            context.gutter,
            8,
          ),
          child: const PageHeader(
            eyebrow: 'Personal analytics',
            title: 'My activity',
            subtitle: 'Where your time goes — by day, month and app.',
          ),
        ),
      ),
    );
  }
}
