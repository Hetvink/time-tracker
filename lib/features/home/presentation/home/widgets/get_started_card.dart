import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:time_trak/core/constants/app_env.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class GetStartedCard extends StatelessWidget {
  const GetStartedCard({super.key});

  @override
  Widget build(BuildContext context) {
    final url = AppEnv.desktopDownloadUrl;
    return SurfaceCard(
      gradient: LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.14),
          AppColors.cyan.withValues(alpha: 0.08),
        ],
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const IconBadge(
            icon: Icons.desktop_mac_rounded,
            color: AppColors.primary,
            size: 52,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start tracking with the desktop app',
                  style: context.text.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Time is recorded by the Time Trak app for macOS and Windows. Install it, sign in with the same account, and your hours show up here automatically.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (url != null)
            GradientButton(
              label: AppStrings.downloadTracker,
              icon: Icons.download_rounded,
              onPressed: () => launchUrl(Uri.parse(url)),
            ),
        ],
      ),
    );
  }
}
