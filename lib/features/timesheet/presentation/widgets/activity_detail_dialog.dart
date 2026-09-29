import 'package:flutter/material.dart';

import '../../../tracking/data/models/app_activity.dart';
import '../../../../theme/macos_theme.dart';
import '../../../../core/utils/logger.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Simplified dialog showing activity details for a time period
/// ENHANCED: Auto-refreshes for active sessions to show real-time durations
class ActivityDetailDialog extends StatefulWidget {
  final DateTime startTime;
  final DateTime endTime;
  final List<AppActivity> activities;
  final String blockType;
  final String? note;
  final List<dynamic> relatedSleepPeriods;

  const ActivityDetailDialog({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.activities,
    required this.blockType,
    this.note,
    this.relatedSleepPeriods = const [],
  });

  @override
  State<ActivityDetailDialog> createState() => _ActivityDetailDialogState();
}

class _ActivityDetailDialogState extends State<ActivityDetailDialog> {
  @override
  void initState() {
    super.initState();

    Logger.info('Activity detail dialog opened', {
      'blockType': widget.blockType,
      'startTime': widget.startTime.toIso8601String(),
      'endTime': widget.endTime.toIso8601String(),
      'durationMinutes': widget.endTime.difference(widget.startTime).inMinutes,
      'activityCount': widget.activities.length,
    });

    if (widget.activities.isEmpty) {
      Logger.warning('No activities passed to dialog', {
        'blockType': widget.blockType,
        'possibleReasons': [
          'Activities not synced from desktop',
          'Session has no tracked activities',
          'User ID mismatch between session and activities',
          'Activities filtered out due to time range mismatch',
        ],
        'troubleshooting':
            'Check Day Timeline View logs above for activity fetching details',
      });
    } else {
      Logger.info('Activities received for dialog', {
        'count': widget.activities.length,
        'sampleActivities': widget.activities
            .take(3)
            .map(
              (a) => {
                'appName': a.appName,
                'startTime': a.startTime.toIso8601String(),
                'endTime': a.endTime?.toIso8601String(),
                'durationSeconds': a.durationSeconds,
                'calculatedDuration': a.duration.inSeconds,
              },
            )
            .toList(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final now = DateTime.now();

    // FIX: Always use the session's actual check-in/check-out times passed from the parent
    // DO NOT recalculate from activities as this causes issues when activities span multiple days
    // The session times are the source of truth from the attendance/timesheet records
    DateTime displayStartTime = widget.startTime;
    DateTime displayEndTime = widget.endTime;

    // Calculate total work session duration (actual session time, not combined app activity time)
    Duration totalSessionDuration = displayEndTime.difference(displayStartTime);

    Color color;
    IconData icon;
    String title;

    switch (widget.blockType) {
      case 'work':
        color = MacOSTheme.systemGreen;
        icon = Icons.work_outline;
        title = 'Work Session';
        break;
      case 'work_during_sleep':
        color = MacOSTheme.systemGreen;
        icon = Icons.work;
        title = 'Work During Sleep';
        break;
      case 'break':
        color = MacOSTheme.systemOrange;
        icon = Icons.coffee;
        title = 'Break';
        break;
      default:
        color = MacOSTheme.systemGreen;
        icon = Icons.work_outline;
        title = 'Activity';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatTime(displayStartTime)} - ${_formatTime(displayEndTime)} (${_formatDurationDetailed(totalSessionDuration)})',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Column(
                children: [
                  // Activity List (Flexible)
                  Flexible(
                    child: Builder(
                      builder: (context) {
                        // ... (Existing activity list logic)
                        if (widget.blockType == 'work_during_sleep' &&
                            widget.note != null) {
                          return Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.work, color: color, size: 20),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'This was a work session during system sleep.',
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Work Note:',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.note, color: color, size: 18),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          widget.note!,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Standard Activity List Logic
                        final aggregatedActivities = _aggregateActivities();
                        if (aggregatedActivities.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(48),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 48,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No App Activity Data',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: theme
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withValues(alpha: 0.5),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: aggregatedActivities.length,
                          itemBuilder: (context, index) {
                            final activity = aggregatedActivities[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 4,
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.2),
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  activity.appName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (activity.windowTitle != null &&
                                        activity.windowTitle!.isNotEmpty)
                                      Text(
                                        activity.windowTitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatTime(activity.startTime)} - ${_formatTime(activity.endTime ?? now)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.textTheme.bodySmall?.color
                                            ?.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatDurationDetailed(
                                      _calculateActivityDuration(activity, now),
                                    ),
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Sleep Work Notes Section (Fixed at bottom of list if present)
                  if (widget.relatedSleepPeriods.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: theme.dividerColor.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                      margin: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.bedtime,
                                  size: 16,
                                  color: MacOSTheme.systemBlue,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Sleep During Work',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: MacOSTheme.systemBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: widget.relatedSleepPeriods.length,
                              itemBuilder: (context, index) {
                                final period =
                                    widget.relatedSleepPeriods[index];
                                final note = period.note ?? 'No note';
                                final duration = period.endTime.difference(
                                  period.startTime,
                                );

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: MacOSTheme.systemBlue.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: MacOSTheme.systemBlue.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Field: Sleep Duration
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.timer_outlined,
                                            size: 14,
                                            color: MacOSTheme.systemBlue,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Sleep Duration:',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: MacOSTheme.systemBlue,
                                                ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_formatTime(period.startTime)} - ${_formatTime(period.endTime)} (${_formatDurationDetailed(duration)})',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: MacOSTheme.systemBlue,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // Field: Note
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 2),
                                            child: Icon(
                                              Icons.note_alt_outlined,
                                              size: 14,
                                              color: MacOSTheme.systemBlue,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Note:',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: MacOSTheme
                                                            .systemBlue,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  note,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF252525)
                    : const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Builder(
                builder: (context) {
                  final activities = _aggregateActivities();

                  // Count unique apps
                  final uniqueApps = activities.map((a) => a.appName).toSet();
                  final appCount = uniqueApps.length;
                  final activityCount = activities.length;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left side - App count and activity count
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.apps, size: 16, color: color),
                                const SizedBox(width: 6),
                                Text(
                                  '$appCount ${appCount == 1 ? 'app' : 'apps'}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (activityCount > appCount) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 22),
                                child: Text(
                                  '$activityCount activities',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Right side - Close button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(AppStrings.close),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total: ${_formatDurationDetailed(totalSessionDuration)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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

  /// Calculate the actual duration for an activity
  /// Handles cases where durationSeconds is null or endTime is null
  /// ONLY counts the portion of activity that falls within session boundaries
  Duration _calculateActivityDuration(AppActivity activity, DateTime now) {
    final activityStart = activity.startTime;
    final activityEnd = activity.endTime ?? now;

    debugPrint('[DIALOG] Calculating duration for ${activity.appName}:');
    debugPrint(
      '[DIALOG]   Activity: ${_formatTime(activityStart)} - ${_formatTime(activityEnd)}',
    );
    debugPrint(
      '[DIALOG]   Session: ${_formatTime(widget.startTime)} - ${_formatTime(widget.endTime)}',
    );

    // Check if activity overlaps with session time range
    if (activityEnd.isBefore(widget.startTime) ||
        activityStart.isAfter(widget.endTime)) {
      debugPrint('[DIALOG]   No overlap - returning 0');
      return Duration.zero;
    }

    // Calculate overlapping duration
    final overlapStart = activityStart.isBefore(widget.startTime)
        ? widget.startTime
        : activityStart;
    final overlapEnd = activityEnd.isAfter(widget.endTime)
        ? widget.endTime
        : activityEnd;

    final overlapDuration = overlapEnd.difference(overlapStart);
    debugPrint(
      '[DIALOG]   Overlap: ${_formatTime(overlapStart)} - ${_formatTime(overlapEnd)} = ${overlapDuration.inSeconds}s',
    );

    return overlapDuration.inSeconds > 0 ? overlapDuration : Duration.zero;
  }

  String _formatTime(DateTime time) {
    // Always use local time in 24-hour format
    final localTime = time.toLocal();
    final hours = localTime.hour.toString().padLeft(2, '0');
    final minutes = localTime.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  /// Format duration with detailed breakdown (hours, minutes, seconds)
  /// Used for footer display to show total time more clearly
  String _formatDurationDetailed(Duration duration) {
    if (duration.inSeconds <= 0) return '0s';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];

    if (hours > 0) {
      parts.add('${hours}h');
    }
    if (minutes > 0 || hours > 0) {
      parts.add('${minutes}m');
    }
    if (seconds > 0 || (hours == 0 && minutes == 0)) {
      parts.add('${seconds}s');
    }

    return parts.join(' ');
  }

  /// Get sorted activities by duration (no aggregation for accurate time display)
  /// Shows each activity instance separately with its actual start/end times
  /// ONLY includes activities that overlap with the session time boundaries
  List<AppActivity> _aggregateActivities() {
    if (widget.activities.isEmpty) {
      debugPrint('[DIALOG] No activities provided to dialog');
      return [];
    }

    debugPrint(
      '[DIALOG] Processing ${widget.activities.length} activities for session overlap',
    );

    final now = DateTime.now();

    // Filter activities to only include those within session boundaries
    final filteredActivities = widget.activities.where((activity) {
      final activityStart = activity.startTime;
      final activityEnd = activity.endTime ?? now;

      // Include activity if it overlaps with session time range
      final overlaps =
          !(activityEnd.isBefore(widget.startTime) ||
              activityStart.isAfter(widget.endTime));

      if (overlaps) {
        debugPrint('[DIALOG] ✓ ${activity.appName} overlaps with session');
      } else {
        debugPrint('[DIALOG] ✗ ${activity.appName} does not overlap');
      }

      return overlaps;
    }).toList();

    debugPrint(
      '[DIALOG] ${filteredActivities.length} activities remain after filtering',
    );

    // Sort by start time descending
    filteredActivities.sort((a, b) {
      return b.startTime.compareTo(a.startTime);
    });

    return filteredActivities;
  }
}
