import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/features/company/presentation/screens/onboarding/widgets/section_label.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../data/models/company.dart';
import '../../providers/company_provider.dart';
import 'widgets/invitation_card.dart';
import 'widgets/invite_code_card.dart';
import 'widgets/register_company_card.dart';
import 'widgets/pending_request_card.dart';
import 'widgets/rejected_request_card.dart';
import 'widgets/how_it_works.dart';

/// Shown to signed-in users who don't belong to a company yet:
/// accept an invitation, or register a company for approval.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  /// Whether the "register your company" form has been opened.
  final _showRegisterForm = ValueNotifier(false);

  @override
  void dispose() {
    _showRegisterForm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _showRegisterForm,
    builder: (context, showRegisterForm, _) =>
        _build(context, showRegisterForm),
  );

  Widget _build(BuildContext context, bool showRegisterForm) {
    final company = context.watch<CompanyProvider>();
    final auth = context.watch<AuthProvider>();
    final ctx = company.context;
    final request = ctx?.latestRequest;
    final invitations = company.openInvitations;
    final name = ctx?.user?.displayName ?? auth.user?.email ?? '';

    final actions = <Widget>[
      if (invitations.isNotEmpty) ...[
        const SectionLabel('Your invitations'),
        for (final inv in invitations)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InvitationCard(
              invitation: inv,
              signedInEmail: auth.user?.email,
            ),
          ),
        const SizedBox(height: 8),
      ],
      if (request?.status == CompanyStatus.pending)
        PendingRequestCard(request: request!)
      else ...[
        if (request?.status == CompanyStatus.rejected)
          RejectedRequestCard(request: request!),
        if (invitations.isEmpty) ...[
          const InviteCodeCard(),
          const SizedBox(height: 16),
        ],
        RegisterCompanyCard(
          expanded:
              showRegisterForm || request?.status == CompanyStatus.rejected,
          initial: request?.status == CompanyStatus.rejected
              ? CompanyDetails.fromCompany(request!)
              : null,
          onExpand: () => _showRegisterForm.value = true,
        ),
      ],
    ];

    final wide = context.screenWidth >= 1000;
    final gutter = context.gutter;

    return Scaffold(
      body: AuroraBackground(
        intensity: 0.7,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: company.load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter + 24),
              children: [
                ContentWidth(
                  maxWidth: 1180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const BrandMark(size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Time Trak',
                              style: context.text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: company.isLoading ? null : company.load,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                          const SizedBox(width: 4),
                          if (context.isPhone)
                            IconButton(
                              tooltip: 'Sign out',
                              onPressed: auth.signOut,
                              icon: const Icon(Icons.logout_rounded),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: auth.signOut,
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Sign out'),
                            ),
                        ],
                      ),
                      SizedBox(height: context.isPhone ? 28 : 48),
                      PageHeader(
                        eyebrow: 'Getting started',
                        title:
                            'Welcome${name.isEmpty ? '' : ', ${name.split(' ').first}'}!',
                        subtitle:
                            'Join your team or register your company to start tracking time.',
                      ),
                      const SizedBox(height: 28),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [...actions],
                              ),
                            ),
                            const SizedBox(width: 28),
                            const Expanded(flex: 2, child: HowItWorks()),
                          ],
                        )
                      else ...[
                        ...actions,
                        const SizedBox(height: 24),
                        const HowItWorks(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
