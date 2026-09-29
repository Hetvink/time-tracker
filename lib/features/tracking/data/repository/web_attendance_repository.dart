import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:time_trak/core/repositories/session_repository.dart';
import 'package:time_trak/infrastructure/supabase/repositories/supabase_session_repository.dart';
import '../models/attendance_state.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';
import 'attendance_repository.dart';

/// Web-compatible wrapper for AttendanceRepository
/// Extends AttendanceRepository to work with AttendanceProvider
/// Uses Supabase for data access instead of local SQLite
///
/// Note: Web platform is READ-ONLY for viewing data synced from desktop
class WebAttendanceRepository extends AttendanceRepository {
  final SessionRepository _sessionRepo;
  static Database? _mockDb;

  // Pass a mock in-memory database to parent (never actually used on web)
  WebAttendanceRepository(this._sessionRepo) : super(_getMockDatabase());

  // Get or create a mock in-memory database (web doesn't actually use it)
  static Database _getMockDatabase() {
    // Return a dummy database that satisfies the type requirement
    // This will never be used on web since all methods are overridden
    _mockDb ??= _MockDatabase();
    return _mockDb!;
  }

  /// Create session - NOT SUPPORTED on web
  @override
  Future<int> createSession(
    DateTime checkInTime,
    EventSource source, {
    int? userId,
    int? continuationOfSessionId,
    String? continuationReason,
  }) async {
    throw UnsupportedError(
      'Creating sessions from web is not supported. Use desktop app for tracking.',
    );
  }

  /// Close session - NOT SUPPORTED on web
  @override
  Future<void> closeSession(
    int sessionId,
    DateTime checkOutTime,
    EventSource source,
  ) async {
    throw UnsupportedError(
      'Closing sessions from web is not supported. Use desktop app for tracking.',
    );
  }

  /// Get active session - returns null on web (read-only)
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      final session = await _sessionRepo.getActiveSession();
      if (session == null) return null;

