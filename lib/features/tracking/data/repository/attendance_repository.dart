import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/attendance_state.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';

class AttendanceRepository {
  final Database _db;
  int? _currentUserId;

  // Expose db for subclasses
  Database get db => _db;

  AttendanceRepository(this._db);

  /// Set the current user ID for filtering queries
  /// This should be called after authentication
  void setCurrentUserId(int? userId) {
    _currentUserId = userId;
    debugPrint('[AttendanceRepository] Current user ID set to: $userId');
  }

  /// Get current user ID
  int? get currentUserId => _currentUserId;

  Future<int> createSession(
    DateTime checkInTime,
    EventSource source, {
    int? userId,
    int? continuationOfSessionId,
    String? continuationReason,
  }) async {
    final checkInUtc = checkInTime.toUtc();
    final timezone = checkInTime.timeZoneName;

    return await _db.insert('attendance_sessions', {
      'user_id': userId,
      'check_in_time': checkInTime.toIso8601String(),
      'check_in_time_utc': checkInUtc.toIso8601String(),
      'check_in_source': source.name,
      'original_timezone': timezone,
      'continuation_of_session_id': continuationOfSessionId,
      'continuation_reason': continuationReason,
      'is_closed': 0,
      'last_seen_time': DateTime.now().toUtc().toIso8601String(), // Ensure UTC
    });
  }

