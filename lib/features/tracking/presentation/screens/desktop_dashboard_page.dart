import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/ui_kit.dart';
import '../../../settings/presentation/providers/preferences_service.dart';
import '../../data/models/attendance_state.dart';
import '../providers/attendance_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Desktop tracker home: live session control, today's progress and totals.
class DesktopDashboardPage extends StatelessWidget {
  const DesktopDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AttendanceProvider>();
    return AppPage(
      eyebrow: DateFormat('EEEE, d MMMM').format(DateTime.now()),
      title: '${greeting()} 👋',
      subtitle: AppStrings.yourTimeIsTrackedAutomaticallyWhileYouWork,
      onRefresh: provider.refresh,
      actions: [
        IconButton(
          tooltip: AppStrings.refresh,
          onPressed: provider.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        SplitPanes(
          breakpoint: 860,
          primary: _SessionPanel(provider: provider),
          secondary: _TodayPanel(provider: provider),
        ),
        AdaptiveGrid(
          phoneMinItemWidth: 150,
          minItemWidth: 200,
          spacing: 14,
          children: [
            KpiCard.duration(
              label: AppStrings.today,
              duration: provider.todayClosedDuration,
              icon: Icons.today_rounded,
              color: AppColors.primary,
            ),
            KpiCard.duration(
              label: AppStrings.breaksToday,
              duration: provider.todayClosedBreakDuration,
              icon: Icons.coffee_rounded,
              color: AppColors.warning,
            ),
            KpiCard.duration(
              label: DateFormat('MMMM').format(DateTime.now()),
              duration: provider.monthClosedDuration,
              icon: Icons.calendar_month_rounded,
              color: AppColors.cyan,
            ),
            KpiCard(
              label: AppStrings.sessionsAllTime,
              numeric: provider.totalSessionsCount.toDouble(),
              format: (v) => '${v.round()}',
              icon: Icons.layers_rounded,
              color: AppColors.violet,
              caption: '${formatHm(provider.allTimeClosedDuration)} tracked',
            ),
          ],
        ),
      ],
    );
  }
}

class _SessionPanel extends StatelessWidget {
  final AttendanceProvider provider;
  const _SessionPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final state = provider.state;
    final status = state.status;
    final (label, color, gradient) = switch (status) {
      AttendanceStatus.checkedIn => (
        'Working',
        AppColors.success,
        const [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0891B2)],
      ),
      AttendanceStatus.onBreak => (
        'On a break',
        AppColors.warning,
        const [Color(0xFFB45309), Color(0xFFD97706), Color(0xFF7C3AED)],
      ),
      AttendanceStatus.checkedOut => (
        'Checked out',
        AppColors.idle,
        const [Color(0xFF334155), Color(0xFF475569), Color(0xFF1E293B)],
      ),
    };
    final running = status != AttendanceStatus.checkedOut;

    return TiltCard(
      maxTilt: 0.04,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        padding: EdgeInsets.all(context.isPhone ? 18 : 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.45),
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (running)
                        PulseDot(color: color)
                      else
                        const SizedBox(width: 8, height: 22),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: context.text.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (state.checkInTime != null && running)
                  Flexible(
                    child: Text(
                      'Since ${formatTime(state.checkInTime)}',
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Ticking(
              active: running,
              builder: (context) => Column(
                children: [
                  FlipClock(
                    duration: running ? state.totalWorkTime : Duration.zero,
                    digitSize: 58,
                  ),
                  if (status == AttendanceStatus.onBreak) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Break ${formatClock(state.currentBreakDuration)}',
                      style: context.text.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: status == AttendanceStatus.onBreak
                        ? Icons.play_arrow_rounded
                        : Icons.coffee_rounded,
                    label: status == AttendanceStatus.onBreak
                        ? 'End break'
                        : 'Take a break',
                    onPressed: running
                        ? () => status == AttendanceStatus.onBreak
                              ? provider.breakOut()
                              : provider.breakIn()
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: running ? Icons.logout_rounded : Icons.login_rounded,
                    label: running ? 'Check out' : 'Check in',
                    filled: true,
                    onPressed: () => running
                        ? provider.checkOut(EventSource.manualUser)
                        : provider.checkIn(EventSource.manualUser),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: filled ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: filled ? const Color(0xFF312E81) : Colors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(
                      color: filled ? const Color(0xFF312E81) : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  final AttendanceProvider provider;
  const _TodayPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final goal = Duration(
      minutes: context.read<PreferencesService>().dailyGoalMinutes,
    );
    // todayClosedDuration already includes the running session.
    final today = provider.todayClosedDuration;
    final progress = goal.inSeconds == 0
        ? 0.0
        : today.inSeconds / goal.inSeconds;
    final remaining = goal - today;

    return AppCard(
      title: "Today's goal",
      subtitle: 'Target ${formatHm(goal)}',
      icon: Icons.flag_rounded,
      child: Column(
        children: [
          ProgressRing(
            progress: progress,
            size: 170,
            stroke: 14,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatHm(today), style: context.text.headlineMedium),
                Text(
                  '${(progress * 100).round()}%',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          InfoRow(
            icon: Icons.hourglass_bottom_rounded,
            label: AppStrings.remaining,
            value: remaining > Duration.zero
                ? formatHm(remaining)
                : 'Goal reached 🎉',
            valueColor: remaining > Duration.zero ? null : AppColors.success,
          ),
          InfoRow(
            icon: Icons.coffee_rounded,
            label: AppStrings.breaks,
            value: formatHm(provider.todayClosedBreakDuration),
          ),
          InfoRow(
            icon: Icons.calendar_month_rounded,
            label: AppStrings.thisMonth,
            value: formatHm(provider.monthClosedDuration),
          ),
        ],
      ),
    );
  }
}
