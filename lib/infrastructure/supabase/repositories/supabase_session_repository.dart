import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/session_model.dart';
import '../../../core/repositories/session_repository.dart';
import '../../../features/tracking/data/models/attendance_state.dart';
import '../../../features/timesheet/data/models/daily_timesheet.dart';

/// Supabase implementation of SessionRepository
/// Used by WEB platform for read-only access to session data
class SupabaseSessionRepository implements SessionRepository {
  final SupabaseClient _supabase;

  SupabaseSessionRepository(this._supabase);

  String? get currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<SessionModel>> getSessionsInRange({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      var query = _supabase
          .from('attendance_sessions')
          .select()
          .gte('check_in_time_utc', startDate.toUtc().toIso8601String())
          .lt('check_in_time_utc', endDate.toUtc().toIso8601String())
          .eq('is_deleted', false);

      // If userId is provided, filter by it. Otherwise filter by current user.
      final targetUserId = userId ?? currentUserId;
      if (targetUserId != null) {
        query = query.eq('user_id', targetUserId);
      }

      final response = await query.order('check_in_time_utc', ascending: false);

      return (response as List)
          .map((json) => SessionModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching sessions in range: $e');
      rethrow;
    }
  }

  @override
  Future<SessionModel?> getSessionById(String id) async {
    try {
      var query = _supabase
          .from('attendance_sessions')
          .select()
          .eq('id', id)
          .eq('is_deleted', false);

      if (currentUserId != null) {
        query = query.eq('user_id', currentUserId!);
      }

      final response = await query.maybeSingle();

      if (response == null) return null;

      return SessionModel.fromJson(response);
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching session by ID: $e');
      rethrow;
    }
  }

  @override
  Future<SessionModel?> getActiveSession() async {
    try {
      var query = _supabase
          .from('attendance_sessions')
          .select()
          .eq('is_closed', false)
          .eq('is_deleted', false);

      if (currentUserId != null) {
        query = query.eq('user_id', currentUserId!);
      }

      final response = await query.maybeSingle();

      if (response == null) return null;

      return SessionModel.fromJson(response);
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching active session: $e');
      rethrow;
    }
  }

  @override
  Future<List<SessionModel>> getTodaySessions() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    return getSessionsInRange(startDate: todayStart, endDate: todayEnd);
  }

