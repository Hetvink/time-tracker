import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/company.dart';
import '../../../providers/company_provider.dart';
import '../../../providers/team_controller.dart';
import '../../../widgets/company_details_form.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class CompanyTab extends StatelessWidget {
  final bool platformView;
  const CompanyTab({super.key, required this.platformView});

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
            title: AppStrings.companyProfile,
            subtitle: AppStrings.shownToMembersAndPlatformAdmins,
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
            title: AppStrings.details,
            icon: Icons.info_outline_rounded,
            child: Column(
              children: [
                InfoRow(label: AppStrings.status, value: company.status.label),
                InfoRow(
                  label: AppStrings.workspaceId,
                  value: company.slug.isEmpty ? company.id : company.slug,
                ),
                InfoRow(label: AppStrings.created, value: formatDate(company.createdAt)),
                if (company.reviewedAt != null)
                  InfoRow(
                    label: AppStrings.approved,
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
                    label: const Text(AppStrings.leaveCompany),
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