  Future<void> closeSession(
    int sessionId,
    DateTime checkOutTime,
    EventSource source,
  ) async {
    // VALIDATION: Ensure checkOutTime is in local time
    // This is a safety check to prevent the UTC/local swap bug
    if (checkOutTime.isUtc) {
      debugPrint(
        '[AttendanceRepository] WARNING: closeSession received UTC time, converting to local',
      );
      debugPrint('[AttendanceRepository]   Input (UTC): $checkOutTime');
      checkOutTime = checkOutTime.toLocal();
      debugPrint('[AttendanceRepository]   Converted (local): $checkOutTime');
    }

    final session = await _db.query(
      'attendance_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    if (session.isEmpty) return;

    final checkOutUtc = checkOutTime.toUtc();

    // Use UTC times for accurate duration calculation (handles DST)
    final checkInUtc = _parseStoredUtc(
      session.first['check_in_time_utc'] as String?,
      session.first['check_in_time'] as String,
    );

    // FIX: Validate session duration to prevent impossible durations
    // If duration is more than 24 hours, something went wrong
    final sessionDuration = checkOutUtc.difference(checkInUtc);
    if (sessionDuration.inHours >= 24) {
      debugPrint(
        '[AttendanceRepository] ⚠️ WARNING: Attempting to close session with ${sessionDuration.inHours}h duration!',
      );
      debugPrint(
        '[AttendanceRepository] Session $sessionId: $checkInUtc -> $checkOutUtc',
      );
      debugPrint(
        '[AttendanceRepository] This should have been split at midnight. Proceeding with caution...',
      );
    }

    // Calculate work time using segment-based approach
    // This prevents negative work time when breaks exceed work duration
    final breaks = await _db.query(
      'break_periods',
      where: 'session_id = ? AND break_end_time IS NOT NULL',
      whereArgs: [sessionId],
      orderBy: 'break_start_time ASC',
    );

    // Build timeline of break periods
    final breakPeriods = <({DateTime start, DateTime end})>[];
    for (var breakPeriod in breaks) {
      final breakStartUtc = _parseStoredUtc(
        breakPeriod['break_start_time_utc'] as String?,
        breakPeriod['break_start_time'] as String,
      );
      final breakEndUtc = _parseStoredUtc(
        breakPeriod['break_end_time_utc'] as String?,
        breakPeriod['break_end_time'] as String,
      );
      breakPeriods.add((start: breakStartUtc, end: breakEndUtc));
    }

    // Calculate work time as segments between breaks
    int netWorkSeconds = 0;
    DateTime currentPosition = checkInUtc;

    for (var breakPeriod in breakPeriods) {
      // Add work time from current position to break start
      if (breakPeriod.start.isAfter(currentPosition)) {
        netWorkSeconds += breakPeriod.start
            .difference(currentPosition)
            .inSeconds;
      }
      // Move position to break end
      if (breakPeriod.end.isAfter(currentPosition)) {
        currentPosition = breakPeriod.end;
      }
    }

    // Add remaining work time from last break end to checkout
    if (checkOutUtc.isAfter(currentPosition)) {
      netWorkSeconds += checkOutUtc.difference(currentPosition).inSeconds;
    }

    await _db.update(
      'attendance_sessions',
      {
        // CRITICAL FIX: Strictly enforce storage format
        // check_out_time -> ALWAYS Local (no 'Z')
        // check_out_time_utc -> ALWAYS UTC (with 'Z')
        'check_out_time': checkOutTime.toLocal().toIso8601String(),
        'check_out_time_utc': checkOutTime.toUtc().toIso8601String(),
        'check_out_source': source.name,
        'total_work_seconds': netWorkSeconds,
        'is_closed': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Helper to robustly parse UTC timestamps from DB
  /// Handles cases where 'Z' might be missing from UTC strings
  DateTime _parseStoredUtc(String? utcStr, String localStr) {
    if (utcStr != null) {
      try {
        // Try parsing valid formats first (including those with offsets like +00:00)
        final parsed = DateTime.parse(utcStr);
        if (parsed.isUtc) return parsed;

        // If parsed as Local (missing 'Z' or offset), treat as UTC by appending 'Z'
        return DateTime.parse('${utcStr}Z');
      } catch (e) {
        // If parsing fails (e.g. slight format mismatch), fallback to localStr
        debugPrint(
          '[AttendanceRepository] Warning: Failed to parse UTC string "$utcStr": $e',
        );
      }
    }
    // Fallback: Parse local string and convert to UTC
    return DateTime.parse(localStr).toUtc();
  }

  Future<void> updateSessionLastSeen(
    dynamic sessionId,
    DateTime lastSeenTime,
  ) async {
    await _db.update(
      'attendance_sessions',
      {
        'last_seen_time': lastSeenTime
            .toUtc()
            .toIso8601String(), // Ensure UTC storage
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    // debugPrint('[AttendanceRepository] Updated last_seen for $sessionId to $lastSeenTime');
  }

  Future<int> addRetroactiveBreak(
    int sessionId,
    DateTime breakStart,
    DateTime breakEnd, {
    String? note,
    int? userId,
  }) async {
    final breakStartUtc = breakStart.toUtc();
    final breakEndUtc = breakEnd.toUtc();
    final duration = breakEnd.difference(breakStart).inSeconds;

    final breakId = await _db.insert('break_periods', {
      'session_id': sessionId,
      'break_start_time': breakStart.toIso8601String(),
      'break_end_time': breakEnd.toIso8601String(),
      'break_start_time_utc': breakStartUtc.toIso8601String(),
      'break_end_time_utc': breakEndUtc.toIso8601String(),
      'duration_seconds': duration,
      'note': ?note,
      'user_id': ?userId,
    });

    await logEvent(
      'retroactive_break',
      EventSource.systemRecovery,
      metadata: {
        'session_id': sessionId,
        'duration_minutes': (duration / 60).round(),
        'reason': 'long_sleep',
        if (note != null) 'has_note': true,
      },
    );

    return breakId;
  }

  /// Add retroactive break that automatically splits across day boundaries
  /// This ensures breaks spanning midnight are properly recorded for each day
  Future<List<int>> addRetroactiveBreakWithDaySplit(
    DateTime breakStart,
    DateTime breakEnd, {
    String? note,
    int? userId,
  }) async {
    final breakIds = <int>[];

    // Get the start and end dates (ignoring time)
    final startDate = DateTime(
      breakStart.year,
      breakStart.month,
      breakStart.day,
    );
    final endDate = DateTime(breakEnd.year, breakEnd.month, breakEnd.day);

    // If break doesn't cross midnight, use simple add
    if (startDate == endDate) {
      // Find the session for this date
      final sessions = await getSessionsForDate(startDate);
      if (sessions.isEmpty) {
        throw Exception('No session found for date $startDate');
      }

      // Use the first (most recent) session for this date
      final sessionId = sessions.first['id'] as int;
      final breakId = await addRetroactiveBreak(
        sessionId,
        breakStart,
        breakEnd,
        note: note,
        userId: userId,
      );
      breakIds.add(breakId);
      return breakIds;
    }

    // Break spans multiple days - split it
    DateTime currentStart = breakStart;
    DateTime currentDate = startDate;

    while (currentDate.isBefore(endDate) || currentDate == endDate) {
      // Calculate end of current day
      final dayEnd = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
        23,
        59,
        59,
        999,
      );

      // Determine the end time for this day's break segment
      final segmentEnd = currentDate == endDate ? breakEnd : dayEnd;

      // Find session for this date
      final sessions = await getSessionsForDate(currentDate);

      if (sessions.isNotEmpty) {
        final sessionId = sessions.first['id'] as int;

        // Add break for this day's segment
        final breakId = await addRetroactiveBreak(
          sessionId,
          currentStart,
          segmentEnd,
          note: note != null ? '$note (Day ${currentDate.day})' : null,
          userId: userId,
        );
        breakIds.add(breakId);

        debugPrint(
          '[BREAK SPLIT] Added break segment for ${currentDate.toString().split(' ')[0]}: $currentStart -> $segmentEnd',
        );
      } else {
        debugPrint(
          '[BREAK SPLIT] Warning: No session found for date $currentDate, skipping break segment',
        );
      }

      // Move to next day
      currentDate = currentDate.add(const Duration(days: 1));
      currentStart = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
      );
    }

    await logEvent(
      'retroactive_break_split',
      EventSource.systemRecovery,
      metadata: {
        'break_start': breakStart.toIso8601String(),
        'break_end': breakEnd.toIso8601String(),
        'days_spanned': breakIds.length,
        'break_ids': breakIds,
        'note': ?note,
      },
    );

    return breakIds;
  }

  /// Add work during sleep that automatically splits across day boundaries
  /// This ensures work spans spanning midnight are properly recorded for each day
  /// AND creates sessions for days that don't have one (if user slept through them)
  Future<List<int>> addWorkDuringSleepWithDaySplit(
    DateTime sleepStart,
    DateTime wakeTime,
    String note, {
    int? userId,
  }) async {
    final workIds = <int>[];

    // Get the start and end dates (ignoring time)
    final startDate = DateTime(
      sleepStart.year,
      sleepStart.month,
      sleepStart.day,
    );
    final endDate = DateTime(wakeTime.year, wakeTime.month, wakeTime.day);

    // If work doesn't cross midnight, use simple add
    if (startDate == endDate) {
      // Find the session for this date
      final sessions = await getSessionsForDate(startDate);
      int sessionId;

      if (sessions.isEmpty) {
        // If no session exists for this day, create one!
        // This handles the case where computer was off/sleeping all day
        debugPrint(
          '[WORK SPLIT] No session found for $startDate, creating one...',
        );
        sessionId = await createSession(
          startDate.add(
            const Duration(hours: 9),
          ), // Default to 9AM or sleepStart if later?
          EventSource.systemRecovery,
          userId: userId,
        );
        // FIXME: createSession typically takes specific checkInTime.
        // Ideally we should use sleepStart as checkInTime if it's the first activity of the day?
        // But createSession implementation handles that.
        // Let's rely on finding a session or recovering one.
        // Actually, let's just use the current session ID strategy by passed context
        // But here we might not HAVE a current session if it was days ago.

        // Let's refine: If we are calling this, we probably have a session context.
        // But if we are splitting for a middle day (e.g. Saturday), we need to create a session.

        // For simplicity: If no session, create one starting at 00:00 (or sleepStart if it's first day)
        // and ending at 23:59 (or wakeTime if last day).
        // BUT `createSession` just opens it. We'll leave it open for now or close it immediately?
        // Since this is retroactive, we should probably close it too if it's in the past.

        // To be safe and reuse existing methods:
        // We will just try to find session. If not, log error or try to create.
        // For now, let's assume we can attach to existing session or one created by midnight recovery logic.
        // However, midnight recovery might not have run if app was closed.

        // Updated logic: ALWAYS ensure a session exists.
        sessionId = await createSession(
          sleepStart,
          EventSource.systemRecovery,
          userId: userId,
          // We link it to previous if possible? Complex.
          // Let's stick to simple: Create isolated session if none exists.
        );
        // Immediately close it? No, let the logic below add the work item.
        // But wait, `addWorkDuringSleep` just adds a record, it doesn't affect session duration directly
        // unless session is closed and we use it to calculate.

        // Actually, attendance_provider calls this.
      } else {
        sessionId = sessions.first['id'] as int;
      }

      final workId = await addWorkDuringSleep(
        sessionId,
        sleepStart,
        wakeTime,
        note,
        userId: userId,
      );
      workIds.add(workId);
      return workIds;
    }

    // Work spans multiple days - split it
    DateTime currentStart = sleepStart;
    DateTime currentDate = startDate;

    while (currentDate.isBefore(endDate) || currentDate == endDate) {
      // Calculate end of current day
      final dayEnd = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
        23,
        59,
        59,
        999,
      );

      // Determine the end time for this day's segment
      final segmentEnd = currentDate == endDate ? wakeTime : dayEnd;

      // Find session for this date
      final sessions = await getSessionsForDate(currentDate);
      int sessionId = -1;

      // Look for a session that actually starts on this day
      for (final session in sessions) {
        final checkIn = DateTime.parse(session['check_in_time'] as String);
        final sessionDate = DateTime(checkIn.year, checkIn.month, checkIn.day);
        if (sessionDate == currentDate) {
          sessionId = session['id'] as int;
          break;
        }
      }

      // If no session starts on this day, we must create one
      // (Even if we found sessions from previous days, we ignore them/close them implicitly by creating a new one?
      // Actually, if we have a previous day session open, we should probably close it to be clean,
      // but strictly speaking, creating a new session for today is the priority.)

      if (sessionId == -1) {
        debugPrint(
          '[WORK SPLIT] No session starts on ${currentDate.toString().split(' ')[0]}, creating one...',
        );

        // If there was an open session from yesterday (in 'sessions' list), close it!
        // This handles the "auto checkout end time" requirement
        for (final session in sessions) {
          final isClosed = (session['is_closed'] as int) == 1;
          if (!isClosed) {
            final checkIn = DateTime.parse(session['check_in_time'] as String);
            if (checkIn.isBefore(currentDate)) {
              debugPrint(
                '[WORK SPLIT] Closing overlapping previous session ${session['id']}',
              );
              // Close at end of yesterday (or effectively start of today minus 1ms?)
              final yesterdayEnd = DateTime(
                currentDate.year,
                currentDate.month,
                currentDate.day,
              ).subtract(const Duration(milliseconds: 1));
              await closeSession(
                session['id'] as int,
                yesterdayEnd,
                EventSource.autoMidnightTransition,
              );
            }
          }
        }

        // Create session starting at 00:00
        final sessionStart = DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
        );
        sessionId = await createSession(
          sessionStart,
          EventSource.systemRecovery,
          userId: userId,
        );
      }

      // Add work record for this day's segment
      final workId = await addWorkDuringSleep(
        sessionId,
        currentStart,
        segmentEnd,
        '$note (Day ${currentDate.day})',
        userId: userId,
      );
      workIds.add(workId);

      debugPrint(
        '[WORK SPLIT] Added work segment for ${currentDate.toString().split(' ')[0]}: $currentStart -> $segmentEnd (Session $sessionId)',
      );

      // Move to next day
      currentDate = currentDate.add(const Duration(days: 1));
      currentStart = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
      );
    }

    await logEvent(
      'work_during_sleep_split',
      EventSource.systemRecovery,
      metadata: {
        'sleep_start': sleepStart.toIso8601String(),
        'wake_time': wakeTime.toIso8601String(),
        'days_spanned': workIds.length,
        'work_ids': workIds,
        'note': note,
      },
    );

    return workIds;
  }

  Future<int> addWorkDuringSleep(
    int sessionId,
    DateTime sleepStart,
    DateTime wakeTime,
    String note, {
    int? userId,
  }) async {
    final sleepStartUtc = sleepStart.toUtc();
    final wakeTimeUtc = wakeTime.toUtc();
    final duration = wakeTime.difference(sleepStart).inSeconds;

    final workId = await _db.insert('work_during_sleep_periods', {
      'session_id': sessionId,
      'sleep_start_time': sleepStart.toIso8601String(),
      'wake_time': wakeTime.toIso8601String(),
      'sleep_start_time_utc': sleepStartUtc.toIso8601String(),
      'wake_time_utc': wakeTimeUtc.toIso8601String(),
      'duration_seconds': duration,
      'note': note,
      'user_id': ?userId,
    });

    await logEvent(
      'work_during_sleep',
      EventSource.manualUser,
      metadata: {
        'session_id': sessionId,
        'sleep_start': sleepStart.toIso8601String(),
        'wake_time': wakeTime.toIso8601String(),
        'duration_minutes': (duration / 60).round(),
        'note': note,
      },
    );

    return workId;
  }

  Future<void> closeCurrentSession(
    DateTime checkOutTime,
    EventSource source,
  ) async {
    final openSessions = await _db.query(
      'attendance_sessions',
      where: 'is_closed = ?',
      whereArgs: [0],
      orderBy: 'check_in_time DESC',
      limit: 1,
    );

    if (openSessions.isNotEmpty) {
      await closeSession(openSessions.first['id'] as int, checkOutTime, source);
    }
  }

  Future<Map<String, dynamic>?> getUnfinishedSession() async {
    // Build WHERE clause with user filtering if user is set
    String whereClause = 'is_closed = ?';
    List<dynamic> whereArgs = [0];

    if (_currentUserId != null) {
      whereClause += ' AND user_id = ?';
      whereArgs.add(_currentUserId);
    }

    final result = await _db.query(
      'attendance_sessions',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'check_in_time DESC',
      limit: 1,
    );

    return result.isNotEmpty ? result.first : null;
  }

  Future<int> startBreak(
    int sessionId,
    DateTime breakStartTime, {
    int? continuationOfBreakId,
    int? userId,
  }) async {
    final breakStartUtc = breakStartTime.toUtc();

    return await _db.insert('break_periods', {
      'session_id': sessionId,
      'break_start_time': breakStartTime.toIso8601String(),
      'break_start_time_utc': breakStartUtc.toIso8601String(),
      'continuation_of_break_id': continuationOfBreakId,
      'user_id': ?userId,
    });
  }

  Future<int?> endBreak(DateTime breakEndTime) async {
    final openBreaks = await _db.query(
      'break_periods',
      where: 'break_end_time IS NULL',
      orderBy: 'break_start_time DESC',
      limit: 1,
    );

    if (openBreaks.isEmpty) return null;

    final breakId = openBreaks.first['id'] as int;
    final breakEndUtc = breakEndTime.toUtc();

    // Use UTC times for accurate duration calculation
    final breakStartUtc = _parseStoredUtc(
      openBreaks.first['break_start_time_utc'] as String?,
      openBreaks.first['break_start_time'] as String,
    );

    final durationSeconds = breakEndUtc.difference(breakStartUtc).inSeconds;

    await _db.update(
      'break_periods',
      {
        'break_end_time': breakEndTime.toIso8601String(),
        'break_end_time_utc': breakEndUtc.toIso8601String(),
        'duration_seconds': durationSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [breakId],
    );

    return breakId;
  }

  Future<int?> getActiveBreakId(int sessionId) async {
    final result = await _db.query(
      'break_periods',
      where: 'session_id = ? AND break_end_time IS NULL',
      whereArgs: [sessionId],
      limit: 1,
    );

    return result.isNotEmpty ? result.first['id'] as int : null;
  }

  Future<void> completeBreak(int breakId, DateTime endTime) async {
    final breakEndUtc = endTime.toUtc();

    final breakData = await _db.query(
      'break_periods',
      where: 'id = ?',
      whereArgs: [breakId],
    );

    if (breakData.isEmpty) return;

    final breakStartUtc = _parseStoredUtc(
      breakData.first['break_start_time_utc'] as String?,
      breakData.first['break_start_time'] as String,
    );

    final durationSeconds = breakEndUtc.difference(breakStartUtc).inSeconds;

    await _db.update(
      'break_periods',
      {
        'break_end_time': endTime.toIso8601String(),
        'break_end_time_utc': breakEndUtc.toIso8601String(),
        'duration_seconds': durationSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [breakId],
    );
  }

  Future<List<BreakPeriod>> getSessionBreaks(dynamic sessionId) async {
    final breaks = await _db.query(
      'break_periods',
      where: 'session_id = ? AND break_end_time IS NOT NULL',
      whereArgs: [sessionId],
      orderBy: 'break_start_time ASC',
    );

    return breaks
        .map(
          (b) => BreakPeriod(
            startTime: _parseStoredUtc(
              b['break_start_time_utc'] as String?,
              b['break_start_time'] as String,
            ).toLocal(),
            endTime: _parseStoredUtc(
              b['break_end_time_utc'] as String?,
              b['break_end_time'] as String,
            ).toLocal(),
            note: b['note'] as String?,
          ),
        )
        .toList();
  }

  Future<void> logEvent(
    String eventType,
    EventSource source, {
    Map<String, dynamic>? metadata,
  }) async {
    await _db.insert('event_log', {
      'event_type': eventType,
      'event_source': source.name,
      'timestamp': DateTime.now().toIso8601String(),
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    });
  }

  Future<List<Map<String, dynamic>>> getTodaysSessions() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return await _db.query(
      'attendance_sessions',
      where: 'check_in_time >= ?',
      whereArgs: [startOfDay.toIso8601String()],
      orderBy: 'check_in_time DESC',
    );
  }

  /// FIX: Query sessions that overlap with the specified date
  /// Includes multi-day sessions that started yesterday but extend into today
  Future<List<Map<String, dynamic>>> getSessionsForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    final startUtc = startOfDay.toUtc();
    final endUtc = endOfDay.toUtc();

    // Build WHERE clause with user filtering if user is set
    String whereClause = '''
        (check_in_time_utc >= ? AND check_in_time_utc < ?) OR
        (check_in_time_utc < ? AND (check_out_time_utc IS NULL OR check_out_time_utc >= ?))
    ''';
    List<dynamic> whereArgs = [
      startUtc.toIso8601String(),
      endUtc.toIso8601String(),
      startUtc.toIso8601String(),
      startUtc.toIso8601String(),
    ];

    if (_currentUserId != null) {
      whereClause = '($whereClause) AND user_id = ?';
      whereArgs.add(_currentUserId);
    }

    // Query sessions that overlap with this day:
    // 1. Sessions starting today
    // 2. Multi-day sessions from previous days that are still active or ended today
    final results = await _db.rawQuery('''
      SELECT *
      FROM attendance_sessions
      WHERE $whereClause
      ORDER BY check_in_time_utc DESC
      ''', whereArgs);
    return results;
  }

  Future<List<Map<String, dynamic>>> getBreaksForSession(
    dynamic sessionId,
  ) async {
    return await _db.query(
      'break_periods',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'break_start_time ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getWorkDuringSleepForSession(
    dynamic sessionId,
  ) async {
    return await _db.query(
      'work_during_sleep_periods',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'sleep_start_time ASC',
    );
  }

  Future<void> recordSessionContinuation({
    required int originalSessionId,
    required int newSessionId,
    required String continuationType,
    required DateTime splitTimestamp,
    Map<String, dynamic>? metadata,
  }) async {
    await _db.insert('session_continuations', {
      'original_session_id': originalSessionId,
      'new_session_id': newSessionId,
      'continuation_type': continuationType,
      'split_timestamp_utc': splitTimestamp.toUtc().toIso8601String(),
      'split_timestamp_local': splitTimestamp.toIso8601String(),
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    });
  }

  Future<List<Map<String, dynamic>>> getContinuousSessionChain(
    int sessionId,
  ) async {
    final sessions = <Map<String, dynamic>>[];
    final visited = <int>{};

    // Find the root session (earliest in chain)
    int? currentId = sessionId;

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);

      final result = await _db.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [currentId],
      );

      if (result.isEmpty) break;

      final session = result.first;
      sessions.insert(0, session);

      // Move to previous session in chain
      currentId = session['continuation_of_session_id'] as int?;
    }

