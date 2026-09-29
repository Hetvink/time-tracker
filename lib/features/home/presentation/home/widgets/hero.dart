import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/insights/data/insights.dart';

import 'hero_chip.dart';
import 'glow_ring.dart';

class HomeHero extends StatelessWidget {
  final Insights? insights;
  final Duration goal;
  const HomeHero({super.key, required this.insights, required this.goal});

  @override
  Widget build(BuildContext context) {
    // Only the hero ticks each second while a session is live.
    return Ticking(active: insights?.liveSession != null, builder: _buildHero);
  }

  Widget _buildHero(BuildContext context) {
    final i = insights;
    final today = DateUtils.dateOnly(DateTime.now());
    final live = i?.liveSession;
    final onBreak = live?.onBreak ?? false;

    // Today's work, advanced live while a session runs.
    var worked = i?.daily[today] ?? Duration.zero;
    if (live != null && !onBreak) {
      worked += DateTime.now().difference(i!.computedAt);
    }
    final progress = goal.inSeconds == 0
        ? 0.0
        : worked.inSeconds / goal.inSeconds;
    final remaining = goal - worked;

    final (statusLabel, statusColor, statusDetail) = switch ((live, onBreak)) {
      (null, _) => (
        'Not tracking',
        AppColors.idle,
        'Start the desktop tracker to record time.',
      ),
      (_, true) => (
        'On a break',
        AppColors.warning,
        'Break since ${formatTime(live!.breaks.last.start)}',
      ),
      _ => (
        'Working now',
        AppColors.success,
        'Session started at ${formatTime(live!.start)}',
      ),
    };

    final ring = ProgressRing(
      progress: progress,
      size: context.isPhone ? 132 : 164,
      stroke: 14,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(progress * 100).clamp(0, 999).round()}%',
            style: context.text.headlineLarge?.copyWith(color: Colors.white),
          ),
          Text(
            'of ${formatHm(goal)}',
            style: context.text.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live != null)
                PulseDot(color: statusColor)
              else
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.pause_circle_filled_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: context.text.labelMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Worked today',
          style: context.text.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            i == null ? '--:--:--' : formatClock(worked),
            style: context.text.displayLarge?.copyWith(
              color: Colors.white,
              fontSize: context.isPhone ? 40 : 54,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          statusDetail,
          style: context.text.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            HeroChip(
              icon: Icons.flag_rounded,
              label: remaining > Duration.zero
                  ? '${formatHm(remaining)} to goal'
                  : 'Goal reached 🎉',
            ),
            if (i != null)
              HeroChip(
                icon: Icons.coffee_rounded,
                label:
                    '${formatHm(Insights(from: today, to: today.add(const Duration(days: 1)), sessions: i.sessions, activities: const [], computedAt: i.computedAt).breakTotal)} breaks',
              ),
            if (i != null && i.streak > 0)
              HeroChip(
                icon: Icons.local_fire_department_rounded,
                label: '${i.streak}-day streak',
              ),
          ],
        ),
      ],
    );

    return TiltCard(
      maxTilt: 0.05,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0891B2)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -12,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Decorative rings
            const Positioned(right: -60, top: -60, child: GlowRing(size: 240)),
            const Positioned(
              left: -40,
              bottom: -80,
              child: GlowRing(size: 200),
            ),
            Padding(
              padding: EdgeInsets.all(context.isPhone ? 20 : 32),
              child: LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        info,
                        const SizedBox(height: 20),
                        Center(child: ring),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 24),
                      ring,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
