import '../../../tracking/data/models/attendance_state.dart';

class DailyTimeSheet {
  final DateTime date;
  final List<AttendanceSession> sessions;

  DailyTimeSheet({required this.date, required this.sessions});

  /// Create a DailyTimesheet from database session maps
  factory DailyTimeSheet.fromDb(
    DateTime date,
    List<Map<String, dynamic>> sessionMaps,
  ) {
    final sessions = sessionMaps.map((sessionMap) {
      // Convert session map to AttendanceSession
      // Note: breaks and work during sleep periods should be loaded separately
      return AttendanceSession.fromMap(sessionMap, [], []);
    }).toList();

    return DailyTimeSheet(date: date, sessions: sessions);
  }

  /// Create an empty DailyTimesheet for a date with no sessions
  factory DailyTimeSheet.empty(DateTime date) {
    return DailyTimeSheet(date: date, sessions: []);
  }

  Duration get totalWorkTime {
    // Calculate effective work duration (Merging overlaps and subtracting breaks)
    return _calculateEffectiveWorkDuration();
  }

  Duration get totalBreakTime {
    return sessions.fold<Duration>(
      Duration.zero,
      (sum, session) => sum + session.totalBreakDuration,
    );
  }

  Duration get netWorkTime {
    // Normal Work = Total Work - Sleep Work
    final net = totalWorkTime - totalWorkDuringSleepTime;
    return net.isNegative ? Duration.zero : net;
  }

  Duration get totalWorkDuringSleepTime {
    // Calculate effective sleep duration (Merging overlaps)
    return _calculateEffectiveSleepDuration();
  }

  Duration get totalWorkTimeWithSleep {
    // Total Work already includes sleep (if calculated from start-end time)
    // The previous implementation added them together, causing double and inaccurate counting.
    // Now, `totalWorkTime` is the master "Total Effective Duration".
    return totalWorkTime;
  }

  Duration get totalGrossWorkTime {
    // User requested Total Work to be (Net Work + Break Time)
    // This represents the "Gross" duration spent "at work" (excluding gaps between sessions)
    return totalWorkTime + totalBreakTime;
  }

  // --- Effective Duration Helpers ---

  Duration _calculateEffectiveWorkDuration() {
    if (sessions.isEmpty) return Duration.zero;

    // CRITICAL FIX: For closed sessions, use the stored total_work_seconds
    // instead of recalculating from timestamps. This prevents incorrect
    // durations when viewing later (DateTime.now() fallback) or timezone issues.
    //
    // The workDuration getter already handles this correctly:
    // - For closed sessions: uses capturedWorkDuration (from total_work_seconds)
    // - For active sessions: calculates in real-time with break subtraction
    //
    // This fixes the midnight transition bug where split sessions showed
    // incorrect total hours (e.g., 7-8h instead of 5-6h).

    Duration totalDuration = Duration.zero;
    for (var session in sessions) {
      totalDuration += session.workDuration;
    }
    return totalDuration;
  }

  Duration _calculateEffectiveSleepDuration() {
    List<({DateTime start, DateTime end})> sleepSegments = [];
    for (var session in sessions) {
      for (var s in session.workDuringSleepPeriods) {
        sleepSegments.add((
          start: s.sleepStartTime.toUtc(),
          end: s.wakeTime.toUtc(),
        ));
      }
    }
    return _mergeAndSumDuration(sleepSegments);
  }

  Duration _mergeAndSumDuration(
    List<({DateTime start, DateTime end})> intervals,
  ) {
    if (intervals.isEmpty) return Duration.zero;

    // Sort by start
    intervals.sort((a, b) => a.start.compareTo(b.start));

    int totalMicroseconds = 0;
    var currentStart = intervals.first.start;
    var currentEnd = intervals.first.end;

    for (int i = 1; i < intervals.length; i++) {
      final next = intervals[i];
      if (next.start.isBefore(currentEnd)) {
        // Overlap
        if (next.end.isAfter(currentEnd)) {
          currentEnd = next.end;
        }
      } else {
        // No overlap, add and reset
        totalMicroseconds += currentEnd.difference(currentStart).inMicroseconds;
        currentStart = next.start;
        currentEnd = next.end;
      }
    }
    // Add last
    totalMicroseconds += currentEnd.difference(currentStart).inMicroseconds;
    return Duration(microseconds: totalMicroseconds);
  }

  Duration get totalDuration {
    // Total time from first check-in to last check-out
    if (sessions.isEmpty) return Duration.zero;

    final firstCheckIn = sessions.first.checkInTime;
    final lastCheckOut = sessions.last.checkOutTime ?? DateTime.now();

    return lastCheckOut.difference(firstCheckIn);
  }

