import 'package:flutter/material.dart';

import 'ui_kit.dart';

/// Full-screen loading state with the animated brand mark.
class AppSplash extends StatelessWidget {
  final String? message;
  const AppSplash({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.8,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 96),
              const SizedBox(height: 28),
              Text('Time Trak', style: context.text.headlineLarge),
              const SizedBox(height: 8),
              Text(
                message ?? 'Loading your workspace…',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen notice (deactivated account, suspended company, errors…).
class NoticeScreen extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final List<Widget> actions;

  const NoticeScreen({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.6,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GlassCard(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color.withValues(alpha: 0.35),
                              color.withValues(alpha: 0.05),
                            ],
                          ),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(icon, size: 40, color: color),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        title,
                        style: context.text.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        style: context.text.bodyLarge?.copyWith(
                          color: context.colors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: actions,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
