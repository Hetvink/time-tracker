/// Domain model for Work Session
/// Platform-agnostic representation of an attendance session
class SessionModel {
  final String id; // Supabase UUID
  final String userId;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final DateTime checkInTimeUtc;
  final DateTime? checkOutTimeUtc;
  final SessionSource checkInSource;
  final SessionSource? checkOutSource;
  final int? totalWorkSeconds;
  final bool isClosed;
  final DateTime? lastSeenTime;
  final String? continuationReason;
  final String? originalTimezone;
  final String? localId; // Reference to desktop's local SQLite ID
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionModel({
    required this.id,
    required this.userId,
    required this.checkInTime,
    this.checkOutTime,
    required this.checkInTimeUtc,
    this.checkOutTimeUtc,
    required this.checkInSource,
    this.checkOutSource,
    this.totalWorkSeconds,
    this.isClosed = false,
    this.lastSeenTime,
    this.continuationReason,
    this.originalTimezone,
    this.localId,
    required this.createdAt,
    required this.updatedAt,
  });

  Duration get totalDuration {
    if (totalWorkSeconds != null) {
      return Duration(seconds: totalWorkSeconds!);
    }
    if (checkOutTime != null) {
      return checkOutTime!.difference(checkInTime);
    }
    // Active session - return duration so far
    return DateTime.now().difference(checkInTime);
  }

  bool get isActive => !isClosed && checkOutTime == null;

  /// Total break seconds - not stored in SessionModel
  /// Break data is stored separately in break_periods table
  /// This getter returns null for compatibility with legacy code
  int? get totalBreakSeconds => null;

  SessionModel copyWith({
    String? id,
    String? userId,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    DateTime? checkInTimeUtc,
    DateTime? checkOutTimeUtc,
    SessionSource? checkInSource,
    SessionSource? checkOutSource,
    int? totalWorkSeconds,
    bool? isClosed,
    DateTime? lastSeenTime,
    String? continuationReason,
    String? originalTimezone,
    String? localId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      checkInTimeUtc: checkInTimeUtc ?? this.checkInTimeUtc,
      checkOutTimeUtc: checkOutTimeUtc ?? this.checkOutTimeUtc,
      checkInSource: checkInSource ?? this.checkInSource,
      checkOutSource: checkOutSource ?? this.checkOutSource,
      totalWorkSeconds: totalWorkSeconds ?? this.totalWorkSeconds,
      isClosed: isClosed ?? this.isClosed,
      lastSeenTime: lastSeenTime ?? this.lastSeenTime,
      continuationReason: continuationReason ?? this.continuationReason,
      originalTimezone: originalTimezone ?? this.originalTimezone,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'check_in_time': checkInTime.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'check_in_time_utc': checkInTimeUtc.toIso8601String(),
      'check_out_time_utc': checkOutTimeUtc?.toIso8601String(),
      'check_in_source': checkInSource.value,
      'check_out_source': checkOutSource?.value,
      'total_work_seconds': totalWorkSeconds,
      'is_closed': isClosed,
      'last_seen_time': lastSeenTime?.toIso8601String(),
      'continuation_reason': continuationReason,
      'original_timezone': originalTimezone,
      'local_id': localId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    // CRITICAL: Always use UTC times as source of truth to avoid timezone confusion
    final checkInTimeUtc = DateTime.parse(json['check_in_time_utc'] as String);
    final checkOutTimeUtc = json['check_out_time_utc'] != null
        ? DateTime.parse(json['check_out_time_utc'] as String)
        : null;

    final checkInTime = checkInTimeUtc.toLocal();
    final checkOutTime = checkOutTimeUtc?.toLocal();

    return SessionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      checkInTimeUtc: checkInTimeUtc,
      checkOutTimeUtc: checkOutTimeUtc,
      checkInSource: SessionSource.fromString(
        json['check_in_source'] as String,
      ),
      checkOutSource: json['check_out_source'] != null
          ? SessionSource.fromString(json['check_out_source'] as String)
          : null,
      totalWorkSeconds: json['total_work_seconds'] as int?,
      isClosed: json['is_closed'] as bool? ?? false,
      lastSeenTime: json['last_seen_time'] != null
          ? DateTime.parse(json['last_seen_time'] as String)
          : null,
      continuationReason: json['continuation_reason'] as String?,
      originalTimezone: json['original_timezone'] as String?,
      localId: json['local_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

enum SessionSource {
  manualUser,
  automaticWake,
  systemBoot,
  activityResumed,
  automaticSleep,
  systemShutdown,
  idleTimeout;

  String get value {
    switch (this) {
      case SessionSource.manualUser:
        return 'manual_user';
      case SessionSource.automaticWake:
        return 'automatic_wake';
      case SessionSource.systemBoot:
        return 'system_boot';
      case SessionSource.activityResumed:
        return 'activity_resumed';
      case SessionSource.automaticSleep:
        return 'automatic_sleep';
      case SessionSource.systemShutdown:
        return 'system_shutdown';
      case SessionSource.idleTimeout:
        return 'idle_timeout';
    }
  }

  static SessionSource fromString(String value) {
    switch (value.toLowerCase()) {
      case 'manual_user':
        return SessionSource.manualUser;
      case 'automatic_wake':
        return SessionSource.automaticWake;
      case 'system_boot':
        return SessionSource.systemBoot;
      case 'activity_resumed':
        return SessionSource.activityResumed;
      case 'automatic_sleep':
        return SessionSource.automaticSleep;
      case 'system_shutdown':
        return SessionSource.systemShutdown;
      case 'idle_timeout':
        return SessionSource.idleTimeout;
      default:
        return SessionSource.manualUser;
    }
  }
}
