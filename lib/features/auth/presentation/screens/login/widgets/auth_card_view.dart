import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';
import 'package:time_trak/features/auth/presentation/providers/login_form_controller.dart';

import 'banner.dart';
import 'google_mark.dart';

class AuthCardView extends StatelessWidget {
  const AuthCardView({super.key});

  Future<void> _forgot(BuildContext context, LoginFormController c) async {
    final controller = TextEditingController(text: c.email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.lock_reset_rounded,
          color: AppColors.primary,
          size: 32,
        ),
        title: const Text('Reset your password'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'We will e-mail you a sign-in link. After opening it, set a new password under Settings → Security.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email != null) await c.sendPasswordReset(email);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LoginFormController>();
    final colors = context.colors;
    final invite = context.watch<CompanyProvider>().hasPendingInviteLink;
    return TiltCard(
      maxTilt: 0.04,
      glare: false,
      child: GlassCard(
        padding: EdgeInsets.all(context.isPhone ? 22 : 32),
        child: Form(
          key: c.formKey,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    c.isSignUp ? 'Create your account' : 'Welcome back',
                    key: ValueKey(c.mode),
                    style: context.text.headlineMedium,
                  ),
                ),
                const SizedBox(height: 6),

                Text(
                  c.isSignUp
                      ? 'Start tracking in under a minute.'
                      : 'Sign in to see your time and your team.',
                  style: context.text.bodyMedium?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                if (invite) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          AppColors.cyan.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.mark_email_unread_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You have a team invitation! Sign in or create an account to accept it.',
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                SegmentedTabs<LoginMode>(
                  expand: true,
                  items: const [
                    (LoginMode.signIn, 'Sign in'),
                    (LoginMode.signUp, 'Create account'),
                  ],
                  value: c.mode,
                  onChanged: c.setMode,
                ),
                const SizedBox(height: 18),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: c.isSignUp
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            controller: c.name,
                            enabled: !c.isBusy,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),

                TextFormField(
                  controller: c.email,
                  enabled: !c.isBusy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (v) =>
                      LoginFormController.emailPattern.hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Enter a valid e-mail address',
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: c.password,
                  enabled: !c.isBusy,
                  obscureText: c.obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    c.isSignUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onFieldSubmitted: (_) => c.submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: c.obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        c.obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                      onPressed: c.toggleObscure,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your password';
                    return c.isSignUp && v.length < 8
                        ? 'Use at least 8 characters'
                        : null;
                  },
                ),
                if (!c.isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: c.isBusy ? null : () => _forgot(context, c),
                      child: const Text('Forgot password?'),
                    ),
                  )
                else
                  const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: c.error != null
                      ? LoginBanner(
                          key: const ValueKey('err'),
                          text: c.error!,
                          color: AppColors.danger,
                          icon: Icons.error_outline_rounded,
                        )
                      : c.info != null
                      ? LoginBanner(
                          key: const ValueKey('info'),
                          text: c.info!,
                          color: AppColors.success,
                          icon: Icons.check_circle_outline_rounded,
                        )
                      : const SizedBox(key: ValueKey('none')),
                ),
                const SizedBox(height: 8),

                GradientButton(
                  label: c.isSignUp ? 'Create account' : 'Sign in',
                  icon: c.isSignUp
                      ? Icons.rocket_launch_rounded
                      : Icons.arrow_forward_rounded,
                  loading: c.isBusy,
                  expand: true,
                  onPressed: c.submit,
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(child: Divider(color: colors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: context.text.bodySmall),
                    ),
                    Expanded(child: Divider(color: colors.border)),
                  ],
                ),
                const SizedBox(height: 20),

                OutlinedButton(
                  onPressed: c.isBusy ? null : c.signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: colors.surface.withValues(alpha: 0.6),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GoogleMark(),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Continue with Google',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'By continuing you agree to let your company see the time you track.',
                  style: context.text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