      // Convert SessionModel to legacy map format
      return {
        'id': session.id,
        'check_in_time': session.checkInTime.toIso8601String(),
        'check_in_source': session.checkInSource.name,
        'is_closed': session.isClosed ? 1 : 0,
      };
    } catch (e) {
      debugPrint('[WEB] Error getting active session: $e');
      return null;
    }
  }

  /// Get timesheet for a specific date
  Future<DailyTimeSheet> getTimesheetForDate(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Use getSessionsWithRelations to get sessions with breaks and activities
      // Cast to SupabaseSessionRepository to access this method
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;
      final sessionsWithRelations = await supabaseRepo.getSessionsWithRelations(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      final sessions = sessionsWithRelations
          .where((sessionMap) {
            // Filter out closed sessions with zero work time
            // These are phantom sessions that shouldn't be displayed
            final isClosed = sessionMap['is_closed'] is bool
                ? sessionMap['is_closed'] as bool
                : (sessionMap['is_closed'] as int) == 1;
            final totalWorkSeconds =
                (sessionMap['total_work_seconds'] as int?) ?? 0;

            // Keep active sessions and sessions with actual work time
            return !isClosed || totalWorkSeconds > 0;
          })
          .map((sessionMap) {
            // Parse breaks
            final breaksData =
                sessionMap['break_periods'] as List<dynamic>? ?? [];
            final breaks = breaksData.map((b) {
              DateTime startTime;
              if (b['break_start_time_utc'] != null) {
                startTime = DateTime.parse(
                  b['break_start_time_utc'] as String,
                ).toLocal();
              } else {
                startTime = DateTime.parse(b['break_start_time'] as String);
              }

              DateTime? endTime;
              if (b['break_end_time_utc'] != null) {
                endTime = DateTime.parse(
                  b['break_end_time_utc'] as String,
                ).toLocal();
              } else if (b['break_end_time'] != null) {
                endTime = DateTime.parse(b['break_end_time'] as String);
              }

              return BreakPeriod(
                startTime: startTime,
                endTime: endTime,
                note: b['note'] as String?,
              );
            }).toList();

            // Parse work during sleep
            final sleepData =
                sessionMap['work_during_sleep_periods'] as List<dynamic>? ?? [];
            final sleepPeriods = sleepData.map((s) {
              DateTime sleepStartTime, wakeTime;

              // Use UTC times if available, otherwise fall back to local times
              if (s['sleep_start_time_utc'] != null) {
                sleepStartTime = DateTime.parse(
                  s['sleep_start_time_utc'] as String,
                ).toLocal();
              } else {
                sleepStartTime = DateTime.parse(
                  s['sleep_start_time'] as String,
                );
              }

              if (s['wake_time_utc'] != null) {
                wakeTime = DateTime.parse(
                  s['wake_time_utc'] as String,
                ).toLocal();
              } else {
                wakeTime = DateTime.parse(s['wake_time'] as String);
              }

              return WorkDuringSleepPeriod(
                sleepStartTime: sleepStartTime,
                wakeTime: wakeTime,
                note: s['note'] as String? ?? '',
              );
            }).toList();

            return AttendanceSession.fromMap(sessionMap, breaks, sleepPeriods);
          })
          .toList();

      return DailyTimeSheet(date: date, sessions: sessions);
    } catch (e) {
      debugPrint('[WEB] Error getting timesheet: $e');
      return DailyTimeSheet.empty(date);
    }
  }

  /// Get closed sessions duration for a date range
  Future<Duration> getClosedSessionsDuration({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      return await _sessionRepo.getTotalWorkDuration(
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      debugPrint('[WEB] Error getting closed sessions duration: $e');
      return Duration.zero;
    }
  }

  /// Break management - NOT SUPPORTED on web
  @override
  Future<int> startBreak(
    int sessionId,
    DateTime breakStartTime, {
    int? continuationOfBreakId,
    int? userId,
  }) async {
    throw UnsupportedError(
      'Break management from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<int?> endBreak(DateTime breakEndTime) async {
    throw UnsupportedError(
      'Break management from web is not supported. Use desktop app.',
    );
  }

  Future<Map<String, dynamic>?> getActiveBreak(int sessionId) async {
    // Web doesn't support active breaks
    return null;
  }

  /// Get active break ID - NOT SUPPORTED on web
  @override
  Future<int?> getActiveBreakId(dynamic sessionId) async {
    // Web doesn't support active break management
    // Return null to indicate no active breaks
    return null;
  }

  /// Complete break - NOT SUPPORTED on web
  @override
  Future<void> completeBreak(dynamic breakId, DateTime endTime) async {
    // Web doesn't support break management - no-op
    // This prevents errors during recovery processes
    debugPrint('[WEB] completeBreak called but not supported on web platform');
    return;
  }

  @override
  Future<void> updateSessionLastSeen(
    dynamic sessionId,
    DateTime lastSeenTime,
  ) async {
    try {
      // On web, sessionId should be a UUID String
      if (sessionId is String) {
        // Ensure we send UTC to Supabase to prevent time shift
        await _sessionRepo.updateSessionLastSeen(
          sessionId,
          lastSeenTime.toUtc(),
        );
        debugPrint(
          '[WEB] Updated last_seen_time for session $sessionId to $lastSeenTime',
        );
      } else {
        debugPrint(
          '[WEB] Warning: updateSessionLastSeen called with non-String ID: $sessionId (Type: ${sessionId.runtimeType})',
        );
      }
    } catch (e) {
      debugPrint('[WEB] Error updating session last seen: $e');
    }
  }

  /// Session statistics
  Future<Map<String, dynamic>> getSessionStatistics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Use getSessionsWithRelations to get sessions with breaks
      // Cast to SupabaseSessionRepository to access this method
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;
      final allSessions = await supabaseRepo.getSessionsWithRelations(
        startDate: startDate,
        endDate: endDate,
      );

      // Filter out closed sessions with zero work time
      final sessions = allSessions.where((sessionMap) {
        final isClosed = sessionMap['is_closed'] is bool
            ? sessionMap['is_closed'] as bool
            : (sessionMap['is_closed'] as int) == 1;
        final totalWorkSeconds =
            (sessionMap['total_work_seconds'] as int?) ?? 0;
        return !isClosed || totalWorkSeconds > 0;
      }).toList();

      int totalWorkSeconds = 0;
      int totalBreakSeconds = 0;
      int sessionCount = sessions.length;

      for (final sessionMap in sessions) {
        // Work seconds
        totalWorkSeconds += (sessionMap['total_work_seconds'] as int?) ?? 0;

        // Break seconds
        final breaksData = sessionMap['break_periods'] as List<dynamic>? ?? [];
        for (final breakData in breaksData) {
          final start = DateTime.parse(breakData['break_start_time'] as String);
          if (breakData['break_end_time'] != null) {
            final end = DateTime.parse(breakData['break_end_time'] as String);
            totalBreakSeconds += end.difference(start).inSeconds;
          }
        }
      }

      return {
        'total_work_seconds': totalWorkSeconds,
        'total_break_seconds': totalBreakSeconds,
        'session_count': sessionCount,
        'average_work_seconds': sessionCount > 0
            ? totalWorkSeconds ~/ sessionCount
            : 0,
      };
    } catch (e) {
      debugPrint('[WEB] Error getting session statistics: $e');
      return {
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'session_count': 0,
        'average_work_seconds': 0,
      };
    }
  }

  /// Get unfinished session - returns null on web (read-only)
  @override
  Future<Map<String, dynamic>?> getUnfinishedSession() async {
    try {
      final session = await _sessionRepo.getActiveSession();
      if (session == null) return null;

      return {
        'id': session.id,
        'check_in_time': session.checkInTime.toIso8601String(),
        'check_in_source': session.checkInSource.name,
        'is_closed': session.isClosed ? 1 : 0,
      };
    } catch (e) {
      debugPrint('[WEB] Error getting unfinished session: $e');
      return null;
    }
  }

  /// Get sessions for a specific date
  @override
  Future<List<Map<String, dynamic>>> getSessionsForDate(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final sessions = await _sessionRepo.getSessionsInRange(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      return sessions
          .map(
            (session) => {
              'id': session.id,
              'check_in_time': session.checkInTime.toIso8601String(),
              'check_out_time': session.checkOutTime?.toIso8601String(),
              'total_work_seconds': session.totalWorkSeconds ?? 0,
              'is_closed': session.isClosed ? 1 : 0,
              'check_in_source': session.checkInSource.name,
              'check_out_source': session.checkOutSource?.name,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('[WEB] Error getting sessions for date: $e');
      return [];
    }
  }

  /// Get breaks for session
  @override
  Future<List<Map<String, dynamic>>> getBreaksForSession(
    dynamic sessionId,
  ) async {
    try {
      final breaks = await _sessionRepo.getBreaksForSession(
        sessionId.toString(),
      );
      return breaks
          .map(
            (b) => {
              'break_start_time': b.startTime.toIso8601String(),
              'break_end_time': b.endTime?.toIso8601String(),
              'note': b.note,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('[WEB] Error getting breaks for session: $e');
      return [];
    }
  }

  /// Get session breaks as BreakPeriod objects
  @override
  Future<List<BreakPeriod>> getSessionBreaks(dynamic sessionId) async {
    try {
      return await _sessionRepo.getBreaksForSession(sessionId.toString());
    } catch (e) {
      debugPrint('[WEB] Error getting session breaks: $e');
      return [];
    }
  }

  /// Get work during sleep for session
  @override
  Future<List<Map<String, dynamic>>> getWorkDuringSleepForSession(
    dynamic sessionId,
  ) async {
    try {
      final periods = await _sessionRepo.getWorkDuringSleepForSession(
        sessionId.toString(),
      );
      return periods
          .map(
            (p) => {
              'sleep_start_time': p.sleepStartTime.toIso8601String(),
              'wake_time': p.wakeTime.toIso8601String(),
              'note': p.note,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('[WEB] Error getting work during sleep for session: $e');
      return [];
    }
  }

  /// Get period work duration
  @override
  Future<Duration> getPeriodWorkDuration({
    required DateTime start,
    required DateTime end,
    bool includeActive = true,
  }) async {
    try {
      return await _sessionRepo.getTotalWorkDuration(
        startDate: start,
        endDate: end,
      );
    } catch (e) {
      debugPrint('[WEB] Error getting period work duration: $e');
      return Duration.zero;
    }
  }

  /// Get complete timeline data for a single day
  /// Overrides parent to fetch from Supabase instead of local database
  @override
  Future<Map<String, dynamic>> getDayTimelineData(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
        59,
        999,
      );

      // Use getSessionsWithRelations to get sessions with breaks and activities
      // Cast to SupabaseSessionRepository to access this method
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;
      final sessionsWithRelations = await supabaseRepo.getSessionsWithRelations(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      final workBlocks = <Map<String, dynamic>>[];
      final breakBlocks = <Map<String, dynamic>>[];

      for (var sessionData in sessionsWithRelations) {
        try {
          final sessionId = sessionData['id']; // UUID string from Supabase

          DateTime checkInTime;
          // CRITICAL FIX: Always try to use UTC time first and convert to local
          // This ensures we get the correct time regardless of browser timezone
          if (sessionData['check_in_time_utc'] != null) {
            checkInTime = DateTime.parse(
              sessionData['check_in_time_utc'] as String,
            ).toLocal();
          } else if (sessionData['check_in_time'] != null) {
            checkInTime = DateTime.parse(
              sessionData['check_in_time'] as String,
            );
          } else {
            debugPrint(
              '[WEB] Warning: Session $sessionId missing check_in_time',
            );
            continue; // Skip invalid session
          }

          DateTime? checkOutTime;
          if (sessionData['check_out_time_utc'] != null) {
            checkOutTime = DateTime.parse(
              sessionData['check_out_time_utc'] as String,
            ).toLocal();
          } else if (sessionData['check_out_time'] != null) {
            checkOutTime = DateTime.parse(
              sessionData['check_out_time'] as String,
            );
          }

          // Clamp session times to the day boundaries
          final sessionStart = checkInTime.isBefore(startOfDay)
              ? startOfDay
              : checkInTime;

          final sessionEndUnclamped = checkOutTime ?? DateTime.now();

          final sessionEnd = sessionEndUnclamped.isAfter(endOfDay)
              ? endOfDay
              : sessionEndUnclamped;

          // Add work block for this session
          workBlocks.add({
            'session_id': sessionId,
            'start_time': sessionStart,
            'end_time': sessionEnd,
            'original_start_time': checkInTime,
            'original_end_time': checkOutTime,
            'block_type': 'work',
          });

          // Get breaks from the session data
          final breaks = sessionData['break_periods'] as List<dynamic>? ?? [];
          for (var breakData in breaks) {
            try {
              DateTime breakStart;
              // CRITICAL FIX: Use UTC time for breaks
              if (breakData['break_start_time_utc'] != null) {
                breakStart = DateTime.parse(
                  breakData['break_start_time_utc'] as String,
                ).toLocal();
              } else if (breakData['break_start_time'] != null) {
                breakStart = DateTime.parse(
                  breakData['break_start_time'] as String,
                );
              } else {
                continue;
              }

              DateTime breakEnd;
              if (breakData['break_end_time_utc'] != null) {
                breakEnd = DateTime.parse(
                  breakData['break_end_time_utc'] as String,
                ).toLocal();
              } else if (breakData['break_end_time'] != null) {
                breakEnd = DateTime.parse(
                  breakData['break_end_time'] as String,
                );
              } else {
                // If break is active, clamp to now
                breakEnd = DateTime.now();
              }

              final note = breakData['note'] as String?;

              // Only include breaks that fall within the day
              if (breakStart.isBefore(endOfDay) &&
                  breakEnd.isAfter(startOfDay)) {
                final clampedStart = breakStart.isBefore(startOfDay)
                    ? startOfDay
                    : breakStart;
                final clampedEnd = breakEnd.isAfter(endOfDay)
                    ? endOfDay
                    : breakEnd;

                breakBlocks.add({
                  'start_time': clampedStart,
                  'end_time': clampedEnd,
                  'block_type': 'break',
                  'note': note,
                });
              }
            } catch (e) {
              debugPrint('[WEB] Error parsing break in session $sessionId: $e');
            }
          }

          // Get work-during-sleep periods
          final workSleepPeriods =
              sessionData['work_during_sleep_periods'] as List<dynamic>? ?? [];
          for (var workSleep in workSleepPeriods) {
            try {
              DateTime sleepStart;
              // CRITICAL FIX: Use UTC time for sleep periods
              if (workSleep['sleep_start_time_utc'] != null) {
                sleepStart = DateTime.parse(
                  workSleep['sleep_start_time_utc'] as String,
                ).toLocal();
              } else if (workSleep['sleep_start_time'] != null) {
                sleepStart = DateTime.parse(
                  workSleep['sleep_start_time'] as String,
                );
              } else {
                continue;
              }

              DateTime wakeTime;
              if (workSleep['wake_time_utc'] != null) {
                wakeTime = DateTime.parse(
                  workSleep['wake_time_utc'] as String,
                ).toLocal();
              } else if (workSleep['wake_time'] != null) {
                wakeTime = DateTime.parse(workSleep['wake_time'] as String);
              } else {
                wakeTime = DateTime.now();
              }

              final note = workSleep['note'] as String? ?? '';

              // Only include work-during-sleep periods that fall within the day
              if (sleepStart.isBefore(endOfDay) &&
                  wakeTime.isAfter(startOfDay)) {
                final clampedStart = sleepStart.isBefore(startOfDay)
                    ? startOfDay
                    : sleepStart;
                final clampedEnd = wakeTime.isAfter(endOfDay)
                    ? endOfDay
                    : wakeTime;

                workBlocks.add({
                  'session_id': sessionId,
                  'start_time': clampedStart,
                  'end_time': clampedEnd,
                  'block_type': 'work_during_sleep',
                  'note': note,
                });
              }
            } catch (e) {
              debugPrint(
                '[WEB] Error parsing work-sleep in session $sessionId: $e',
              );
            }
          }
        } catch (e) {
          debugPrint('[WEB] Error parsing session data: $e');
          // Continue to next session instead of failing entire request
        }
      }

      return {
        'date': date,
        'work_blocks': workBlocks,
        'break_blocks': breakBlocks,
        'day_start': startOfDay,
        'day_end': endOfDay,
      };
    } catch (e) {
      debugPrint('[WEB] Error getting day timeline data: $e');
      // Return empty timeline data
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
        59,
        999,
      );
      return {
        'date': date,
        'work_blocks': <Map<String, dynamic>>[],
        'break_blocks': <Map<String, dynamic>>[],
        'day_start': startOfDay,
        'day_end': endOfDay,
      };
    }
  }

  /// Get daily summary
  @override
  Future<Map<String, dynamic>> getDailySummary(DateTime date) async {
    try {
      debugPrint('[WEB] Getting daily summary for: $date');
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Use getSessionsWithRelations to get sessions with breaks
      // Cast to SupabaseSessionRepository to access this method
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;

      try {
        final allSessions = await supabaseRepo.getSessionsWithRelations(
          startDate: startOfDay,
          endDate: endOfDay,
        );
        debugPrint('[WEB] Found ${allSessions.length} sessions with relations');

        // Filter out closed sessions with zero work time
        final sessions = allSessions.where((sessionMap) {
          final isClosed = sessionMap['is_closed'] is bool
              ? sessionMap['is_closed'] as bool
              : (sessionMap['is_closed'] as int) == 1;
          final totalWorkSeconds =
              (sessionMap['total_work_seconds'] as int?) ?? 0;
          return !isClosed || totalWorkSeconds > 0;
        }).toList();

        debugPrint('[WEB] Processing ${sessions.length} valid sessions');

        int totalWorkSeconds = 0;
        int totalBreakSeconds = 0;
        int totalBreaks = 0;
        int sessionCount = sessions.length;

        for (final sessionMap in sessions) {
          // Work seconds
          totalWorkSeconds += (sessionMap['total_work_seconds'] as int?) ?? 0;

          // Break seconds and count
          final breaksData =
              sessionMap['break_periods'] as List<dynamic>? ?? [];
          totalBreaks += breaksData.length;

          for (final breakData in breaksData) {
            try {
              DateTime start;
              if (breakData['break_start_time_utc'] != null) {
                start = DateTime.parse(
                  breakData['break_start_time_utc'] as String,
                ).toLocal();
              } else if (breakData['break_start_time'] != null) {
                start = DateTime.parse(breakData['break_start_time'] as String);
              } else {
                continue;
              }

              DateTime end;
              if (breakData['break_end_time_utc'] != null) {
                end = DateTime.parse(
                  breakData['break_end_time_utc'] as String,
                ).toLocal();
              } else if (breakData['break_end_time'] != null) {
                end = DateTime.parse(breakData['break_end_time'] as String);
              } else {
                end = DateTime.now();
              }

              totalBreakSeconds += end.difference(start).inSeconds;
            } catch (e) {
              debugPrint('[WEB] Error parsing break for summary: $e');
            }
          }
        }

        debugPrint('[WEB] ✅ Daily summary calculated successfully');
        return {
          'total_sessions': sessionCount,
          'total_work_seconds': totalWorkSeconds,
          'total_break_seconds': totalBreakSeconds,
          'net_work_seconds':
              totalWorkSeconds, // total_work_seconds is already net in Supabase
          'total_breaks': totalBreaks,
        };
      } catch (e) {
        debugPrint(
          '[WEB] ❌ Error in getSessionsWithRelations, using fallback: $e',
        );
        // Fallback: Use simpler query without relations
        return await _getDailySummaryFallback(date);
      }
    } catch (e) {
      debugPrint('[WEB] ❌ Error getting daily summary: $e');
      return {
        'total_sessions': 0,
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'net_work_seconds': 0,
        'total_breaks': 0,
      };
    }
  }

  /// Fallback method for daily summary using simpler query
  Future<Map<String, dynamic>> _getDailySummaryFallback(DateTime date) async {
    try {
      debugPrint('[WEB] Using fallback daily summary method');
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final sessions = await _sessionRepo.getSessionsInRange(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      int totalWorkSeconds = 0;
      int sessionCount = 0;

      for (final session in sessions) {
        final workSeconds = session.totalWorkSeconds ?? 0;
        if (!session.isClosed || workSeconds > 0) {
          totalWorkSeconds += workSeconds;
          sessionCount++;
        }
      }

      debugPrint('[WEB] ✅ Fallback daily summary completed');
      return {
        'total_sessions': sessionCount,
        'total_work_seconds': totalWorkSeconds,
        'total_break_seconds': 0, // Not available in fallback
        'net_work_seconds': totalWorkSeconds,
        'total_breaks': 0, // Not available in fallback
      };
    } catch (e) {
      debugPrint('[WEB] ❌ Fallback method also failed: $e');
      return {
        'total_sessions': 0,
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'net_work_seconds': 0,
        'total_breaks': 0,
      };
    }
  }

  /// Get today's work duration
  @override
  Future<Duration> getTodayWorkDuration() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    debugPrint(
      '[WEB_REPO] Getting today work duration from $startOfDay to $endOfDay',
    );

    final duration = await _sessionRepo.getTotalWorkDuration(
      startDate: startOfDay,
      endDate: endOfDay,
    );

    debugPrint('[WEB_REPO] Today work duration result: $duration');
    return duration;
  }

  /// Get today's break duration
  @override
  Future<Duration> getTodayBreakDuration() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // Cast to SupabaseSessionRepository to access this method
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;
      final allSessions = await supabaseRepo.getSessionsWithRelations(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      Duration totalBreak = Duration.zero;

      for (final sessionMap in allSessions) {
        final breaksData = sessionMap['break_periods'] as List<dynamic>? ?? [];
        for (final breakData in breaksData) {
          try {
            DateTime start;
            if (breakData['break_start_time'] != null) {
              start = DateTime.parse(breakData['break_start_time'] as String);
            } else if (breakData['break_start_time_utc'] != null) {
              start = DateTime.parse(
                breakData['break_start_time_utc'] as String,
              ).toLocal();
            } else {
              continue;
            }

            DateTime end;
            if (breakData['break_end_time'] != null) {
              end = DateTime.parse(breakData['break_end_time'] as String);
            } else if (breakData['break_end_time_utc'] != null) {
              end = DateTime.parse(
                breakData['break_end_time_utc'] as String,
              ).toLocal();
            } else {
              end = DateTime.now();
            }

            totalBreak += end.difference(start);
          } catch (e) {
            debugPrint('[WEB] Error parsing break for today duration: $e');
          }
        }
      }

      return totalBreak;
    } catch (e) {
      debugPrint('[WEB] Error getting today break duration: $e');
      return Duration.zero;
    }
  }

  /// Get month's closed work duration
  @override
  Future<Duration> getMonthClosedWorkDuration() async {
    final today = DateTime.now();
    final startOfMonth = DateTime(today.year, today.month);
    final endOfMonth = DateTime(today.year, today.month + 1);

    debugPrint(
      '[WEB_REPO] Getting month work duration from $startOfMonth to $endOfMonth',
    );

    final duration = await _sessionRepo.getTotalWorkDuration(
      startDate: startOfMonth,
      endDate: endOfMonth,
    );

    debugPrint('[WEB_REPO] Month work duration result: $duration');
    return duration;
  }

  /// Get month's break duration
  @override
  Future<Duration> getMonthBreakDuration() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final endOfMonth = DateTime(now.year, now.month + 1);

    try {
      // Cast to SupabaseSessionRepository to access this method
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;
      final allSessions = await supabaseRepo.getSessionsWithRelations(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      Duration totalBreak = Duration.zero;

      for (final sessionMap in allSessions) {
        final breaksData = sessionMap['break_periods'] as List<dynamic>? ?? [];
        for (final breakData in breaksData) {
          try {
            DateTime start;
            if (breakData['break_start_time'] != null) {
              start = DateTime.parse(breakData['break_start_time'] as String);
            } else if (breakData['break_start_time_utc'] != null) {
              start = DateTime.parse(
                breakData['break_start_time_utc'] as String,
              ).toLocal();
            } else {
              continue;
            }

            DateTime end;
            if (breakData['break_end_time'] != null) {
              end = DateTime.parse(breakData['break_end_time'] as String);
            } else if (breakData['break_end_time_utc'] != null) {
              end = DateTime.parse(
                breakData['break_end_time_utc'] as String,
              ).toLocal();
            } else {
              end = DateTime.now();
            }

            totalBreak += end.difference(start);
          } catch (e) {
            debugPrint('[WEB] Error parsing break for month duration: $e');
          }
        }
      }

      return totalBreak;
    } catch (e) {
      debugPrint('[WEB] Error getting month break duration: $e');
      return Duration.zero;
    }
  }

  /// Get all-time closed work duration
  @override
  Future<Duration> getAllTimeClosedWorkDuration() async {
    final startOfTime = DateTime(2020);
    final endOfTime = DateTime.now().add(const Duration(days: 1));
    return await _sessionRepo.getTotalWorkDuration(
      startDate: startOfTime,
      endDate: endOfTime,
    );
  }

  /// Get total sessions count
  @override
  Future<int> getTotalSessionsCount() async {
    try {
      debugPrint('[WEB_REPO] Getting total sessions count');

      final sessions = await _sessionRepo.getSessionsInRange(
        startDate: DateTime(2020),
        endDate: DateTime.now().add(const Duration(days: 1)),
      );

      debugPrint('[WEB_REPO] Total sessions count result: ${sessions.length}');
      return sessions.length;
    } catch (e) {
      debugPrint('[WEB_REPO] Error getting total sessions count: $e');
      return 0;
    }
  }

  /// Get monthly daily timesheets - OPTIMIZED for Web
  /// Uses materialized view to avoid N+1 queries
  @override
  Future<List<DailyTimeSheet>> getMonthlyDailyTimeSheets(
    int year,
    int month, {
    bool refresh = false,
  }) async {
    try {
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;

      debugPrint(
        '[WEB] Fetching monthly timesheet for $year/$month (refresh: $refresh)',
      );

      // 0. Manual refresh requested?
      if (refresh) {
        debugPrint(
          '[WEB] Manual refresh requested, refreshing materialized view...',
        );
        await supabaseRepo.refreshMonthlySummary();
      }

      // 1. Fetch aggregated stats from materialized view
      var monthlyStats = await supabaseRepo.getMonthlySummary(year, month);
      debugPrint(
        '[WEB] Initial query returned ${monthlyStats.length} days of data',
      );

      // 2. Smart Refresh Strategy
      // If view is empty (likely unpopulated), force refresh and retry
      if (monthlyStats.isEmpty && !refresh) {
        debugPrint(
          '[WEB] Monthly summary empty, attempting auto-refresh of MV...',
        );
        await supabaseRepo.refreshMonthlySummary();
        monthlyStats = await supabaseRepo.getMonthlySummary(year, month);
        debugPrint('[WEB] After refresh: ${monthlyStats.length} days of data');
      } else if (!refresh) {
        // If we have data, we still want to refresh the cache in the background
        // to ensure we aren't showing stale data next time.
        // We don't await this to keep the UI snappy.
        supabaseRepo
            .refreshMonthlySummary()
            .then((_) {
              debugPrint(
                '[WEB] Background refresh of monthly summary completed',
              );
            })
            .catchError((e) {
              debugPrint('[WEB] Background refresh failed: $e');
            });
      }

      if (monthlyStats.isEmpty) {
        debugPrint('[WEB] No data found for $year/$month after all attempts');
        return [];
      }

      debugPrint(
        '[WEB] Processing ${monthlyStats.length} days for monthly timesheet',
      );

      // 2. Map to DailyTimesheet objects
      return monthlyStats.map((stat) {
        final date = DateTime.parse(stat['date'] as String);
        final totalWorkSeconds = (stat['total_work_seconds'] as int?) ?? 0;
        final totalBreakSeconds = (stat['total_break_seconds'] as int?) ?? 0;
        final totalWorkDuringSleepSeconds =
            (stat['total_work_during_sleep_seconds'] as int?) ?? 0;

        // If we want to show break duration in the table, we'd need to add a fake break
        // or update DailyTimesheet to accept raw values.

        // Hack: To make totalBreakTime work, we add a single synthetic break
        final syntheticBreaks = totalBreakSeconds > 0
            ? [
                BreakPeriod(
                  startTime: date, // Dummy time
                  endTime: date.add(Duration(seconds: totalBreakSeconds)),
                ),
              ]
            : <BreakPeriod>[];

        // Create synthetic work-during-sleep periods to make totalWorkDuringSleepTime work
        final syntheticSleepPeriods = totalWorkDuringSleepSeconds > 0
            ? [
                WorkDuringSleepPeriod(
                  sleepStartTime: date, // Dummy time
                  wakeTime: date.add(
                    Duration(seconds: totalWorkDuringSleepSeconds),
                  ),
                  note: 'Work during sleep',
                ),
              ]
            : <WorkDuringSleepPeriod>[];

        final sessionForTotals = AttendanceSession(
          id: 'summary_$date',
          // Explicitly use the local time string from the view as the check-in time
          // This represents the "Wall Clock" time as calculated by the SQL view
          checkInTime: DateTime.parse(stat['first_check_in'] as String),
          checkOutTime: stat['last_check_out'] != null
              ? DateTime.parse(stat['last_check_out'] as String)
              : null,
          checkInSource: EventSource.manualUser,
          isClosed: true, // Force use of captured duration
          breaks: syntheticBreaks,
          workDuringSleepPeriods: syntheticSleepPeriods,
          capturedWorkDuration: Duration(seconds: totalWorkSeconds),
          // CRITICAL: innovative fix for timezone display issues
          // We intentionally DO NOT populate checkInTimeUtc here.
          // The SQL view already returns the correct "Wall Clock" time in 'first_check_in'.
          // By leaving checkInTimeUtc null, the UI will fall back to using checkInTime directly,
          // preventing any unwanted client-side timezone conversions (e.g. UTC -> Local).
        );

        return DailyTimeSheet(date: date, sessions: [sessionForTotals]);
      }).toList();
    } catch (e, stackTrace) {
      debugPrint('[WEB] Error getting optimized monthly timesheets: $e');
      debugPrint('[WEB] Stack trace: $stackTrace');
      // Return empty list on error as we have removed the slow fallback
      return [];
    }
  }

  /// Get available months
  /// Get available months
  @override
  Future<List<Map<String, int>>> getAvailableMonths() async {
    try {
      final supabaseRepo = _sessionRepo as SupabaseSessionRepository;
      return await supabaseRepo.getAvailableMonths();
    } catch (e) {
      debugPrint('[WEB] Error getting available months: $e');
      return [];
    }
  }
}

/// Mock database implementation for web platform
/// This satisfies the Database type requirement but is never actually used
class _MockDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Database operations not supported on web platform. '
      'This is a mock database that should never be called.',
    );
  }
}
