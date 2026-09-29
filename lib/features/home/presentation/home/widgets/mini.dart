import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class Mini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const Mini({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: context.text.headlineMedium?.copyWith(color: color)),
      Text(label, style: context.text.bodySmall),
    ],
  );
}
