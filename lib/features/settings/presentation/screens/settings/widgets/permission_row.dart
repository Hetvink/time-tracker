import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class PermissionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onOpen;
  final VoidCallback onCheck;

  const PermissionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onOpen,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(subtitle, style: context.text.bodySmall),
                  ],
                ),
              ),
              StatusPill(
                label: granted ? 'Granted' : 'Required',
                color: granted ? AppColors.success : AppColors.warning,
                icon: granted
                    ? Icons.check_circle_rounded
                    : Icons.warning_rounded,
              ),
            ],
          ),
          if (!granted) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: const Text(AppStrings.openSystemSettings),
                ),
                TextButton.icon(
                  onPressed: onCheck,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(AppStrings.checkAgain),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
