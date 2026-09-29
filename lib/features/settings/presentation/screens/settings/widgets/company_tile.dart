import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';

class CompanyTile extends StatelessWidget {
  const CompanyTile({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CompanyProvider>();
    final ctx = provider.context;
    final company = ctx?.company;
    final role = ctx?.isSuperAdmin == true
        ? 'Platform admin'
        : ctx?.isCompanyAdmin == true
        ? 'Company admin'
        : 'Member';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const IconBadge(
        icon: Icons.business_rounded,
        color: AppColors.violet,
        size: 38,
      ),
      title: Text(company?.name ?? 'No company'),
      subtitle: Text(
        company == null ? role : '$role · ${company.status.label}',
      ),
      trailing: company == null || provider.isCompanyAdmin
          ? null
          : TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                if (!await confirmAction(
                  context,
                  title: 'Leave ${company.name}?',
                  message:
                      'Your admin will no longer see your tracked time and tracking stops until you join a company again.',
                  confirmLabel: 'Leave',
                  destructive: true,
                )) {
                  return;
                }
                final error = await provider.leaveCompany();
                if (error != null && context.mounted) {
                  showSnack(context, error, error: true);
                }
              },
              child: const Text('Leave'),
            ),
    );
  }
}
