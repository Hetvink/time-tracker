import 'package:flutter/material.dart';
import '../../../timesheet/data/models/daily_timesheet.dart';
import '../../../../theme/macos_theme.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class SummaryCard extends StatelessWidget {
  final DailyTimeSheet timesheet;

  const SummaryCard({super.key, required this.timesheet});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MacOSTheme.systemBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: MacOSTheme.systemBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Daily Summary',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Total Work Time
          _buildSummaryRow(
            context,
            icon: Icons.work_outline_rounded,
            label: AppStrings.totalWorkTime,
            value: _formatDuration(timesheet.totalWorkTime),
            color: MacOSTheme.systemBlue,
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Total Break Time
          _buildSummaryRow(
            context,
            icon: Icons.coffee_outlined,
            label: AppStrings.totalBreakTime,
            value: _formatDuration(timesheet.totalBreakTime),
            color: MacOSTheme.systemGray, // Muted for breaks
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Net Working Hours
          _buildSummaryRow(
            context,
            icon: Icons.timer_outlined,
            label: AppStrings.netWorkingHours,
            value: _formatDuration(timesheet.netWorkTime),
            color: MacOSTheme.systemGreen,
            isHighlighted: true,
          ),
          const SizedBox(height: 24),

          // Statistics Row
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  context,
                  icon: Icons.event_note_rounded,
                  label: AppStrings.sessions,
                  value: '${timesheet.totalSessions}',
                  color: MacOSTheme.systemGray3Dark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  context,
                  icon: Icons.pause_circle_outline_rounded,
                  label: AppStrings.breaks,
                  value: '${timesheet.totalBreaks}',
                  color: MacOSTheme.systemGray3Dark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isHighlighted = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: MacOSTheme.systemGray,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isHighlighted ? color : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? MacOSTheme.systemGray6Dark
            : MacOSTheme.systemGray6,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: MacOSTheme.systemGray,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }
}
