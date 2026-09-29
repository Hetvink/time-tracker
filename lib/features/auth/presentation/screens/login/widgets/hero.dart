import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class LoginHero extends StatelessWidget {
  const LoginHero({super.key});

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
