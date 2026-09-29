import 'package:flutter/foundation.dart';
import '../../data/models/daily_timesheet.dart';
import '../../../tracking/data/models/attendance_state.dart';
import '../../../tracking/data/repository/attendance_repository.dart';

class TimeSheetProvider extends ChangeNotifier {
  final AttendanceRepository _repository;

  TimeSheetProvider({required AttendanceRepository repository})
    : _repository = repository;

  // Helper to parse local time strings correctly as local time
  DateTime _parseLocalTime(String timeStr) {
    final parsed = DateTime.parse(timeStr);
    // If the parsed time is UTC (has 'Z' or offset), convert to local
    if (parsed.isUtc) {
      return parsed.toLocal();
    }
    // If already local, return as-is
    return parsed;
  }

  Future<DailyTimeSheet> getTimesheetForDate(DateTime date) async {
    final sessions = await _repository.getSessionsForDate(date);
    final List<AttendanceSession> attendanceSessions = [];
    final Set<dynamic> sessionIds = {};

    // Helper to process session map
    Future<void> processSession(Map<String, dynamic> sessionMap) async {
      final sessionId = sessionMap['id']; // dynamic (int or String)
      if (sessionIds.contains(sessionId)) return;

      sessionIds.add(sessionId);
      final breaksData = await _repository.getBreaksForSession(sessionId);

      final breaks = breaksData
          .map(
            (b) => BreakPeriod(
              startTime: _parseLocalTime(b['break_start_time'] as String),
              endTime: b['break_end_time'] != null
                  ? _parseLocalTime(b['break_end_time'] as String)
                  : null,
            ),
          )
          .toList();

      // Load work-during-sleep periods
      final workDuringSleepData = await _repository
          .getWorkDuringSleepForSession(sessionId);

      final workDuringSleepPeriods = workDuringSleepData
          .map(
            (w) => WorkDuringSleepPeriod(
              sleepStartTime: _parseLocalTime(w['sleep_start_time'] as String),
              wakeTime: _parseLocalTime(w['wake_time'] as String),
              note: w['note'] as String,
            ),
          )
          .toList();

      attendanceSessions.add(
        AttendanceSession.fromMap(sessionMap, breaks, workDuringSleepPeriods),
      );
    }

    // Process DB results
    for (var sessionMap in sessions) {
      await processSession(sessionMap);
    }

    // Fail-safe: If viewing today, explicitly check for active session
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    if (isToday) {
      final unfinishedSession = await _repository.getUnfinishedSession();
      if (unfinishedSession != null) {
        // Verify it belongs to today (or started today)
        // Actually, if it's unfinished, it IS the active session for today/now.
        // Even if it started yesterday, it's crossing into today.
        // But getSessionsForDate query logic handles "check_in_time" based.
        // If it started yesterday, it won't show in TODAY's list by definition of the query.
        // BUT the user wants to see "Active session".
        // If I started yesterday 11PM and it's now Today 1AM, should it show in Today's list?
        // Usually, yes, or at least visible.
        // But the previous logic was check_in_time based.
        // Let's stick to: If it started TODAY, ensure it's there.

        final checkInTime = DateTime.parse(
          unfinishedSession['check_in_time'] as String,
        );
        final checkInDay = DateTime(
          checkInTime.year,
          checkInTime.month,
          checkInTime.day,
        );
        final queryingDay = DateTime(date.year, date.month, date.day);

        if (checkInDay == queryingDay) {
          await processSession(unfinishedSession);
        }
      }
    }

    // Sort descending
    attendanceSessions.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

    return DailyTimeSheet(date: date, sessions: attendanceSessions);
  }

  Future<Map<String, dynamic>> getDailySummary(DateTime date) async {
    return await _repository.getDailySummary(date);
  }

  Future<List<DailyTimeSheet>> getWeeklyTimesheets(DateTime weekStart) async {
    final List<DailyTimeSheet> timesheets = [];

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      timesheets.add(await getTimesheetForDate(date));
    }

    return timesheets;
  }

  Future<Map<String, dynamic>> getWeeklySummary(DateTime weekStart) async {
    Duration totalWork = Duration.zero;
    Duration totalBreak = Duration.zero;
    int totalSessions = 0;
    int totalBreaks = 0;

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final summary = await getDailySummary(date);

      totalWork += Duration(seconds: summary['total_work_seconds'] as int);
      totalBreak += Duration(seconds: summary['total_break_seconds'] as int);
      totalSessions += summary['total_sessions'] as int;
      totalBreaks += summary['total_breaks'] as int;
    }

    return {
      'total_sessions': totalSessions,
      'total_work_seconds': totalWork.inSeconds,
      'total_break_seconds': totalBreak.inSeconds,
      'net_work_seconds': (totalWork - totalBreak).inSeconds,
      'total_breaks': totalBreaks,
    };
  }
}
