import 'package:flutter/material.dart';

import '../../../../../../core/widgets/ui_kit.dart';

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        text.toUpperCase(),
        style: context.text.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: context.colors.textSubtle,
        ),
      ),
    );
  }
}