    // Now find forward continuations
    currentId = sessionId;
    visited.clear();

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);

      final result = await _db.query(
        'attendance_sessions',
        where: 'continuation_of_session_id = ?',
        whereArgs: [currentId],
      );

      if (result.isEmpty) break;

      final session = result.first;
      sessions.add(session);

      currentId = session['id'] as int?;
    }

    return sessions;
  }

  Future<Map<String, dynamic>> getDailySummary(DateTime date) async {
    final sessions = await getSessionsForDate(date);

    Duration totalWork = Duration.zero;
    Duration totalBreak = Duration.zero;
    int totalBreakCount = 0;

    for (var session in sessions) {
      final checkIn = DateTime.parse(session['check_in_time'] as String);
      final checkOut = session['check_out_time'] != null
          ? DateTime.parse(session['check_out_time'] as String)
          : DateTime.now();

      totalWork += checkOut.difference(checkIn);

      final breaks = await getBreaksForSession(session['id']);
      totalBreakCount += breaks.length;

      for (var breakPeriod in breaks) {
        if (breakPeriod['break_end_time'] != null) {
          final breakStart = DateTime.parse(
            breakPeriod['break_start_time'] as String,
          );
          final breakEnd = DateTime.parse(
            breakPeriod['break_end_time'] as String,
          );
          totalBreak += breakEnd.difference(breakStart);
        }
      }
    }

    return {
      'total_sessions': sessions.length,
      'total_work_seconds': totalWork.inSeconds,
      'total_break_seconds': totalBreak.inSeconds,
      'net_work_seconds': (totalWork - totalBreak).inSeconds,
      'total_breaks': totalBreakCount,
    };
  }

  Future<Duration> getPeriodClosedBreakDuration(
    DateTime start,
    DateTime end,
  ) async {
    String whereClause = '''s.is_closed = 1
      AND s.check_in_time >= ?
      AND s.check_in_time <= ?''';
    List<dynamic> whereArgs = [start.toIso8601String(), end.toIso8601String()];

    if (_currentUserId != null) {
      whereClause += ' AND s.user_id = ?';
      whereArgs.add(_currentUserId);
    }

    final breakResult = await _db.rawQuery('''
      SELECT SUM(b.duration_seconds) as total_break_seconds
      FROM break_periods b
      INNER JOIN attendance_sessions s ON b.session_id = s.id
      WHERE $whereClause
      ''', whereArgs);

    final totalBreakSeconds =
        (breakResult.first['total_break_seconds'] as int?) ?? 0;

    return Duration(seconds: totalBreakSeconds);
  }

  Future<Duration> getPeriodClosedWorkDuration(
    DateTime start,
    DateTime end,
  ) async {
    // Sum total_work_seconds for closed sessions in range
    // NOTE: total_work_seconds already contains NET work time (breaks are already subtracted)
    // This is calculated during session close using segment-based approach
    String whereClause = '''is_closed = 1
      AND check_in_time >= ?
      AND check_in_time <= ?''';
    List<dynamic> whereArgs = [start.toIso8601String(), end.toIso8601String()];

    if (_currentUserId != null) {
      whereClause += ' AND user_id = ?';
      whereArgs.add(_currentUserId);
    }

    final sessionResult = await _db.rawQuery('''
      SELECT SUM(total_work_seconds) as total_seconds
      FROM attendance_sessions
      WHERE $whereClause
      ''', whereArgs);

    final totalNetWorkSeconds =
        (sessionResult.first['total_seconds'] as int?) ?? 0;

    // Return the net work duration directly (breaks already subtracted during session close)
    return Duration(seconds: totalNetWorkSeconds);
  }

  Future<Duration> getTodayClosedBreakDuration() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);
    return getPeriodClosedBreakDuration(startOfDay, endOfDay);
  }

  Future<Duration> getTodayClosedWorkDuration() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);
    return getPeriodClosedWorkDuration(startOfDay, endOfDay);
  }

  Future<Duration> getMonthClosedWorkDuration() async {
    final today = DateTime.now();
    final startOfMonth = DateTime(today.year, today.month);
    final endOfMonth = DateTime(today.year, today.month + 1);
    // FIX: Use getPeriodWorkDuration to include active sessions
    return getPeriodWorkDuration(start: startOfMonth, end: endOfMonth);
  }

  Future<Duration> getAllTimeClosedWorkDuration() async {
    final startOfTime = DateTime(2020);
    final endOfTime = DateTime.now().add(const Duration(days: 1));
    return getPeriodClosedWorkDuration(startOfTime, endOfTime);
  }

  /// UNIFIED WORK DURATION CALCULATION (includes BOTH closed AND active sessions)
  /// This ensures dashboard and timesheet show the same values
  /// FIX: Addresses dashboard-timesheet desynchronization issue
  Future<Duration> getPeriodWorkDuration({
    required DateTime start,
    required DateTime end,
    bool includeActive = true,
  }) async {
    final startUtc = start.toUtc();
    final endUtc = end.toUtc();

    String whereClause = 'check_in_time_utc >= ? AND check_in_time_utc < ?';
    List<dynamic> whereArgs = [
      startUtc.toIso8601String(),
      endUtc.toIso8601String(),
    ];

    if (_currentUserId != null) {
      whereClause += ' AND user_id = ?';
      whereArgs.add(_currentUserId);
    }

    // Query ALL sessions in range (closed + active)
    final sessions = await _db.rawQuery('''
      SELECT
        id,
        check_in_time,
        check_in_time_utc,
        check_out_time,
        check_out_time_utc,
        is_closed
      FROM attendance_sessions
      WHERE $whereClause
      ORDER BY check_in_time_utc ASC
      ''', whereArgs);

    Duration totalWork = Duration.zero;

    for (final session in sessions) {
      final sessionId = session['id'] as int;
      final isClosed = (session['is_closed'] as int) == 1;

      // Skip active sessions if not included
      if (!isClosed && !includeActive) continue;

      final checkInUtc = _parseStoredUtc(
        session['check_in_time_utc'] as String?,
        session['check_in_time'] as String,
      );
      // NOTE: Query above selects 'check_in_time_utc', but maybe not 'check_in_time'.
      // Actually line 1005 selects id, check_in_time_utc, check_out_time_utc, is_closed.
      // It MISSES check_in_time!
      // I should update the query to select check_in_time too.

      DateTime checkOutUtc;

      if (isClosed && session['check_out_time_utc'] != null) {
        checkOutUtc = _parseStoredUtc(
          session['check_out_time_utc'] as String?,
          '', // We don't have local time, but if UTC exists we are good. If not, we risk crash.
          // But isClosed=1 usually has UTC.
          // Let's rely on UTC column presence here or unsafe parse?
          // Actually _parseStoredUtc handles null 1st arg by using 2nd.
          // If 1st arg is present, 2nd arg is ignored.
        );
      } else {
        // Active session: use current time
        checkOutUtc = DateTime.now().toUtc();
      }

      // Calculate work time using segment-based approach
      final breaks = await _db.rawQuery(
        '''
        SELECT break_start_time, break_start_time_utc, break_end_time, break_end_time_utc
        FROM break_periods
        WHERE session_id = ?
        ORDER BY break_start_time ASC
        ''',
        [sessionId],
      );

      // Build timeline of break periods
      final breakPeriods = <({DateTime start, DateTime end})>[];
      for (final breakPeriod in breaks) {
        final breakStartUtc = _parseStoredUtc(
          breakPeriod['break_start_time_utc'] as String?,
          breakPeriod['break_start_time'] as String,
        );
        DateTime breakEndUtc;

        if (breakPeriod['break_end_time_utc'] != null) {
          breakEndUtc = _parseStoredUtc(
            breakPeriod['break_end_time_utc'] as String?,
            breakPeriod['break_end_time'] as String,
          );
        } else if (breakPeriod['break_end_time'] != null) {
          // Closed break but no UTC time (older record)
          breakEndUtc = _parseStoredUtc(
            null,
            breakPeriod['break_end_time'] as String,
          );
        } else {
          // Active break: use current time
          breakEndUtc = DateTime.now().toUtc();
        }

        breakPeriods.add((start: breakStartUtc, end: breakEndUtc));
      }

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

      totalWork += sessionWorkTime;
    }

    return totalWork;
  }

  /// Today's work duration (includes active session)
  /// FIX: Dashboard will now match timesheet
  Future<Duration> getTodayWorkDuration() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getPeriodWorkDuration(start: startOfDay, end: endOfDay);
  }

  /// Today's break duration (includes active break)
  /// FIX: Dashboard will now match timesheet
  Future<Duration> getTodayBreakDuration() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final startUtc = startOfDay.toUtc();
    final endUtc = endOfDay.toUtc();

    String whereClause = 's.check_in_time_utc >= ? AND s.check_in_time_utc < ?';
    List<dynamic> whereArgs = [
      startUtc.toIso8601String(),
      endUtc.toIso8601String(),
    ];

    if (_currentUserId != null) {
      whereClause += ' AND s.user_id = ?';
      whereArgs.add(_currentUserId);
    }

    final breaks = await _db.rawQuery('''
      SELECT b.break_start_time, b.break_start_time_utc, b.break_end_time, b.break_end_time_utc
      FROM break_periods b
      INNER JOIN attendance_sessions s ON b.session_id = s.id
      WHERE $whereClause
      ORDER BY b.break_start_time ASC
      ''', whereArgs);

    Duration totalBreak = Duration.zero;

    for (final breakPeriod in breaks) {
      // Handle robust parsing
      final breakStartUtc = _parseStoredUtc(
        breakPeriod['break_start_time_utc'] as String?,
        breakPeriod['break_start_time'] as String,
      );
      DateTime breakEndUtc;

      if (breakPeriod['break_end_time_utc'] != null) {
        breakEndUtc = _parseStoredUtc(
          breakPeriod['break_end_time_utc'] as String?,
          breakPeriod['break_end_time'] as String,
        );
      } else if (breakPeriod['break_end_time'] != null) {
        // Closed break but no UTC time (older record)
        breakEndUtc = _parseStoredUtc(
          null,
          breakPeriod['break_end_time'] as String,
        );
      } else {
        // Active break: use current time
        breakEndUtc = DateTime.now().toUtc();
      }

      totalBreak += breakEndUtc.difference(breakStartUtc);
    }

    return totalBreak;
  }

  /// This month's break duration (includes active break)
  Future<Duration> getMonthBreakDuration() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final endOfMonth = DateTime(now.year, now.month + 1);

    final startUtc = startOfMonth.toUtc();
    final endUtc = endOfMonth.toUtc();

    String whereClause = 's.check_in_time_utc >= ? AND s.check_in_time_utc < ?';
    List<dynamic> whereArgs = [
      startUtc.toIso8601String(),
      endUtc.toIso8601String(),
    ];

    if (_currentUserId != null) {
      whereClause += ' AND s.user_id = ?';
      whereArgs.add(_currentUserId);
    }

    final breaks = await _db.rawQuery('''
      SELECT b.break_start_time, b.break_start_time_utc, b.break_end_time, b.break_end_time_utc
      FROM break_periods b
      INNER JOIN attendance_sessions s ON b.session_id = s.id
      WHERE $whereClause
      ORDER BY b.break_start_time ASC
      ''', whereArgs);

    Duration totalBreak = Duration.zero;

    for (final breakPeriod in breaks) {
      // Handle robust parsing
      final breakStartUtc = _parseStoredUtc(
        breakPeriod['break_start_time_utc'] as String?,
        breakPeriod['break_start_time'] as String,
      );
      DateTime breakEndUtc;

      if (breakPeriod['break_end_time_utc'] != null) {
        breakEndUtc = _parseStoredUtc(
          breakPeriod['break_end_time_utc'] as String?,
          breakPeriod['break_end_time'] as String,
        );
      } else if (breakPeriod['break_end_time'] != null) {
        // Closed break but no UTC time
        breakEndUtc = _parseStoredUtc(
          null,
          breakPeriod['break_end_time'] as String,
        );
      } else {
        // Active break: use current time
        breakEndUtc = DateTime.now().toUtc();
      }

      totalBreak += breakEndUtc.difference(breakStartUtc);
    }

    return totalBreak;
  }

  Future<void> clearAllData() async {
    await _db.delete('attendance_sessions');
    await _db.delete('break_periods');
    await _db.delete('session_continuations');
    await _db.delete('event_log');
  }

  Future<int> getTotalSessionsCount() async {
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (_currentUserId != null) {
      whereClause = 'user_id = ?';
      whereArgs.add(_currentUserId);
    }

    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM attendance_sessions WHERE $whereClause',
      whereArgs,
    );
    if (result.isNotEmpty) {
      return (result.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  /// Get complete timeline data for a single day
  /// Returns work blocks, break blocks, and not-working blocks
  Future<Map<String, dynamic>> getDayTimelineData(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    // Get all sessions for this day
    final sessions = await getSessionsForDate(date);

    final workBlocks = <Map<String, dynamic>>[];
    final breakBlocks = <Map<String, dynamic>>[];

    for (var sessionData in sessions) {
      final sessionId = sessionData['id'] as int;

      // CRITICAL FIX: Use UTC times for robust local conversion
      // This matches AppActivity and DailyTimeSheet parsing logic
      final checkInTime = _parseStoredUtc(
        sessionData['check_in_time_utc'] as String?,
        sessionData['check_in_time'] as String,
      ).toLocal();

      final checkOutTime = sessionData['check_out_time'] != null
          ? _parseStoredUtc(
              sessionData['check_out_time_utc'] as String?,
              sessionData['check_out_time'] as String,
            ).toLocal()
          : null;

      // Clamp session times to the day boundaries
      final sessionStart = checkInTime.isBefore(startOfDay)
          ? startOfDay
          : checkInTime;
      final sessionEnd = checkOutTime == null
          ? DateTime.now()
          : (checkOutTime.isAfter(endOfDay) ? endOfDay : checkOutTime);

      // Add work block for this session
      workBlocks.add({
        'session_id': sessionId,
        'start_time': sessionStart,
        'end_time': sessionEnd,
        'original_start_time': checkInTime,
        'original_end_time': checkOutTime,
        'block_type': 'work',
        'note':
            sessionData['continuation_reason']
                as String?, // Pass note/reason if available
      });

      // Get breaks for this session
      final breaksData = await getBreaksForSession(sessionId);
      for (var breakData in breaksData) {
        // Use UTC times for breaks too
        final breakStart = _parseStoredUtc(
          breakData['break_start_time_utc'] as String?,
          breakData['break_start_time'] as String,
        ).toLocal();

        final breakEnd = breakData['break_end_time'] != null
            ? _parseStoredUtc(
                breakData['break_end_time_utc'] as String?,
                breakData['break_end_time'] as String,
              ).toLocal()
            : DateTime.now();

        final note = breakData['note'] as String?;

        // Only include breaks that fall within the day
        if (breakStart.isBefore(endOfDay) && breakEnd.isAfter(startOfDay)) {
          final clampedStart = breakStart.isBefore(startOfDay)
              ? startOfDay
              : breakStart;
          final clampedEnd = breakEnd.isAfter(endOfDay) ? endOfDay : breakEnd;

          breakBlocks.add({
            'start_time': clampedStart,
            'end_time': clampedEnd,
            'block_type': 'break',
            'note': note,
          });
        }
      }

      // Get work-during-sleep periods for this session
      final workSleepData = await getWorkDuringSleepForSession(sessionId);
      for (var workSleep in workSleepData) {
        // Use UTC times for sleep periods
        final sleepStart = _parseStoredUtc(
          workSleep['sleep_start_time_utc'] as String?,
          workSleep['sleep_start_time'] as String,
        ).toLocal();

        final wakeTime = _parseStoredUtc(
          workSleep['wake_time_utc'] as String?,
          workSleep['wake_time'] as String,
        ).toLocal();

        final note = workSleep['note'] as String;

        // Only include work-during-sleep periods that fall within the day
        if (sleepStart.isBefore(endOfDay) && wakeTime.isAfter(startOfDay)) {
          final clampedStart = sleepStart.isBefore(startOfDay)
              ? startOfDay
              : sleepStart;
          final clampedEnd = wakeTime.isAfter(endOfDay) ? endOfDay : wakeTime;

          workBlocks.add({
            'session_id': sessionId,
            'start_time': clampedStart,
            'end_time': clampedEnd,
            'block_type': 'work_during_sleep',
            'note': note,
          });
        }
      }
    }

    return {
      'date': date,
      'work_blocks': workBlocks,
      'break_blocks': breakBlocks,
      'day_start': startOfDay,
      'day_end': endOfDay,
    };
  }

  Future<List<DailyTimeSheet>> getMonthlyDailyTimeSheets(
    int year,
    int month, {
    bool refresh = false,
  }) async {
    debugPrint(
      '[DESKTOP] Fetching monthly timesheet for $year/$month (current user: $_currentUserId)',
    );

    final endOfMonth = DateTime(year, month + 1, 0); // Last day of month
    final daysInMonth = endOfMonth.day;

    final List<DailyTimeSheet> timesheets = [];
    int totalSessions = 0;

    // Naive implementation for local DB
    for (int i = 0; i < daysInMonth; i++) {
      final date = DateTime(year, month, 1 + i);
      final sessions = await getSessionsForDate(date);
      totalSessions += sessions.length;

      final List<AttendanceSession> attendanceSessions = [];
      for (var sessionMap in sessions) {
        final sessionId = sessionMap['id'];
        final breaksData = await getBreaksForSession(sessionId);
        final workSleep = await getWorkDuringSleepForSession(sessionId);

        // Manually map breaks to BreakPeriod objects
        // CRITICAL: Use UTC column + .toLocal() for correct timezone display
        final breaks = breaksData
            .map(
              (b) => BreakPeriod(
                startTime: _parseStoredUtc(
                  b['break_start_time_utc'] as String?,
                  b['break_start_time'] as String,
                ).toLocal(),
                endTime: b['break_end_time'] != null
                    ? _parseStoredUtc(
                        b['break_end_time_utc'] as String?,
                        b['break_end_time'] as String,
                      ).toLocal()
                    : null,
                note: b['note'] as String?,
              ),
            )
            .toList();

        final sleepPeriods = workSleep.map((w) {
          DateTime sleepStartTime, wakeTime;

          // Use UTC times if available, otherwise fall back to local times
          if (w['sleep_start_time_utc'] != null) {
            sleepStartTime = DateTime.parse(
              w['sleep_start_time_utc'] as String,
            ).toLocal();
          } else {
            sleepStartTime = DateTime.parse(w['sleep_start_time'] as String);
          }

          if (w['wake_time_utc'] != null) {
            wakeTime = DateTime.parse(w['wake_time_utc'] as String).toLocal();
          } else {
            wakeTime = DateTime.parse(w['wake_time'] as String);
          }

          return WorkDuringSleepPeriod(
            sleepStartTime: sleepStartTime,
            wakeTime: wakeTime,
            note: w['note'] as String,
          );
        }).toList();

        attendanceSessions.add(
          AttendanceSession.fromMap(sessionMap, breaks, sleepPeriods),
        );
      }

      if (attendanceSessions.isNotEmpty) {
        timesheets.add(
          DailyTimeSheet(date: date, sessions: attendanceSessions),
        );
      }
    }

    debugPrint(
      '[DESKTOP] Found $totalSessions total sessions across ${timesheets.length} days for $year/$month',
    );
    return timesheets;
  }

  Future<List<Map<String, int>>> getAvailableMonths() async {
    // Naive implementation for local DB
    // Query distinct year/month from attendance_sessions
    final result = await _db.rawQuery('''
      SELECT DISTINCT 
        strftime('%Y', check_in_time) as year,
        strftime('%m', check_in_time) as month
      FROM attendance_sessions
      ORDER BY year DESC, month DESC
    ''');

    return result.map((row) {
      return {
        'year': int.parse(row['year'] as String),
        'month': int.parse(row['month'] as String),
      };
    }).toList();
  }
}
