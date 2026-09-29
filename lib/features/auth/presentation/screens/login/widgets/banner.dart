import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class LoginBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const LoginBanner({
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
