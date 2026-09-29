import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';
import 'package:time_trak/features/platform_admin/presentation/platform_admin_controller.dart';

import 'widgets/platform_admin_view.dart';

/// Platform owner console: overview of the whole platform, the company
/// registration queue, and every company → its admins and members → a
/// member's tracked activity.
class PlatformAdminPage extends StatelessWidget {
  const PlatformAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.read<PlatformAdminController>();
    // Land on the queue when something is waiting.
    return DefaultTabController(
      length: 3,
      initialIndex: admin.pendingCount > 0 ? 1 : 0,
      child: const PlatformAdminView(),
    );
  }
}

/// Holds no data of its own: everything comes from [PlatformAdminController].
/// The State only gives the actions a context for dialogs and snackbars.

Color companyStatusColor(CompanyStatus s) => switch (s) {
  CompanyStatus.pending => AppColors.warning,
  CompanyStatus.approved => AppColors.success,
  CompanyStatus.rejected => AppColors.danger,
  CompanyStatus.suspended => AppColors.idle,
};

// =============================================================================
// Overview
// =============================================================================

// =============================================================================
// Requests queue
// =============================================================================

// =============================================================================
// Companies
// =============================================================================

/// Status filter, search and sort of the Companies tab.
