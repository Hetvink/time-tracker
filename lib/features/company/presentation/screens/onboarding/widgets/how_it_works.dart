import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../../core/constants/app_env.dart';
import '../../../../../../core/widgets/ui_kit.dart';

class HowItWorks extends StatelessWidget {
  const HowItWorks();

  @override
  Widget build(BuildContext context) {
    final download = AppEnv.desktopDownloadUrl;
    const steps = [
      (
        Icons.mail_rounded,
        'Get invited',
        'Your company admin invites you by e-mail.',
      ),
      (
        Icons.how_to_reg_rounded,
        'Accept',
        'Accept the invitation with the same account.',
      ),
      (
        Icons.desktop_windows_rounded,
        'Install the tracker',
        'Sign in to the desktop app — tracking starts automatically.',
      ),
      (
        Icons.insights_rounded,
        'See your time',
        'You and your admin see hours here on any device.',
      ),
    ];
    final colors = context.colors;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works', style: context.text.titleLarge),
          const SizedBox(height: 18),
          for (final (i, (icon, title, text)) in steps.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      IconBadge(icon: icon, color: AppColors.chartAt(i)),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.chartAt(i),
                                  AppColors.chartAt(i + 1),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. $title',
                            style: context.text.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            text,
                            style: context.text.bodyMedium?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (download != null)
            GradientButton(
              label: 'Download the desktop app',
              icon: Icons.download_rounded,
              expand: true,
              onPressed: () => launchUrl(Uri.parse(download)),
            ),
        ],
      ),
    );
  }
}
