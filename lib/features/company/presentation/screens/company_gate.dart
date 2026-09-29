import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/splash.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/company.dart';
import '../providers/company_provider.dart';
import 'onboarding/onboarding_page.dart';

/// Sits between sign-in and the main app. Shows onboarding for users without
/// a company and a notice for deactivated users or suspended companies;
/// otherwise renders [child].
class CompanyGate extends StatelessWidget {
  final Widget child;

  const CompanyGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final company = context.watch<CompanyProvider>();
    final ctx = company.context;

    Widget notice({
      required IconData icon,
      required Color color,
      required String title,
      required String message,
      required String primaryLabel,
    }) => NoticeScreen(
      icon: icon,
      color: color,
      title: title,
      message: message,
      actions: [
        GradientButton(
          label: primaryLabel,
          icon: Icons.refresh_rounded,
          loading: company.isLoading,
          onPressed: company.load,
        ),
        OutlinedButton.icon(
          onPressed: context.read<AuthProvider>().signOut,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Sign out'),
        ),
      ],
    );

    if (ctx == null) {
      if (company.error != null && !company.isLoading) {
        return notice(
          icon: Icons.cloud_off_rounded,
          color: AppColors.danger,
          title: 'Could not load your account',
          message: company.error!,
          primaryLabel: 'Try again',
        );
      }
      return const AppSplash(message: 'Loading your account…');
    }

    // Platform admins always get in (they may not belong to any company)
    if (ctx.isSuperAdmin) return child;

    if (!ctx.isActive) {
      return notice(
        icon: Icons.person_off_rounded,
        color: AppColors.warning,
        title: 'Account deactivated',
        message:
            'Your ${ctx.company?.name ?? 'company'} admin has deactivated your account. Contact them to regain access.',
        primaryLabel: 'Check again',
      );
    }

    final c = ctx.company;
    if (c == null) return const OnboardingPage();

    if (c.status == CompanyStatus.suspended) {
      return notice(
        icon: Icons.pause_circle_outline_rounded,
        color: AppColors.warning,
        title: '${c.name} is suspended',
        message:
            'Access for this company has been paused by the platform administrator. Tracking is stopped until it is reactivated.',
        primaryLabel: 'Check again',
      );
    }

    return child;
  }
}
