import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const HeroChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
