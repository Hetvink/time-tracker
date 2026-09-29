import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class DateBadge extends StatelessWidget {
  final DateTime date;
  const DateBadge({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final weekend = date.weekday >= 6;
    final color = weekend ? AppColors.violet : AppColors.primary;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            '${date.day}',
            style: context.text.titleMedium?.copyWith(height: 1.1),
          ),
        ],
      ),
    );
  }
}
