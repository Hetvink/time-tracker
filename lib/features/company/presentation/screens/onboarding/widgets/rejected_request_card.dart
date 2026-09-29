import 'package:flutter/material.dart';
import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/company.dart';

class RejectedRequestCard extends StatelessWidget {
  final Company request;
  const RejectedRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SurfaceCard(
        color: AppColors.danger.withValues(alpha: 0.08),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBadge(
              icon: Icons.info_outline_rounded,
              color: AppColors.danger,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Request for ${request.name} was not approved',
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    request.rejectionReason?.isNotEmpty == true
                        ? 'Reason: ${request.rejectionReason}'
                        : 'You can update the details and submit again.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