  int get totalSessions => sessions.length;
  int get totalBreaks =>
      sessions.fold<int>(0, (sum, session) => sum + session.breaks.length);

  bool get hasActiveSessions => sessions.any((s) => !s.isClosed);

  String get dateFormatted {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDate = DateTime(date.year, date.month, date.day);

    if (sessionDate == today) {
      return 'Today';
    } else if (sessionDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String get totalWorkDurationFormatted => _formatDuration(totalWorkTime);
  String get totalBreakDurationFormatted => _formatDuration(totalBreakTime);
  String get netWorkDurationFormatted => _formatDuration(netWorkTime);

  String _formatDuration(Duration duration) {
    var seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    seconds = seconds % 3600;
    final minutes = seconds ~/ 60;
    seconds = seconds % 60;

    final hourStr = hours.toString().padLeft(2, '0');
    final minuteStr = minutes.toString().padLeft(2, '0');
    final secondStr = seconds.toString().padLeft(2, '0');

    return '$hourStr:$minuteStr:$secondStr';
  }
}

class AttendanceSession {
  final dynamic id; // Can be int (SQLite) or String (Supabase UUID)
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final EventSource checkInSource;
  final EventSource? checkOutSource;
  final List<BreakPeriod> breaks;
  final List<WorkDuringSleepPeriod> workDuringSleepPeriods;
  final bool isClosed;
  final dynamic continuationOfSessionId; // Can be int or String
  final String? continuationReason;
  final String? originalTimezone;
  final DateTime? checkInTimeUtc;
  final DateTime? checkOutTimeUtc;
  final Duration? capturedWorkDuration;

  AttendanceSession({
    required this.id,
    required this.checkInTime,
    this.checkOutTime,
    required this.checkInSource,
    this.checkOutSource,
    required this.breaks,
    this.workDuringSleepPeriods = const [],
    required this.isClosed,
    this.continuationOfSessionId,
    this.continuationReason,
    this.originalTimezone,
    this.checkInTimeUtc,
    this.checkOutTimeUtc,
    this.capturedWorkDuration,
  });

  Duration get workDuration {
    // For closed sessions, ALWAYS use the stored duration if available
    // This is the NET work time (already has breaks subtracted)
    // This prevents phantom durations from being calculated from timestamps
    // when total_work_seconds is 0 or NULL
    if (isClosed) {
      // If we have a captured duration (even if it's zero), use it
      if (capturedWorkDuration != null) {
        return capturedWorkDuration!;
      }
      // If capturedWorkDuration is null for a closed session, treat it as zero
      // This handles cases where total_work_seconds is NULL in the database
      return Duration.zero;
    }

    // For active sessions, calculate work time using segment-based approach
    // This prevents negative work time when breaks exceed work duration

    final nowUtc = DateTime.now().toUtc();
    final checkInUtc = checkInTimeUtc ?? checkInTime.toUtc();
    final checkOutUtc = checkOutTimeUtc ?? (checkOutTime?.toUtc() ?? nowUtc);

    // Build timeline of break periods
    final breakPeriods = <({DateTime start, DateTime end})>[];
    for (var breakPeriod in breaks) {
      if (breakPeriod.endTime != null) {
        breakPeriods.add((
          start: breakPeriod.startTime.toUtc(),
          end: breakPeriod.endTime!.toUtc(),
        ));
      }
    }

    // Sort by start time
    breakPeriods.sort((a, b) => a.start.compareTo(b.start));

    // Calculate work time as segments between breaks
    Duration sessionWorkTime = Duration.zero;
    DateTime currentPosition = checkInUtc;

    for (var breakPeriod in breakPeriods) {
      // Add work time from current position to break start
      if (breakPeriod.start.isAfter(currentPosition)) {
        sessionWorkTime += breakPeriod.start.difference(currentPosition);
      }
      // Move position to break end
      if (breakPeriod.end.isAfter(currentPosition)) {
        currentPosition = breakPeriod.end;
      }
    }

    // Add remaining work time from last break end to checkout
    if (checkOutUtc.isAfter(currentPosition)) {
      sessionWorkTime += checkOutUtc.difference(currentPosition);
    }

    return sessionWorkTime;
  }

  Duration get totalBreakDuration {
    return breaks.fold<Duration>(
      Duration.zero,
      (sum, breakPeriod) => sum + breakPeriod.duration,
    );
  }

  Duration get netWorkDuration {
    // workDuration already has breaks excluded for active sessions
    // and capturedWorkDuration already has breaks excluded for closed sessions
    return workDuration;
  }

  String get checkInTimeFormatted {
    // Use UTC time converted to local to avoid timezone issues
    final localTime = checkInTimeUtc?.toLocal() ?? checkInTime;
    final hours = localTime.hour;
    final minutes = localTime.minute;
    final period = hours >= 12 ? 'PM' : 'AM';
    final displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours);
    return '$displayHour:${minutes.toString().padLeft(2, '0')} $period';
  }

  String get checkOutTimeFormatted {
    if (checkOutTime == null && checkOutTimeUtc == null) return 'Active';
    // Use UTC time converted to local to avoid timezone issues
    final localTime = checkOutTimeUtc?.toLocal() ?? checkOutTime;
    if (localTime == null) return 'Active';
    final hours = localTime.hour;
    final minutes = localTime.minute;
    final period = hours >= 12 ? 'PM' : 'AM';
    final displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours);
    return '$displayHour:${minutes.toString().padLeft(2, '0')} $period';
  }

