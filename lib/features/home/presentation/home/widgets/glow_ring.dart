import 'package:flutter/material.dart';

class GlowRing extends StatelessWidget {
  final double size;
  const GlowRing({super.key, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.12),
        width: 26,
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// KPIs
// -----------------------------------------------------------------------------
