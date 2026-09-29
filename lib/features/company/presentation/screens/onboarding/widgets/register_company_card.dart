import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/company.dart';
import '../../../providers/company_provider.dart';
import '../../../widgets/company_details_form.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class RegisterCompanyCard extends StatelessWidget {
  final bool expanded;
  final CompanyDetails? initial;
  final VoidCallback onExpand;

  const RegisterCompanyCard({
    super.key,
    required this.expanded,
    required this.initial,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CompanyProvider>();
    return AppCard(
      title: initial == null ? 'Register your company' : 'Submit a new request',
      subtitle: AppStrings.afterApprovalYouBecomeTheCompanyAdminAndCanInviteYourTeam,
      icon: Icons.add_business_rounded,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: expanded
            ? CompanyDetailsForm(
                initial: initial,
                submitLabel: 'Send for approval',
                onSubmit: (details) async {
                  final error = await provider.requestCompany(details);
                  if (error == null && context.mounted) {
                    showSnack(
                      context,
                      'Request sent. We will review it shortly.',
                    );
                  }
                  return error;
                },
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onExpand,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(AppStrings.startRegistration),
                ),
              ),
      ),
    );
  }
}
