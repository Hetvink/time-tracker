import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';

class DangerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const DangerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: IconBadge(icon: icon, color: AppColors.danger, size: 38),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

// =============================================================================
// Cards
// =============================================================================
