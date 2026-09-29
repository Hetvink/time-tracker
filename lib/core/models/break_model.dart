/// Domain model for Break Period
/// Platform-agnostic representation of a break during a work session
class BreakModel {
  final String id; // Supabase UUID
  final String sessionId;
  final String userId;
  final DateTime breakStartTime;
  final DateTime? breakEndTime;
  final DateTime breakStartTimeUtc;
  final DateTime? breakEndTimeUtc;
  final int? durationSeconds;
  final String? note;
  final String? localId; // Reference to desktop's local SQLite ID
  final DateTime createdAt;
  final DateTime updatedAt;

  const BreakModel({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.breakStartTime,
    this.breakEndTime,
    required this.breakStartTimeUtc,
    this.breakEndTimeUtc,
    this.durationSeconds,
    this.note,
    this.localId,
    required this.createdAt,
    required this.updatedAt,
  });

  Duration get duration {
    if (durationSeconds != null) {
      return Duration(seconds: durationSeconds!);
    }
    if (breakEndTime != null) {
      return breakEndTime!.difference(breakStartTime);
    }
    // Active break - return duration so far
    return DateTime.now().difference(breakStartTime);
  }

  bool get isActive => breakEndTime == null;

  BreakModel copyWith({
    String? id,
    String? sessionId,
    String? userId,
    DateTime? breakStartTime,
    DateTime? breakEndTime,
    DateTime? breakStartTimeUtc,
    DateTime? breakEndTimeUtc,
    int? durationSeconds,
    String? note,
    String? localId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BreakModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      breakStartTime: breakStartTime ?? this.breakStartTime,
      breakEndTime: breakEndTime ?? this.breakEndTime,
      breakStartTimeUtc: breakStartTimeUtc ?? this.breakStartTimeUtc,
      breakEndTimeUtc: breakEndTimeUtc ?? this.breakEndTimeUtc,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      note: note ?? this.note,
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
      'break_start_time': breakStartTime.toIso8601String(),
      'break_end_time': breakEndTime?.toIso8601String(),
      'break_start_time_utc': breakStartTimeUtc.toIso8601String(),
      'break_end_time_utc': breakEndTimeUtc?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'note': note,
      'local_id': localId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory BreakModel.fromJson(Map<String, dynamic> json) {
    // CRITICAL: Always use UTC times as source of truth to avoid timezone confusion
    final breakStartTimeUtc = DateTime.parse(
      json['break_start_time_utc'] as String,
    );
    final breakEndTimeUtc = json['break_end_time_utc'] != null
        ? DateTime.parse(json['break_end_time_utc'] as String)
        : null;

    final breakStartTime = breakStartTimeUtc.toLocal();
    final breakEndTime = breakEndTimeUtc?.toLocal();

    return BreakModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      breakStartTime: breakStartTime,
      breakEndTime: breakEndTime,
      breakStartTimeUtc: breakStartTimeUtc,
      breakEndTimeUtc: breakEndTimeUtc,
      durationSeconds: json['duration_seconds'] as int?,
      note: json['note'] as String?,
      localId: json['local_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
