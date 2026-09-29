/// Domain model for App Activity
/// Platform-agnostic representation of tracked application usage
class ActivityModel {
  final String id; // Supabase UUID
  final String? sessionId;
  final String userId;
  final String appName;
  final String? windowTitle;
  final String? bundleId;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime startTimeUtc;
  final DateTime? endTimeUtc;
  final int? durationSeconds;
  final ActivityType activityType;
  final String? localId; // Reference to desktop's local SQLite ID
  final DateTime createdAt;
  final DateTime updatedAt;

  const ActivityModel({
    required this.id,
    this.sessionId,
    required this.userId,
    required this.appName,
    this.windowTitle,
    this.bundleId,
    required this.startTime,
    this.endTime,
    required this.startTimeUtc,
    this.endTimeUtc,
    this.durationSeconds,
    this.activityType = ActivityType.work,
    this.localId,
    required this.createdAt,
    required this.updatedAt,
  });

  Duration get duration {
    if (durationSeconds != null) {
      // Validate stored duration is reasonable (< 24 hours)
      if (durationSeconds! < 0) {
        return Duration.zero;
      }
      if (durationSeconds! > 86400) {
        // Cap at 24 hours
        return const Duration(seconds: 86400);
      }
      return Duration(seconds: durationSeconds!);
    }
    if (endTime != null) {
      final calculated = endTime!.difference(startTime);
      // Validate calculated duration
      if (calculated.isNegative) {
        return Duration.zero;
      }
      if (calculated.inSeconds > 86400) {
        // Cap at 24 hours
        return const Duration(seconds: 86400);
      }
      return calculated;
    }
    // For active activities, return zero instead of open-ended duration
    return Duration.zero;
  }

  bool get isActive => endTime == null;

  ActivityModel copyWith({
    String? id,
    String? sessionId,
    String? userId,
    String? appName,
    String? windowTitle,
    String? bundleId,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? startTimeUtc,
    DateTime? endTimeUtc,
    int? durationSeconds,
    ActivityType? activityType,
    String? localId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ActivityModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      appName: appName ?? this.appName,
      windowTitle: windowTitle ?? this.windowTitle,
      bundleId: bundleId ?? this.bundleId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startTimeUtc: startTimeUtc ?? this.startTimeUtc,
      endTimeUtc: endTimeUtc ?? this.endTimeUtc,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      activityType: activityType ?? this.activityType,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'app_name': appName,
      'window_title': windowTitle,
      'bundle_id': bundleId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'start_time_utc': startTimeUtc.toIso8601String(),
      'end_time_utc': endTimeUtc?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'activity_type': activityType.value,
      'local_id': localId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    // Parse UTC times first as they are the source of truth
    final startTimeUtc = DateTime.parse(json['start_time_utc'] as String);
    final endTimeUtc = json['end_time_utc'] != null
        ? DateTime.parse(json['end_time_utc'] as String)
        : null;

    // Robust parsing: Always derive local time from UTC to ensure consistency
    // with SessionModel and prevent timezone mismatches
    final startTime = startTimeUtc.toLocal();
    final endTime = endTimeUtc?.toLocal();

    // Safe numeric parsing
    final durationSeconds = json['duration_seconds'] is num
        ? (json['duration_seconds'] as num).toInt()
        : null;

    return ActivityModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String?,
      userId: json['user_id'] as String,
      appName: json['app_name'] as String,
      windowTitle: json['window_title'] as String?,
      bundleId: json['bundle_id'] as String?,
      startTime: startTime,
      endTime: endTime,
      startTimeUtc: startTimeUtc,
      endTimeUtc: endTimeUtc,
      durationSeconds: durationSeconds,
      activityType: ActivityType.fromString(
        json['activity_type'] as String? ?? 'work',
      ),
      localId: json['local_id'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

enum ActivityType {
  work,
  break_,
  idle;

  String get value {
    switch (this) {
      case ActivityType.work:
        return 'work';
      case ActivityType.break_:
        return 'break';
      case ActivityType.idle:
        return 'idle';
    }
  }

  static ActivityType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'work':
        return ActivityType.work;
      case 'break':
        return ActivityType.break_;
      case 'idle':
        return ActivityType.idle;
      default:
        return ActivityType.work;
    }
  }
}
