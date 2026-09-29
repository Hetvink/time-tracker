import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/ui_kit.dart';
import '../../../company/presentation/providers/company_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/login_form_controller.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = context.screenWidth >= 980;
    return Scaffold(
      body: AuroraBackground(
        grid: true,
        child: SafeArea(
          child: wide
              ? Row(
                  children: [
                    const Expanded(flex: 6, child: _Hero()),
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: const _AuthCard(),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(context.gutter),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: const Column(
                        children: [
                          _CompactBrand(),
                          SizedBox(height: 24),
                          _AuthCard(),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Hero (wide screens)
// -----------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const features = [
      (
        Icons.bolt_rounded,
        'Automatic tracking',
        'The desktop app records work, breaks and apps — no timers to start.',
      ),
      (
        Icons.insights_rounded,
        'Deep insights',
        'Daily, weekly and monthly analytics with app-level detail.',
      ),
      (
        Icons.groups_rounded,
        'Built for teams',
        'Live team status, reports and invitations for admins.',
      ),
      (
        Icons.devices_rounded,
        'Everywhere',
        'Web, tablet and phone — your timesheet always in reach.',
      ),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(64, 40, 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const BrandMark(size: 48),
                const SizedBox(width: 14),
                Text('Time Trak', style: context.text.headlineMedium),
              ],
            ),
            const SizedBox(height: 48),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (r) =>
                            AppColors.auroraGradient.createShader(r),
                        child: Text(
                          'Own every\nhour of work.',
                          style: context.text.displayLarge?.copyWith(
                            color: Colors.white,
                            fontSize: context.screenWidth > 1300 ? 60 : 48,
                            height: 1.05,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Text(
                          'Effortless time tracking for you and your team — with timelines, timesheets and analytics that actually make sense.',
                          style: context.text.bodyLarge?.copyWith(
                            color: colors.textMuted,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Floating(distance: 16, child: SpinningCube(size: 110)),
              ],
            ),
            const SizedBox(height: 36),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final (i, (icon, title, text)) in features.indexed)
                  SizedBox(
                    width: 260,
                    child: TiltCard(
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        radius: AppRadius.lg,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconBadge(
                              icon: icon,
                              color: AppColors.chartAt(i),
                              size: 36,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: context.text.titleSmall),
                                  const SizedBox(height: 2),
                                  Text(text, style: context.text.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              '© ${DateTime.now().year} Time Trak',
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Floating(child: SpinningCube(size: 64)),
        const SizedBox(height: 6),
        ShaderMask(
          shaderCallback: (r) => AppColors.auroraGradient.createShader(r),
          child: Text(
            'Time Trak',
            style: context.text.displayMedium?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Own every hour of work.',
          style: context.text.bodyLarge?.copyWith(
            color: context.colors.textMuted,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Auth card
// -----------------------------------------------------------------------------

class _AuthCard extends StatelessWidget {
  const _AuthCard();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => LoginFormController(context.read<AuthProvider>()),
    child: const _AuthCardView(),
  );
}

class _AuthCardView extends StatelessWidget {
  const _AuthCardView();

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
                      ? _Banner(
                          key: const ValueKey('err'),
                          text: c.error!,
                          color: AppColors.danger,
                          icon: Icons.error_outline_rounded,
                        )
                      : c.info != null
                      ? _Banner(
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
                      _GoogleMark(),
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

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Banner({
    super.key,
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
    return color == AppColors.danger
        ? box.animate().shakeX(hz: 4, amount: 3, duration: 400.ms)
        : box;
  }
}

/// Four-colour "G" without an image asset.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(
        colors: [
          Color(0xFF4285F4),
          Color(0xFF34A853),
          Color(0xFFFBBC05),
          Color(0xFFEA4335),
          Color(0xFF4285F4),
        ],
        stops: [0.0, 0.3, 0.55, 0.8, 1.0],
      ).createShader(r),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
