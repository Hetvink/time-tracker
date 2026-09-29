import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'company_avatar.dart';

import '../platform_admin_page.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class RequestCard extends StatelessWidget {
  final CompanyOverview overview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;
  final bool expanded;

  const RequestCard({
    super.key,
    required this.overview,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = overview.company;
    final pending = c.status == CompanyStatus.pending;
    Widget field(IconData icon, String label, String? value) =>
        value == null || value.isEmpty
        ? const SizedBox.shrink()
        : InfoRow(icon: icon, label: label, value: value);

    return TiltCard(
      maxTilt: 0.04,
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CompanyAvatar(name: c.name, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: context.text.titleLarge),
                      Text(
                        'Submitted ${formatRelative(c.createdAt)}',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: c.status.label,
                  color: companyStatusColor(c.status),
                  dot: pending,
                ),
              ],
            ),
            const SizedBox(height: 14),
            field(Icons.person_rounded, 'Requested by', overview.creatorName),
            field(
              Icons.alternate_email_rounded,
              'E-mail',
              overview.creatorEmail,
            ),
            field(Icons.language_rounded, 'Website', c.website),
            field(Icons.work_outline_rounded, 'Industry', c.industry),
            field(Icons.groups_2_rounded, 'Team size', c.companySize),
            field(Icons.public_rounded, 'Country', c.country),
            field(Icons.phone_rounded, 'Phone', c.phone),
            if (c.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  c.description!,
                  style: context.text.bodyMedium,
                  maxLines: expanded ? null : 4,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                ),
              ),
            ],
            if (c.rejectionReason?.isNotEmpty == true)
              field(Icons.block_rounded, 'Rejection reason', c.rejectionReason),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: pending
                  ? [
                      OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text(AppStrings.reject),
                      ),
                      GradientButton(
                        label: AppStrings.approve,
                        icon: Icons.check_rounded,
                        onPressed: onApprove,
                      ),
                    ]
                  : [
                      OutlinedButton.icon(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text(AppStrings.deleteRequest),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Companies
// =============================================================================

/// Status filter, search and sort of the Companies tab.
