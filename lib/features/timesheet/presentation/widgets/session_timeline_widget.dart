import 'package:flutter/material.dart';
import '../../../tracking/data/models/work_session.dart';
import '../../../tracking/data/models/app_activity.dart';
import '../../../../theme/macos_theme.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Timeline widget showing work sessions with 15-minute segments in vertical layout
class SessionTimelineWidget extends StatelessWidget {
  final List<WorkSession> sessions;
  final double hourHeight;

  const SessionTimelineWidget({
    super.key,
    required this.sessions,
    this.hourHeight = 60.0,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'No activity tracked for this day',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sessions
            .map(
              (session) =>
                  SessionBlock(session: session, hourHeight: hourHeight),
            )
            .toList(),
      ),
    );
  }
}

/// Widget representing a single work session block
class SessionBlock extends StatelessWidget {
  final WorkSession session;
  final double hourHeight;

  const SessionBlock({
    super.key,
    required this.session,
    this.hourHeight = 60.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? MacOSTheme.darkSidebar : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MacOSTheme.darkDivider : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session header
          _buildSessionHeader(context, theme, isDark),

          // 15-minute segments in COLUMN (vertical)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: session.segments
                  .map((segment) => SegmentTile(segment: segment))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionHeader(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    // FIX: Use new properties to distinguish working time from activity time
    final workingTime =
        session.workingTime; // Total session time (check-in to check-out)
    final activityTime = session.activityTime; // Actual app usage time
    final idleTime = session.idleTime; // Time when no app was actively used

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? MacOSTheme.systemBlue.withValues(alpha: 0.1)
            : MacOSTheme.systemBlue.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.work_outline,
                color: MacOSTheme.systemBlue,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Work Session',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: MacOSTheme.systemBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatTime(session.startTime)} - ${_formatTime(session.endTime)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MacOSTheme.systemBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${session.segmentCount} segments',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: MacOSTheme.systemBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // FIX: Show both Working Time and Activity Time clearly
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MacOSTheme.systemBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 14,
                      color: MacOSTheme.systemBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Working: ${_formatDuration(workingTime)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: MacOSTheme.systemBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MacOSTheme.systemGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.computer,
                      size: 14,
                      color: MacOSTheme.systemGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Activity: ${_formatDuration(activityTime)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: MacOSTheme.systemGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (idleTime.inSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: MacOSTheme.systemGray.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.hourglass_empty,
                        size: 14,
                        color: MacOSTheme.systemGray,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Idle: ${_formatDuration(idleTime)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: MacOSTheme.systemGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal(); // Convert to local time for display
    final hour = localTime.hour;
    final minute = localTime.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

/// Widget for a single 15-minute segment (clickable)
class SegmentTile extends StatelessWidget {
  final TimeSegment segment;

  const SegmentTile({super.key, required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _getColorForActivityType(segment.segmentActivityType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSegmentDetails(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: isDark ? 0.3 : 0.15),
                  color.withValues(alpha: isDark ? 0.2 : 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Time range
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTime(segment.startTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      Text(
                        _formatTime(segment.endTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Primary app info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getIconForApp(segment.primaryAppName),
                            size: 16,
                            color: color,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              segment.primaryAppName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (segment.activities.length > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          '+${segment.activities.length - 1} more app${segment.activities.length > 2 ? 's' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Duration
                Text(
                  _formatDuration(segment.duration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),

                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSegmentDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SegmentDetailsDialog(segment: segment),
    );
  }

  Color _getColorForActivityType(String type) {
    switch (type) {
      case 'work':
        return MacOSTheme.systemGreen;
      case 'break':
        return MacOSTheme.systemOrange;
      default:
        return MacOSTheme.systemBlue;
    }
  }

  IconData _getIconForApp(String appName) {
    final lower = appName.toLowerCase();
    if (lower.contains('code') ||
        lower.contains('xcode') ||
        lower.contains('windsurf') ||
        lower.contains('cursor')) {
      return Icons.code;
    } else if (lower.contains('chrome') ||
        lower.contains('safari') ||
        lower.contains('firefox')) {
      return Icons.web;
    } else if (lower.contains('terminal') || lower.contains('iterm')) {
      return Icons.terminal;
    } else if (lower.contains('slack') || lower.contains('discord')) {
      return Icons.chat;
    } else {
      return Icons.apps;
    }
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal(); // Convert to local time for display
    final hour = localTime.hour;
    final minute = localTime.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 1) return '< 1m';
    return '${minutes}m';
  }
}

/// Dialog showing detailed activities in a segment
class SegmentDetailsDialog extends StatelessWidget {
  final TimeSegment segment;

  const SegmentDetailsDialog({super.key, required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedActivities = segment.activitiesByDuration;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(AppStrings.s_15MinuteSegment),
          const SizedBox(height: 4),
          Text(
            '${_formatTime(segment.startTime)} - ${_formatTime(segment.endTime)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Applications Used:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...sortedActivities.map(
              (activity) => _buildActivityItem(context, activity, theme),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.close),
        ),
      ],
    );
  }

  Widget _buildActivityItem(
    BuildContext context,
    AppActivity activity,
    ThemeData theme,
  ) {
    final color = activity.activityType == 'work'
        ? MacOSTheme.systemGreen
        : MacOSTheme.systemOrange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activity.appName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatDuration(activity.duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          if (activity.windowTitle != null &&
              activity.windowTitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              activity.windowTitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal(); // Convert to local time for display
    final hour = localTime.hour;
    final minute = localTime.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
