import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../../auth/data/models/user_role.dart';
import '../../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../data/models/company_invitation.dart';
import '../../../providers/company_provider.dart';

class InvitationCard extends StatefulWidget {
  final CompanyInvitation invitation;
  final String? signedInEmail;

  const InvitationCard({
    super.key,
    required this.invitation,
    this.signedInEmail,
  });

  @override
  State<InvitationCard> createState() => InvitationCardState();
}

class InvitationCardState extends State<InvitationCard> {
  final _submit = SubmitController();
  bool get _busy => _submit.isBusy;

  @override
  void dispose() {
    _submit.dispose();
    super.dispose();
  }

  Future<void> _act(Future<String?> Function() action, String success) async {
    final ok = await _submit.run(action);
    if (!mounted) return;
    showSnack(context, ok ? success : _submit.error!, error: !ok);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _submit,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final inv = widget.invitation;
    final provider = context.read<CompanyProvider>();
    final wrongAccount = inv.emailMatches == false;
    final isAdmin = inv.role == UserRole.admin;

    return TiltCard(
      maxTilt: 0.05,
      child: SurfaceCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.violet.withValues(alpha: 0.08),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(
                  icon: Icons.mark_email_unread_rounded,
                  color: AppColors.primary,
                  size: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Join ${inv.companyName ?? 'a company'}',
                        style: context.text.titleLarge,
                      ),
                      Text(
                        'Invited by ${inv.invitedBy}',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: isAdmin ? 'Admin' : 'Member',
                  color: isAdmin ? AppColors.warning : AppColors.primary,
                  icon: isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),
            InfoRow(
              icon: Icons.alternate_email_rounded,
              label: 'Invitation for',
              value: inv.email,
            ),
            InfoRow(
              icon: Icons.event_rounded,
              label: 'Expires',
              value: formatDate(inv.expiresAt),
            ),
            if (wrongAccount) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You are signed in as ${widget.signedInEmail}. Sign out and sign in with ${inv.email} to accept.',
                        style: context.text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: wrongAccount
                    ? [
                        FilledButton.icon(
                          onPressed: context.read<AuthProvider>().signOut,
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Switch account'),
                        ),
                      ]
                    : [
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _act(
                                  () => provider.declineInvitation(inv.token),
                                  'Invitation declined',
                                ),
                          child: const Text('Decline'),
                        ),
                        GradientButton(
                          label: 'Join team',
                          icon: Icons.group_add_rounded,
                          loading: _busy,
                          onPressed: () => _act(
                            () => provider.acceptInvitation(inv.token),
                            'Welcome to ${inv.companyName}!',
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
