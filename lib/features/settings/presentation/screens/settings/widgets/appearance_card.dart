import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

import 'theme_preview.dart';

class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const options = [
      (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
      (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
      (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdaptiveGrid(
          minItemWidth: 150,
          maxColumns: 3,
          spacing: 12,
          children: [
            for (final (mode, icon, label) in options)
              TiltCard(
                onTap: () => theme.setMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: theme.mode == mode
                          ? AppColors.primary
                          : context.colors.border,
                      width: theme.mode == mode ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      ThemePreview(mode: mode),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color: theme.mode == mode
                                ? AppColors.primary
                                : null,
                          ),
                          const SizedBox(width: 6),
                          Text(label, style: context.text.labelLarge),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Motion',
                    style: context.text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    theme.reducedMotion
                        ? '3D tilt, spinning and drifting effects are off.'
                        : 'Hover tilt and background effects are on.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SegmentedTabs<bool>(
              items: const [(false, 'Full'), (true, 'Reduced')],
              value: theme.reducedMotion,
              onChanged: theme.setReducedMotion,
            ),
          ],
        ),
      ],
    );
  }
}

/// Miniature mock of the UI in a given theme.
