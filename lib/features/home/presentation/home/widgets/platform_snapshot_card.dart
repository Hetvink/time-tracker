import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/routes/navigation_provider.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'mini.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class PlatformSnapshotCard extends StatelessWidget {
  /// Null while loading.
  final PlatformStats? stats;
  const PlatformSnapshotCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final s = stats;
        return AppCard(
          title: AppStrings.platformSnapshot,
          icon: Icons.admin_panel_settings_rounded,
          actions: [
            TextButton.icon(
              onPressed: () => context.read<NavigationProvider>().selectIndex(
                NavIndex.platformAdmin,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text(AppStrings.openConsole),
            ),
          ],
          child: s == null
              ? const Skeleton(height: 60)
              : Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    Mini(
                      label: AppStrings.pendingRequests,
                      value: '${s.companiesPending}',
                      color: AppColors.warning,
                    ),
                    Mini(
                      label: AppStrings.activeCompanies,
                      value: '${s.companiesApproved}',
                      color: AppColors.primary,
                    ),
                    Mini(
                      label: AppStrings.users,
                      value: '${s.usersTotal}',
                      color: AppColors.violet,
                    ),
                    Mini(
                      label: AppStrings.workingNow,
                      value: '${s.workingNow}',
                      color: AppColors.success,
                    ),
                  ],
                ),
        );
      },
    );
  }
}
