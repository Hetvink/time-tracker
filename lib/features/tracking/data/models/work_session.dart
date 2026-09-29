import 'app_activity.dart';

class WorkSession {
  final dynamic sessionId; // Links to timesheet attendance session
  final DateTime startTime;
  final DateTime endTime;
  final Duration totalDuration; // Full session duration (working time)
  final List<TimeSegment> segments; // 15-minute segments

  WorkSession({
    this.sessionId, // FIX: Optional sessionId for linking to timesheet
    required this.startTime,
    required this.endTime,
    required this.totalDuration,
    required this.segments,
  });

  /// Number of 15-minute segments in this session
  int get segmentCount => segments.length;

  /// Get all unique apps used in this session
  Set<String> get appsUsed {
    final apps = <String>{};
    for (final segment in segments) {
      for (final activity in segment.activities) {
        apps.add(activity.appName);
      }
    }
    return apps;
  }

  /// WORKING TIME: Full session duration from check-in to check-out
  /// This is the total time shown in the timesheet
  Duration get workingTime => totalDuration;

  /// ACTIVITY TIME: Actual app usage time tracked by activities
  /// This is the sum of all activity durations
  Duration get activityTime {
    Duration total = Duration.zero;
    for (final segment in segments) {
      for (final activity in segment.activities) {
        total += activity.duration;
      }
    }
    return total;
  }

  /// IDLE TIME: Working time minus activity time
  /// This represents time when you were checked in but not actively using apps
  Duration get idleTime {
    final idle = workingTime - activityTime;
    return idle.isNegative ? Duration.zero : idle;
  }

  /// Get total work time vs break time (legacy methods)
  Duration get workTime {
    return segments.fold(
      Duration.zero,
      (sum, segment) => sum + segment.workDuration,
    );
  }

  Duration get breakTime {
    return segments.fold(
      Duration.zero,
      (sum, segment) => sum + segment.breakDuration,
    );
  }
}

/// SIMPLIFIED: 15-minute time segment showing app usage
/// - Part of a work session (timesheet check-in period)
/// - Shows which apps were used in this 15-minute block
/// - primaryActivity = most-used app in the segment
class TimeSegment {
  final DateTime startTime;
  final DateTime endTime;
  final List<AppActivity> activities; // All activities in this 15-min period
  final AppActivity? primaryActivity; // Most used app in this segment
  final String? activityType; // Type determined by timesheet state

  TimeSegment({
    required this.startTime,
    required this.endTime,
    required this.activities,
    this.primaryActivity, // FIX: Now optional
    this.activityType, // FIX: New field for work/break distinction
  });

  Duration get duration => endTime.difference(startTime);

  /// Get work time in this segment
  Duration get workDuration {
    return activities
        .where((a) => a.activityType == 'work')
        .fold(Duration.zero, (sum, activity) => sum + activity.duration);
  }

  /// Get break time in this segment
  Duration get breakDuration {
    return activities
        .where((a) => a.activityType == 'break')
        .fold(Duration.zero, (sum, activity) => sum + activity.duration);
  }

  /// Get the most used app in this segment
  String get primaryAppName => primaryActivity?.appName ?? 'No Activity';

  /// FIX: Get activity type - prioritize explicit activityType, fallback to primary activity
  String get segmentActivityType {
    if (activityType != null) return activityType!;
    if (primaryActivity != null) return primaryActivity!.activityType;
    // Determine by majority of activities
    final workCount = activities.where((a) => a.activityType == 'work').length;
    final breakCount = activities
        .where((a) => a.activityType == 'break')
        .length;
    return breakCount > workCount ? 'break' : 'work';
  }

  /// Get summary of apps used in this segment
  Map<String, Duration> get appUsageSummary {
    final Map<String, Duration> usage = {};
    for (final activity in activities) {
      usage[activity.appName] =
          (usage[activity.appName] ?? Duration.zero) + activity.duration;
    }
    return usage;
  }

  /// Sort activities by duration (longest first)
  List<AppActivity> get activitiesByDuration {
    final sorted = List<AppActivity>.from(activities);
    sorted.sort((a, b) => b.duration.compareTo(a.duration));
    return sorted;
  }
}
