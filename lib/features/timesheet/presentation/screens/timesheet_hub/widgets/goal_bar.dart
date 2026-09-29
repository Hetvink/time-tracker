import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class GoalBar extends StatelessWidget {
  final Duration worked;
  final Duration goal;
  const GoalBar({super.key, required this.worked, required this.goal});

  @override
  Widget build(BuildContext context) {
    final ratio = goal.inSeconds == 0 ? 0.0 : worked.inSeconds / goal.inSeconds;
    final color = ratio >= 1
        ? AppColors.success
        : ratio >= 0.5
        ? AppColors.warning
        : AppColors.danger;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: context.colors.surfaceHover,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 38,
          child: Text(
            '${(ratio * 100).round()}%',
            style: context.text.bodySmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Calendar grid (hour × day matrix)
// -----------------------------------------------------------------------------
