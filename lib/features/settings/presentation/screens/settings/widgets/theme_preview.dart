import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class ThemePreview extends StatelessWidget {
  final ThemeMode mode;
  const ThemePreview({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    Widget pane(AppColors c) => Container(
      color: c.background,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Container(
            width: 14,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: c.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: 70,
        child: switch (mode) {
          ThemeMode.light => pane(AppColors.light),
          ThemeMode.dark => pane(AppColors.dark),
          ThemeMode.system => Row(
            children: [
              Expanded(child: pane(AppColors.light)),
              Expanded(child: pane(AppColors.dark)),
            ],
          ),
        },
      ),
    );
  }
}
