import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRepository {
  final SupabaseClient _supabase;

  AdminRepository(this._supabase);

  // ============================================================================
  // USER MANAGEMENT
  // ============================================================================

  /// Fetch all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .order('name', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }

  /// Fetch a specific user by ID
  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Failed to fetch user: $e');
    }
  }

  // ============================================================================
  // SESSION & ACTIVITY DATA
  // ============================================================================

  /// Fetch user sessions in a date range
  Future<List<Map<String, dynamic>>> getUserSessions({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _supabase
          .from('attendance_sessions')
          .select('''
            *,
            break_periods (*),
            work_during_sleep_periods (*)
          ''')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .gte('check_in_time_utc', startDate.toUtc().toIso8601String())
          .lt('check_in_time_utc', endDate.toUtc().toIso8601String())
          .order('check_in_time_utc', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch user sessions: $e');
    }
  }

  /// Fetch detailed day activity for a specific user and date
  Future<Map<String, dynamic>> getUserDayActivity({
    required String userId,
    required DateTime date,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final sessions = await _supabase
          .from('attendance_sessions')
          .select('''
            *,
            break_periods (*),
            work_during_sleep_periods (*),
            app_activities (*)
          ''')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .gte('check_in_time_utc', startOfDay.toUtc().toIso8601String())
          .lt('check_in_time_utc', endOfDay.toUtc().toIso8601String())
          .order('check_in_time_utc', ascending: false);

      // Calculate statistics
      int totalWorkSeconds = 0;
      int totalBreakSeconds = 0;
      int sessionCount = 0;

      for (var session in sessions) {
        if (session['is_closed'] == true) {
          totalWorkSeconds += (session['total_work_seconds'] as int?) ?? 0;
          sessionCount++;
        }

        final breaks = session['break_periods'] as List<dynamic>? ?? [];
        for (var breakPeriod in breaks) {
          if (breakPeriod['break_end_time'] != null) {
            final start = DateTime.parse(breakPeriod['break_start_time']);
            final end = DateTime.parse(breakPeriod['break_end_time']);
            totalBreakSeconds += end.difference(start).inSeconds;
          }
        }
      }

      return {
        'date': date.toIso8601String(),
        'sessions': sessions,
        'statistics': {
          'total_work_seconds': totalWorkSeconds,
          'total_break_seconds': totalBreakSeconds,
          'session_count': sessionCount,
        },
      };
    } catch (e) {
      throw Exception('Failed to fetch user day activity: $e');
    }
  }

  /// Fetch monthly summary for a specific user
  Future<Map<String, dynamic>> getUserMonthSummary({
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final startOfMonth = DateTime(year, month);
      final endOfMonth = DateTime(year, month + 1);

      final sessions = await getUserSessions(
        userId: userId,
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      // Calculate monthly statistics using Time Range Merging to handle overlaps

      // 1. Collect all Work Intervals (CheckIn-CheckOut minus Breaks)
      List<({DateTime start, DateTime end})> allWorkIntervals = [];

      // 2. Collect all Sleep Intervals
      List<({DateTime start, DateTime end})> allSleepIntervals = [];

      // 3. Track daily work intervals for accurate daily trends
      Map<String, List<({DateTime start, DateTime end})>> dailyIntervals = {};

      int totalSessions = 0;
      int totalBreakSeconds = 0; // Raw sum of breaks (metadata)

      for (var session in sessions) {
        if (session['is_closed'] != true) continue;

        totalSessions++;

        final checkIn = DateTime.parse(session['check_in_time']).toUtc();
        final checkOut = DateTime.parse(session['check_out_time']).toUtc();

        // Get breaks for this session
        final breaks = session['break_periods'] as List<dynamic>? ?? [];
        List<({DateTime start, DateTime end})> sessionBreaks = [];

        for (var b in breaks) {
          if (b['break_end_time'] != null) {
            final bStart = DateTime.parse(b['break_start_time']).toUtc();
            final bEnd = DateTime.parse(b['break_end_time']).toUtc();
            sessionBreaks.add((start: bStart, end: bEnd));
            totalBreakSeconds += bEnd.difference(bStart).inSeconds;
          }
        }

        // Calculate Work Segments for this session (Session - Breaks)
        // We start with one segment [CheckIn, CheckOut] and subtract breaks
        List<({DateTime start, DateTime end})> sessionSegments = [
          (start: checkIn, end: checkOut),
        ];

        for (final breakPeriod in sessionBreaks) {
          List<({DateTime start, DateTime end})> newSegments = [];
          for (final segment in sessionSegments) {
            // If break is completely outside segment, keep segment
            if (breakPeriod.end.isBefore(segment.start) ||
                breakPeriod.start.isAfter(segment.end)) {
              newSegments.add(segment);
            } else {
              // Break overlaps segment. Split segment.
              if (breakPeriod.start.isAfter(segment.start)) {
                newSegments.add((start: segment.start, end: breakPeriod.start));
              }
              if (breakPeriod.end.isBefore(segment.end)) {
                newSegments.add((start: breakPeriod.end, end: segment.end));
              }
            }
          }
          sessionSegments = newSegments;
        }

        allWorkIntervals.addAll(sessionSegments);

        // Group by day for daily trend
        // Note: A segment might span days. For simple trend, we attribute to Start Day.
        // For distinct daily accuracy, we'd need to split segments by midnight.
        // Let's split by midnight for high accuracy daily stats?
        // Or keep it simple: Attribute to date of start.
        // User wants "in day in my life", so precise split is better.
        for (final segment in sessionSegments) {
          _distributeSegmentToDays(segment, dailyIntervals);
        }

        // Collect Sleep Intervals
        final sleepPeriods =
            session['work_during_sleep_periods'] as List<dynamic>? ?? [];
        for (var s in sleepPeriods) {
          final sStart = DateTime.parse(s['sleep_start_time']).toUtc();
          final wake = DateTime.parse(s['wake_time']).toUtc();
          allSleepIntervals.add((start: sStart, end: wake));
        }
      }

      // Calculate Effective Durations (Merging overlaps)
      final totalWorkSeconds = _calculateEffectiveDuration(allWorkIntervals);
      final totalWorkDuringSleepSeconds = _calculateEffectiveDuration(
        allSleepIntervals,
      );

      // Calculate Daily Totals
      Map<String, int> dailyWorkSeconds = {};
      dailyIntervals.forEach((dateKey, intervals) {
        dailyWorkSeconds[dateKey] = _calculateEffectiveDuration(intervals);
      });

      // Normal work is Total work minus Work during sleep
      // (Since Total Work logic includes Sleep time if it was part of session)
      final normalWorkSeconds = (totalWorkSeconds - totalWorkDuringSleepSeconds)
          .clamp(0, totalWorkSeconds);

      return {
        'year': year,
        'month': month,
        'total_work_seconds': totalWorkSeconds,
        'normal_work_seconds': normalWorkSeconds,
        'total_break_seconds': totalBreakSeconds,
        'total_work_during_sleep_seconds': totalWorkDuringSleepSeconds,
        'total_sessions': totalSessions,
        'average_session_seconds': totalSessions > 0
            ? totalWorkSeconds ~/ totalSessions
            : 0,
        'daily_work_seconds': dailyWorkSeconds,
      };
    } catch (e) {
      throw Exception('Failed to fetch user month summary: $e');
    }
  }

  void _distributeSegmentToDays(
    ({DateTime start, DateTime end}) segment,
    Map<String, List<({DateTime start, DateTime end})>> dailyMap,
  ) {
    var current = segment.start;
    while (current.isBefore(segment.end)) {
      final dateKey =
          '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';

      final endOfDay = DateTime.utc(
        current.year,
        current.month,
        current.day,
        23,
        59,
        59,
        999,
      );
      final segmentEndForDay = segment.end.isBefore(endOfDay)
          ? segment.end
          : endOfDay.add(const Duration(milliseconds: 1));

      dailyMap.putIfAbsent(dateKey, () => []).add((
        start: current,
        end: segmentEndForDay,
      ));

      // Move to next day
      current = DateTime.utc(
        current.year,
        current.month,
        current.day,
      ).add(const Duration(days: 1));
    }
  }

  int _calculateEffectiveDuration(
    List<({DateTime start, DateTime end})> intervals,
  ) {
    if (intervals.isEmpty) return 0;

    // Sort by start time
    intervals.sort((a, b) => a.start.compareTo(b.start));

    int totalSeconds = 0;
    var currentStart = intervals.first.start;
    var currentEnd = intervals.first.end;

    for (int i = 1; i < intervals.length; i++) {
      final next = intervals[i];

      if (next.start.isBefore(currentEnd)) {
        // Overlap: Extend current end if needed
        if (next.end.isAfter(currentEnd)) {
          currentEnd = next.end;
        }
      } else {
        // No overlap: Add duration and start new segment
        totalSeconds += currentEnd.difference(currentStart).inSeconds;
        currentStart = next.start;
        currentEnd = next.end;
      }
    }

    // Add last segment
    totalSeconds += currentEnd.difference(currentStart).inSeconds;
    return totalSeconds;
  }

  /// Fetch raw app activities (with window titles) for a user in a date range.
  /// Used by the monthly Mixed Sessions tab to group by app+window.
  Future<List<Map<String, dynamic>>> getUserMonthlyAppActivityWithWindows({
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final startOfMonth = DateTime(year, month).toUtc();
      final endOfMonth = DateTime(year, month + 1).toUtc();

      final response = await _supabase
          .from('app_activities')
          .select('app_name, window_title, duration_seconds')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .gte('start_time_utc', startOfMonth.toIso8601String())
          .lt('start_time_utc', endOfMonth.toIso8601String())
          .order('start_time_utc', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch monthly app activities: $e');
    }
  }

  /// Fetch app-wise activity breakdown for a user in a date range
  Future<List<Map<String, dynamic>>> getUserAppActivityBreakdown({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _supabase
          .from('app_activities')
          .select()
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .gte('start_time_utc', startDate.toUtc().toIso8601String())
          .lt('start_time_utc', endDate.toUtc().toIso8601String())
          .order('start_time_utc', ascending: false);

      final activities = List<Map<String, dynamic>>.from(response);

      // Aggregate by app name
      Map<String, int> appDurations = {};
      for (var activity in activities) {
        final appName = activity['app_name'] as String? ?? 'Unknown';
        final duration = (activity['duration_seconds'] as int?) ?? 0;
        appDurations[appName] = (appDurations[appName] ?? 0) + duration;
      }

      // Convert to list and sort by duration
      final breakdown = appDurations.entries.map((entry) {
        return {'app_name': entry.key, 'total_duration_seconds': entry.value};
      }).toList();

      breakdown.sort(
        (a, b) => (b['total_duration_seconds'] as int).compareTo(
          a['total_duration_seconds'] as int,
        ),
      );

      return breakdown;
    } catch (e) {
      throw Exception('Failed to fetch app activity breakdown: $e');
    }
  }

  /// Fetch comprehensive user statistics for a date range
  Future<Map<String, dynamic>> getUserStatistics({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final sessions = await getUserSessions(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
      );

      int totalWorkSeconds = 0;
      int totalBreakSeconds = 0;
      int totalSessions = 0;
      int activeSessions = 0;

      for (var session in sessions) {
        final isClosed = session['is_closed'] == true;

        if (isClosed) {
          totalWorkSeconds += (session['total_work_seconds'] as int?) ?? 0;
          totalSessions++;
        } else {
          activeSessions++;
        }

        final breaks = session['break_periods'] as List<dynamic>? ?? [];
        for (var breakPeriod in breaks) {
          if (breakPeriod['break_end_time'] != null) {
            final start = DateTime.parse(breakPeriod['break_start_time']);
            final end = DateTime.parse(breakPeriod['break_end_time']);
            totalBreakSeconds += end.difference(start).inSeconds;
          }
        }
      }

      return {
        'total_work_seconds': totalWorkSeconds,
        'total_break_seconds': totalBreakSeconds,
        'total_sessions': totalSessions,
        'active_sessions': activeSessions,
        'average_session_seconds': totalSessions > 0
            ? totalWorkSeconds ~/ totalSessions
            : 0,
      };
    } catch (e) {
      throw Exception('Failed to fetch user statistics: $e');
    }
  }

  // ============================================================================
  // LEGACY METHOD (kept for backward compatibility)
  // ============================================================================

  /// Fetch usage stats for a specific user (Example: total sessions)
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      // This is a basic example. You might want to use RPCs for more complex aggregate data
      final sessionsCount = await _supabase
          .from('attendance_sessions')
          .count()
          .eq('user_id', userId);

      return {'total_sessions': sessionsCount};
    } catch (e) {
      throw Exception('Failed to fetch user stats: $e');
    }
  }
}
