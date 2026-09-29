import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class CompactBrand extends StatelessWidget {
  const CompactBrand({super.key});

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
