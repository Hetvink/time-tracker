import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class CompanyAvatar extends StatelessWidget {
  final String name;
  final double size;
  const CompanyAvatar({super.key, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = UserAvatar.colorFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, AppColors.violet, 0.6)!],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

// =============================================================================
// Requests queue
// =============================================================================
