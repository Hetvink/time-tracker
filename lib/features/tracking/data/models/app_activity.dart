/// SIMPLIFIED: App activity record from native tracking
/// - Captured by native platform code (macOS/Windows/Linux)
/// - sessionId links to timesheet attendance_sessions table
/// - Only activities with valid sessionId are shown in UI
/// - activityType is stored but Flutter doesn't determine it
/// - Native tracking handles all detection, Flutter just displays
class AppActivity {
  final int? id;
  final dynamic sessionId; // Links to timesheet - dynamic for int or String
  final String appName;
  final String? windowTitle;
  final String? bundleId;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationSeconds;
  final String activityType; // 'work', 'break', 'idle' (from native/DB)

  AppActivity({
    this.id,
    this.sessionId,
    required this.appName,
    this.windowTitle,
    this.bundleId,
    required this.startTime,
    this.endTime,
    this.durationSeconds,
    this.activityType = 'work',
  });

  /// FIXED: Duration calculation with validation
  /// - Prefers stored durationSeconds (most accurate)
  /// - Falls back to endTime - startTime
  /// - Returns zero for active activities (prevents runaway durations)
  /// - Validates duration is not negative or unreasonably long
  Duration get duration {
    if (durationSeconds != null) {
      // FIX: Validate stored duration is reasonable (< 24 hours)
      if (durationSeconds! < 0) {
        _logWarning(
          '[WARN] Negative duration detected for activity $id: $durationSeconds',
        );
        return Duration.zero;
      }
      if (durationSeconds! > 86400) {
        // > 24 hours
        _logWarning(
          '[WARN] Unreasonable duration detected for activity $id: ${durationSeconds! ~/ 3600}h',
        );
        return const Duration(seconds: 86400); // Cap at 24 hours
      }
      return Duration(seconds: durationSeconds!);
    }
    if (endTime != null) {
      final calculated = endTime!.difference(startTime);
      // FIX: Validate calculated duration
      if (calculated.isNegative) {
        _logWarning('[WARN] Negative duration for activity $id: $calculated');
        return Duration.zero;
      }
      if (calculated.inSeconds > 86400) {
        // > 24 hours
        _logWarning(
          '[WARN] Duration > 24h for activity $id: ${calculated.inHours}h',
        );
        return const Duration(seconds: 86400); // Cap at 24 hours
      }
      return calculated;
    }
    // FIX: For active activities, return zero instead of open-ended duration
    // This prevents showing thousands of hours for unclosed activities
    return Duration.zero;
  }

  void _logWarning(String message) {
    // Only log in debug mode - using assert for zero runtime cost in production
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }

  bool get isActive => endTime == null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'app_name': appName,
      'window_title': windowTitle,
      'bundle_id': bundleId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'start_time_utc': startTime.toUtc().toIso8601String(),
      'end_time_utc': endTime?.toUtc().toIso8601String(),
      'activity_type': activityType,
    };
  }

  factory AppActivity.fromMap(Map<String, dynamic> map) {
    // Robust parsing: Use UTC times as source of truth if available
    DateTime startTime;
    if (map['start_time_utc'] != null) {
      startTime = DateTime.parse(map['start_time_utc'] as String).toLocal();
    } else {
      startTime = DateTime.parse(map['start_time'] as String);
    }

    DateTime? endTime;
    if (map['end_time_utc'] != null) {
      endTime = DateTime.parse(map['end_time_utc'] as String).toLocal();
    } else if (map['end_time'] != null) {
      endTime = DateTime.parse(map['end_time'] as String);

      // FIX: Heuristic for timezone mismatch detection
      // If end_time was stored as UTC string but parsed as Local (missing Z),
      // it will appear to be before start_time (if timezone is ahead of UTC).
      // We attempt to correct this by adding the local offset.
      if (endTime.isBefore(startTime)) {
        final offset = DateTime.now().timeZoneOffset;
        final corrected = endTime.add(offset);
        // Only apply if it makes sense (activity ends after it starts)
        if (corrected.isAfter(startTime) ||
            corrected.isAtSameMomentAs(startTime)) {
          // Double check we aren't creating a huge duration (e.g. > 24h)
          // unless the original mismatch was also huge.
          // For the 5.5h case, duration becomes small positive.
          endTime = corrected;
        }
      }
    }

    return AppActivity(
      id: map['id'] as int?,
      sessionId: map['session_id'], // Keep as dynamic (int or String)
      appName: map['app_name'] as String,
      windowTitle: map['window_title'] as String?,
      bundleId: map['bundle_id'] as String?,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: _parseNullableInt(map['duration_seconds']),
      activityType: map['activity_type'] as String? ?? 'work',
    );
  }

  /// Safely parse a nullable int from database (handles both int and String)
  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  AppActivity copyWith({
    int? id,
    dynamic sessionId,
    String? appName,
    String? windowTitle,
    String? bundleId,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    String? activityType,
  }) {
    return AppActivity(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      appName: appName ?? this.appName,
      windowTitle: windowTitle ?? this.windowTitle,
      bundleId: bundleId ?? this.bundleId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      activityType: activityType ?? this.activityType,
    );
  }
}

/// Aggregated activity data for timeline view
class ActivityBlock {
  final DateTime startTime;
  final DateTime endTime;
  final String appName;
  final String? windowTitle;
  final String activityType;
  final Duration duration;

  ActivityBlock({
    required this.startTime,
    required this.endTime,
    required this.appName,
    this.windowTitle,
    required this.activityType,
    required this.duration,
  });
}

/// Daily activity summary
class DailyActivity {
  final DateTime date;
  final List<AppActivity> activities;

  DailyActivity({required this.date, required this.activities});

  Duration get totalWorkTime {
    return activities
        .where((a) => a.activityType == 'work')
        .fold(Duration.zero, (sum, activity) => sum + activity.duration);
  }

  Duration get totalBreakTime {
    return activities
        .where((a) => a.activityType == 'break')
        .fold(Duration.zero, (sum, activity) => sum + activity.duration);
  }

  Map<String, Duration> get appUsageMap {
    final Map<String, Duration> usage = {};
    for (final activity in activities) {
      usage[activity.appName] =
          (usage[activity.appName] ?? Duration.zero) + activity.duration;
    }
    return usage;
  }

  List<MapEntry<String, Duration>> get topApps {
    final entries = appUsageMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(10).toList();
  }
}