  @override
  Future<List<SessionModel>> getThisMonthSessions() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);

    return getSessionsInRange(startDate: monthStart, endDate: monthEnd);
  }

  @override
  Future<SessionModel> createSession(SessionModel session) async {
    // Web platform should NOT create sessions - this is desktop only
    throw UnsupportedError(
      'Creating sessions from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<void> updateSession(SessionModel session) async {
    // Web platform should NOT update sessions - this is desktop only
    throw UnsupportedError(
      'Updating sessions from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<void> closeSession(
    String sessionId, {
    required DateTime checkOutTime,
    required SessionSource checkOutSource,
  }) async {
    // Web platform should NOT close sessions - this is desktop only
    throw UnsupportedError(
      'Closing sessions from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<Duration> getTotalWorkDuration({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      final sessions = await getSessionsInRange(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
      );

      int totalSeconds = 0;
      for (final session in sessions) {
        // For CLOSED sessions, use pre-calculated totalWorkSeconds
        if (session.isClosed && session.totalWorkSeconds != null) {
          totalSeconds += session.totalWorkSeconds!;
        }
        // For ACTIVE sessions, calculate duration in real-time
        else if (!session.isClosed) {
          // Get total session duration (UTC based)
          // CRITICAL FIX: Use UTC for calculation to prevent timezone offset errors (e.g. +5.5h in IST)
          final checkInTimeUtc = session.checkInTimeUtc;
          final checkOutTimeUtc = DateTime.now().toUtc();
          final sessionDuration = checkOutTimeUtc.difference(checkInTimeUtc);

          // Subtract break durations
          final breaks = await getBreaksForSession(session.id);
          Duration totalBreakDuration = Duration.zero;

          for (final breakPeriod in breaks) {
            if (breakPeriod.endTime != null) {
              // Completed break
              totalBreakDuration += breakPeriod.endTime!.difference(
                breakPeriod.startTime,
              );
            } else {
              // Active break - calculate from start to now
              totalBreakDuration += DateTime.now().difference(
                breakPeriod.startTime,
              );
            }
          }

          // Net work duration = session duration - break duration
          final workDuration = sessionDuration - totalBreakDuration;
          totalSeconds += workDuration.inSeconds;

          debugPrint(
            '[SUPABASE] Active session ${session.id}: ${workDuration.inMinutes}m (${sessionDuration.inMinutes}m - ${totalBreakDuration.inMinutes}m breaks)',
          );
        }
      }

      debugPrint(
        '[SUPABASE] Total work duration: ${Duration(seconds: totalSeconds).inMinutes}m from ${sessions.length} sessions',
      );
      return Duration(seconds: totalSeconds);
    } catch (e) {
      debugPrint('[SUPABASE] Error calculating total work duration: $e');
      rethrow;
    }
  }

  @override
  Stream<List<SessionModel>>? watchSessions({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Real-time subscription for live dashboard updates
    final userId = currentUserId;
    if (userId == null) return null;

    return _supabase.from('attendance_sessions').stream(primaryKey: ['id']).map(
      (data) {
        // Filter data in memory since stream doesn't support .eq()
        return data
            .where(
              (json) =>
                  json['user_id'] == userId && json['is_deleted'] == false,
            )
            .map((json) => SessionModel.fromJson(json))
            .toList();
      },
    );
  }

  /// Get sessions with related data (breaks, work-during-sleep periods, activities)
  Future<List<Map<String, dynamic>>> getSessionsWithRelations({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      debugPrint('[SUPABASE] Starting getSessionsWithRelations query...');
      debugPrint('[SUPABASE] Date range: $startDate to $endDate');

      var query = _supabase
          .from('attendance_sessions')
          .select('''
            *,
            break_periods (*),
            work_during_sleep_periods (*),
            app_activities (*)
          ''')
          .gte('check_in_time_utc', startDate.toUtc().toIso8601String())
          .lt('check_in_time_utc', endDate.toUtc().toIso8601String())
          .eq('is_deleted', false);

      // If userId is provided, filter by it. Otherwise filter by current user.
      final targetUserId = userId ?? currentUserId;
      if (targetUserId != null) {
        query = query.eq('user_id', targetUserId);
      }

      // Add timeout to prevent hanging
      final response = await query
          .order('check_in_time_utc', ascending: false)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint(
                '[SUPABASE] ⚠️ Query timeout after 10 seconds, returning empty result',
              );
              throw TimeoutException(
                'Supabase query timed out',
                const Duration(seconds: 10),
              );
            },
          );

      debugPrint(
        '[SUPABASE] ✅ getSessionsWithRelations completed successfully',
      );
      return response;
    } on TimeoutException catch (e) {
      debugPrint('[SUPABASE] ❌ Query timeout: $e');
      rethrow;
    } catch (e) {
      debugPrint('[SUPABASE] ❌ Error fetching sessions with relations: $e');
      rethrow;
    }
  }

  @override
  Future<List<BreakPeriod>> getBreaksForSession(String sessionId) async {
    try {
      final response = await _supabase
          .from('break_periods')
          .select()
          .eq('session_id', sessionId)
          .eq('is_deleted', false)
          .order('break_start_time', ascending: true);

      return (response as List).map((json) {
        // CRITICAL: Use UTC column + .toLocal() for correct timezone display.
        // Supabase timestamptz columns return UTC strings — without .toLocal()
        // the displayed hour is UTC, not the user's local time.
        // Mirrors the correct pattern used in getWorkDuringSleepForSession.
        DateTime startTime;
        if (json['break_start_time_utc'] != null) {
          startTime = DateTime.parse(
            json['break_start_time_utc'] as String,
          ).toLocal();
        } else {
          final parsed = DateTime.parse(json['break_start_time'] as String);
          startTime = parsed.isUtc ? parsed.toLocal() : parsed;
        }

        DateTime? endTime;
        if (json['break_end_time_utc'] != null) {
          endTime = DateTime.parse(
            json['break_end_time_utc'] as String,
          ).toLocal();
        } else if (json['break_end_time'] != null) {
          final parsed = DateTime.parse(json['break_end_time'] as String);
          endTime = parsed.isUtc ? parsed.toLocal() : parsed;
        }

        return BreakPeriod(
          startTime: startTime,
          endTime: endTime,
          note: json['note'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching breaks for session: $e');
      return [];
    }
  }

  @override
  Future<List<WorkDuringSleepPeriod>> getWorkDuringSleepForSession(
    String sessionId,
  ) async {
    try {
      final response = await _supabase
          .from('work_during_sleep_periods')
          .select()
          .eq('session_id', sessionId)
          .eq('is_deleted', false)
          .order('sleep_start_time', ascending: true);

      return (response as List).map((json) {
        DateTime sleepStartTime, wakeTime;

        // Use UTC times if available, otherwise fall back to local times
        if (json['sleep_start_time_utc'] != null) {
          sleepStartTime = DateTime.parse(
            json['sleep_start_time_utc'] as String,
          ).toLocal();
        } else {
          sleepStartTime = DateTime.parse(json['sleep_start_time'] as String);
        }

        if (json['wake_time_utc'] != null) {
          wakeTime = DateTime.parse(json['wake_time_utc'] as String).toLocal();
        } else {
          wakeTime = DateTime.parse(json['wake_time'] as String);
        }

        return WorkDuringSleepPeriod(
          sleepStartTime: sleepStartTime,
          wakeTime: wakeTime,
          note: json['note'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching work during sleep for session: $e');
      return [];
    }
  }

  /// Refresh the monthly summary materialized view
  Future<void> refreshMonthlySummary() async {
    try {
      await _supabase.rpc('refresh_monthly_summary_cache');
    } catch (e) {
      debugPrint('[SUPABASE] Error refreshing monthly summary: $e');
    }
  }

  /// Get monthly summary from materialized view
  Future<List<Map<String, dynamic>>> getMonthlySummary(
    int year,
    int month,
  ) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        debugPrint('[SUPABASE] No user ID set, cannot fetch monthly summary');
        return [];
      }

      // The materialized view is only readable through this access-checked RPC
      final response = await _supabase.rpc(
        'get_monthly_summary',
        params: {'p_user_id': userId, 'p_year': year, 'p_month': month},
      );

      debugPrint('[SUPABASE] Query returned ${(response as List).length} rows');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching monthly summary: $e');
      rethrow;
    }
  }

  Future<List<Map<String, int>>> getAvailableMonths() async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];

      final response =
          await _supabase.rpc(
                'get_available_months',
                params: {'p_user_id': userId},
              )
              as List;

      final List<Map<String, int>> months = [];
      final Set<String> seen = {};

      for (var row in response) {
        final key = '${row['year']}-${row['month']}';
        if (!seen.contains(key)) {
          seen.add(key);
          months.add({
            'year': row['year'] as int,
            'month': row['month'] as int,
          });
        }
      }

      return months;
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching available months: $e');
      return [];
    }
  }

  @override
  Future<void> updateSessionLastSeen(
    String sessionId,
    DateTime lastSeenTime,
  ) async {
    try {
      if (currentUserId == null) return;

      await _supabase
          .from('attendance_sessions')
          .update({
            'last_seen_time': lastSeenTime.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', sessionId)
          .eq('user_id', currentUserId!);
    } catch (e) {
      debugPrint('[SUPABASE] Error updating session last seen: $e');
    }
  }
}