  String get sourceLabel {
    switch (checkInSource) {
      case EventSource.autoSystemStart:
        return 'Auto (Boot)';
      case EventSource.manualUser:
        return 'Manual';
      case EventSource.systemRecovery:
        return 'Recovery';
      case EventSource.autoMidnightTransition:
        return 'Auto (Day Change)';
      default:
        return 'Unknown';
    }
  }

  bool get isContinuation => continuationOfSessionId != null;

  factory AttendanceSession.fromMap(
    Map<String, dynamic> map,
    List<BreakPeriod> breaks,
    List<WorkDuringSleepPeriod> workDuringSleepPeriods,
  ) {
    // Helper to parse local time strings correctly as local time
    DateTime parseLocalTime(String timeStr) {
      final parsed = DateTime.parse(timeStr);
      // If the parsed time is UTC (has 'Z' or offset), convert to local
      if (parsed.isUtc) {
        return parsed.toLocal();
      }
      // If already local, return as-is
      return parsed;
    }

    // Handle both int (SQLite) and String (Supabase UUID) IDs
    final id = map['id']; // Keep as-is, can be int or String
    final continuationId =
        map['continuation_of_session_id']; // Can be int or String

    // Handle is_closed - can be int (SQLite) or bool (Supabase)
    final isClosed = map['is_closed'] is bool
        ? map['is_closed'] as bool
        : (map['is_closed'] as int) == 1;

    return AttendanceSession(
      id: id,
      checkInTime: parseLocalTime(map['check_in_time'] as String),
      checkOutTime: map['check_out_time'] != null
          ? parseLocalTime(map['check_out_time'] as String)
          : null,
      checkInSource: EventSource.values.firstWhere(
        (e) => e.name == map['check_in_source'],
        orElse: () => EventSource.manualUser,
      ),
      checkOutSource: map['check_out_source'] != null
          ? EventSource.values.firstWhere(
              (e) => e.name == map['check_out_source'],
              orElse: () => EventSource.manualUser,
            )
          : null,
      breaks: breaks,
      workDuringSleepPeriods: workDuringSleepPeriods,
      isClosed: isClosed,
      continuationOfSessionId: continuationId,
      continuationReason: map['continuation_reason'] as String?,
      originalTimezone: map['original_timezone'] as String?,
      checkInTimeUtc: map['check_in_time_utc'] != null
          ? DateTime.parse(map['check_in_time_utc'] as String).isUtc
                ? DateTime.parse(map['check_in_time_utc'] as String)
                : DateTime.parse('${map['check_in_time_utc']}Z')
          : null,
      checkOutTimeUtc: map['check_out_time_utc'] != null
          ? DateTime.parse(map['check_out_time_utc'] as String).isUtc
                ? DateTime.parse(map['check_out_time_utc'] as String)
                : DateTime.parse('${map['check_out_time_utc']}Z')
          : null,
      capturedWorkDuration: map['total_work_seconds'] != null
          ? Duration(seconds: map['total_work_seconds'] as int)
          : null,
    );
  }
}

/// Represents a work-during-sleep period
class WorkDuringSleepPeriod {
  final DateTime sleepStartTime;
  final DateTime wakeTime;
  final String note;

  WorkDuringSleepPeriod({
    required this.sleepStartTime,
    required this.wakeTime,
    required this.note,
  });

  Duration get duration => wakeTime.difference(sleepStartTime);
}
