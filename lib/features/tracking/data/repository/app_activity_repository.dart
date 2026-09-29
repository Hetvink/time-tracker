import 'package:flutter/foundation.dart';
import '../models/app_activity.dart';
import '../datasource/database_service.dart';

class AppActivityRepository {
  Future<int> insertActivity(AppActivity activity) async {
    final db = await DatabaseService.database;
    return await db.insert('app_activities', activity.toMap());
  }

  Future<void> updateActivity(AppActivity activity) async {
    final db = await DatabaseService.database;
    await db.update(
      'app_activities',
      {...activity.toMap(), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [activity.id],
    );
  }

  Future<void> endActivity(int activityId, DateTime endTime) async {
    final db = await DatabaseService.database;
    final activity = await getActivityById(activityId);
    if (activity == null) return;

    final duration = endTime.difference(activity.startTime);
    await db.update(
      'app_activities',
      {
        'end_time': endTime.toIso8601String(),
        'end_time_utc': endTime.toUtc().toIso8601String(),
        'duration_seconds': duration.inSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
  }

  Future<AppActivity?> getActivityById(int id) async {
    final db = await DatabaseService.database;
    final results = await db.query(
      'app_activities',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return AppActivity.fromMap(results.first);
  }

  Future<List<AppActivity>> getActivitiesBySession(dynamic sessionId) async {
    final db = await DatabaseService.database;

    // FIXED: Handle both int and string session IDs for consistency
    // This prevents issues where activities are stored with one type but queried with another
    String whereClause;
    List<dynamic> whereArgs;

    if (sessionId is String) {
      // For string session IDs, check both string and int representations
      whereClause =
          '(session_id = ? OR session_id = CAST(? AS INTEGER)) AND (is_deleted IS NULL OR is_deleted = 0)';
      whereArgs = [sessionId, sessionId];
    } else {
      // For int session IDs, check both int and string representations
      whereClause =
          '(session_id = ? OR session_id = CAST(? AS TEXT)) AND (is_deleted IS NULL OR is_deleted = 0)';
      whereArgs = [sessionId, sessionId.toString()];
    }

    final results = await db.query(
      'app_activities',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'start_time ASC',
    );

    debugPrint(
      '[APP_REPO] Query for session $sessionId (${sessionId.runtimeType}): ${results.length} activities found',
    );

    return results.map((map) => AppActivity.fromMap(map)).toList();
  }

  Future<List<AppActivity>> getActivitiesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await DatabaseService.database;
    final results = await db.query(
      'app_activities',
      where:
          'start_time >= ? AND start_time < ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
      orderBy: 'start_time ASC',
    );

    return results.map((map) => AppActivity.fromMap(map)).toList();
  }

  Future<List<AppActivity>> getActivitiesForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getActivitiesByDateRange(startOfDay, endOfDay);
  }

  /// SIMPLIFIED: Get activities for a date, only those linked to attendance sessions
  /// This ensures we only show activities during actual working hours (check-in to check-out)
  Future<List<AppActivity>> getActivitiesForDateWithSessions(
    DateTime date,
  ) async {
    final db = await DatabaseService.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Query activities that have a valid session_id (linked to timesheet)
    final results = await db.query(
      'app_activities',
      where:
          'start_time >= ? AND start_time < ? AND session_id IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'start_time ASC',
    );

    return results.map((map) => AppActivity.fromMap(map)).toList();
  }

  Future<DailyActivity> getDailyActivity(DateTime date) async {
    final activities = await getActivitiesForDate(date);
    return DailyActivity(date: date, activities: activities);
  }

  Future<AppActivity?> getLastActivity() async {
    final db = await DatabaseService.database;
    final results = await db.query(
      'app_activities',
      where: 'is_deleted IS NULL OR is_deleted = 0',
      orderBy: 'start_time DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return AppActivity.fromMap(results.first);
  }

  Future<AppActivity?> getCurrentActivity() async {
    final db = await DatabaseService.database;
    final results = await db.query(
      'app_activities',
      where: 'end_time IS NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      orderBy: 'start_time DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return AppActivity.fromMap(results.first);
  }

  /// Get the latest activity time for a session (for recovery purposes)
  /// Returns the most recent end_time OR start_time from activities in this session
  /// This is used during crash recovery to determine actual last activity time
  Future<DateTime?> getLatestActivityTime(dynamic sessionId) async {
    final db = await DatabaseService.database;

    // Get the latest activity with an end_time
    final endedActivities = await db.query(
      'app_activities',
      where:
          'session_id = ? AND end_time IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [sessionId],
      orderBy: 'end_time DESC',
      limit: 1,
    );

    // Get the latest activity that's still active (no end_time)
    final activeActivities = await db.query(
      'app_activities',
      where:
          'session_id = ? AND end_time IS NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [sessionId],
      orderBy: 'start_time DESC',
      limit: 1,
    );

    DateTime? latestTime;

    // Check ended activities
    if (endedActivities.isNotEmpty) {
      final endTime = endedActivities.first['end_time'] as String?;
      if (endTime != null) {
        latestTime = DateTime.parse(endTime);
      }
    }

    // Check active activities (use start_time since they don't have end_time)
    if (activeActivities.isNotEmpty) {
      final startTime = activeActivities.first['start_time'] as String?;
      if (startTime != null) {
        final activeStartTime = DateTime.parse(startTime);
        // Use the more recent time
        if (latestTime == null || activeStartTime.isAfter(latestTime)) {
          latestTime = activeStartTime;
        }
      }
    }

    return latestTime;
  }

  /// Get active activity for a specific app and window
  /// This helps prevent duplicate entries for the same window
  Future<AppActivity?> getActiveActivityForWindow(
    String appName,
    String? windowTitle,
    dynamic sessionId,
  ) async {
    final db = await DatabaseService.database;

    // FIXED: Handle both int and string session IDs for consistency
    String whereClause =
        'end_time IS NULL AND app_name = ? AND (is_deleted IS NULL OR is_deleted = 0)';
    List<dynamic> whereArgs = [appName];

    if (sessionId != null) {
      if (sessionId is String) {
        // For string session IDs, check both string and int representations
        whereClause +=
            ' AND (session_id = ? OR session_id = CAST(? AS INTEGER))';
        whereArgs.addAll([sessionId, sessionId]);
      } else {
        // For int session IDs, check both int and string representations
        whereClause += ' AND (session_id = ? OR session_id = CAST(? AS TEXT))';
        whereArgs.addAll([sessionId, sessionId.toString()]);
      }
    }

    final results = await db.query(
      'app_activities',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'start_time DESC',
    );

    if (results.isEmpty) return null;

    // Filter by window title in code (since it can be null)
    for (final result in results) {
      final activity = AppActivity.fromMap(result);
      // Match if both are null or both are equal
      if ((activity.windowTitle == null && windowTitle == null) ||
          (activity.windowTitle == windowTitle)) {
        return activity;
      }
    }

    return null;
  }

  Future<Map<String, Duration>> getAppUsageForDate(DateTime date) async {
    final dailyActivity = await getDailyActivity(date);
    return dailyActivity.appUsageMap;
  }

  Future<Map<String, Duration>> getAppUsageForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final activities = await getActivitiesByDateRange(startDate, endDate);
    final Map<String, Duration> usage = {};

    for (final activity in activities) {
      usage[activity.appName] =
          (usage[activity.appName] ?? Duration.zero) + activity.duration;
    }

    return usage;
  }

  /// Close any open activity records whose attendance session is already closed.
  ///
  /// This fixes the "21-hour duration" bug:
  /// If the app crashed / was force-quit while an activity was being tracked,
  /// the row in `app_activities` is left with `end_time = NULL`. When the app
  /// restarts, any view that uses `endTime ?? DateTime.now()` sees an activity
  /// that has been "running" since yesterday, giving absurd durations.
  ///
  /// We resolve this by setting `end_time` to the session's `check_out_time`
  /// for every such orphaned activity record.
  Future<void> closeStaleActivities() async {
    final db = await DatabaseService.database;

    // Find open activities whose attendance session is already closed
    final staleActivities = await db.rawQuery('''
      SELECT a.id,
             s.check_out_time,
             s.check_out_time_utc
      FROM app_activities a
      JOIN attendance_sessions s ON CAST(a.session_id AS TEXT) = CAST(s.id AS TEXT)
      WHERE a.end_time IS NULL
        AND s.is_closed = 1
        AND (a.is_deleted IS NULL OR a.is_deleted = 0)
    ''');

    if (staleActivities.isEmpty) return;

    for (final row in staleActivities) {
      final activityId = row['id'] as int;
      // Prefer UTC checkout; fall back to local
      final checkoutStr =
          (row['check_out_time_utc'] as String?) ??
          (row['check_out_time'] as String?);
      if (checkoutStr != null) {
        try {
          final endTime = DateTime.parse(checkoutStr);
          await endActivity(activityId, endTime);
        } catch (e) {
          debugPrint(
            '[ACTIVITY_REPO] Failed to close stale activity $activityId: $e',
          );
        }
      }
    }

    debugPrint(
      '[ACTIVITY_REPO] Closed ${staleActivities.length} stale open activities',
    );
  }

  Future<void> deleteActivitiesBySession(int sessionId) async {
    final db = await DatabaseService.database;
    await db.delete(
      'app_activities',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteAllActivities() async {
    final db = await DatabaseService.database;
    await db.delete('app_activities');
  }

  /// Get activities grouped by hour for timeline visualization
  Future<Map<int, List<AppActivity>>> getActivitiesByHour(DateTime date) async {
    final activities = await getActivitiesForDate(date);
    final Map<int, List<AppActivity>> hourlyActivities = {};

    for (final activity in activities) {
      final hour = activity.startTime.hour;
      hourlyActivities[hour] = hourlyActivities[hour] ?? [];
      hourlyActivities[hour]!.add(activity);
    }

    return hourlyActivities;
  }

  /// Soft deletes an activity by id
  Future<void> softDeleteActivity(int activityId) async {
    final db = await DatabaseService.database;
    await db.update(
      'app_activities',
      {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [activityId],
    );
  }

  /// Soft deletes matching overlapping activities within a specific time range
  Future<List<int>> deleteActivitiesInTimeRange(
    dynamic sessionId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final db = await DatabaseService.database;
    final startUtc = startTime.toUtc().toIso8601String();
    final endUtc = endTime.toUtc().toIso8601String();

    String sessionWhere = sessionId is String
        ? '(session_id = ? OR session_id = CAST(? AS INTEGER))'
        : '(session_id = ? OR session_id = CAST(? AS TEXT))';
    List<dynamic> sessionArgs = [sessionId, sessionId.toString()];

    // Find activities in the time range
    // Overlap: start < endRange AND (end > startRange OR end IS NULL)
    final results = await db.query(
      'app_activities',
      where:
          '$sessionWhere AND start_time_utc < ? AND (end_time_utc > ? OR end_time_utc IS NULL) AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [...sessionArgs, endUtc, startUtc],
    );

    List<int> deletedIds = [];
    for (final result in results) {
      final id = result['id'] as int;
      await softDeleteActivity(id);
      deletedIds.add(id);
    }

    return deletedIds;
  }
}
