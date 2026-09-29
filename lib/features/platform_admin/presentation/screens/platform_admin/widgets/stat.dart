import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  const Stat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 4),
        Text(value, style: context.text.labelLarge?.copyWith(color: color)),
        const SizedBox(width: 3),
        Text(label, style: context.text.bodySmall),
      ],
    );
  }
}
