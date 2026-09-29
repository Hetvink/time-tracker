import 'package:flutter/foundation.dart';

import 'package:time_trak/core/models/activity_model.dart';
import 'package:time_trak/core/repositories/activity_repository.dart';
import '../models/app_activity.dart';
import 'app_activity_repository.dart';

/// Web-compatible wrapper for AppActivityRepository
/// Extends AppActivityRepository to work with ActivityTrackingProvider
///
/// Note: Web platform is READ-ONLY for viewing activity data synced from desktop
class WebAppActivityRepository extends AppActivityRepository {
  final ActivityRepository _activityRepo;

  WebAppActivityRepository(this._activityRepo);

  /// Insert activity - NOT SUPPORTED on web
  @override
  Future<int> insertActivity(AppActivity activity) async {
    throw UnsupportedError(
      'Creating activities from web is not supported. Use desktop app for tracking.',
    );
  }

  /// Update activity - NOT SUPPORTED on web
  @override
  Future<void> updateActivity(AppActivity activity) async {
    throw UnsupportedError(
      'Updating activities from web is not supported. Use desktop app for tracking.',
    );
  }

  /// End activity - NOT SUPPORTED on web
  @override
  Future<void> endActivity(int activityId, DateTime endTime) async {
    throw UnsupportedError(
      'Ending activities from web is not supported. Use desktop app for tracking.',
    );
  }

  /// Get activity by ID
  @override
  Future<AppActivity?> getActivityById(int id) async {
    // Web uses UUID strings, this method is not applicable
    // Return null for compatibility
    return null;
  }

  /// Get activities by session ID
  @override
  Future<List<AppActivity>> getActivitiesBySession(dynamic sessionId) async {
    try {
      // Ensure session ID is treated as a string for Supabase
      final sessionIdString = sessionId.toString();

      final activities = await _activityRepo.getActivitiesForSession(
        sessionIdString,
      );

      final result = activities
          .map((model) => _mapModelToEntity(model, sessionId))
          .toList();

      return result;
    } catch (e) {
      debugPrint(
        '[WEB_ACTIVITY] ERROR getting activities by session $sessionId: $e',
      );
      return [];
    }
  }

  AppActivity _mapModelToEntity(ActivityModel model, dynamic sessionId) {
    // CRITICAL FIX: Calculate duration from UTC times if durationSeconds is missing/zero
    // This prevents timezone issues from causing negative or zero durations
    int? finalDurationSeconds = model.durationSeconds;

    if ((finalDurationSeconds == null || finalDurationSeconds == 0) &&
        model.endTimeUtc != null) {
      final calculatedDuration = model.endTimeUtc!.difference(
        model.startTimeUtc,
      );
      if (!calculatedDuration.isNegative && calculatedDuration.inSeconds > 0) {
        finalDurationSeconds = calculatedDuration.inSeconds;
        debugPrint(
          '[WEB_ACTIVITY] Calculated duration from UTC: ${finalDurationSeconds}s for ${model.appName}',
        );
      }
    }

    return AppActivity(
      id: _parseIntId(model.id),
      sessionId: model.sessionId ?? sessionId, // Keep as String (UUID)
      appName: model.appName,
      windowTitle: model.windowTitle,
      startTime: model.startTimeUtc
          .toLocal(), // Use UTC as source, convert to local
      endTime: model.endTimeUtc
          ?.toLocal(), // Use UTC as source, convert to local
      durationSeconds: finalDurationSeconds,
      activityType: model.activityType.name,
    );
  }

  /// Get activities by date range
  @override
  Future<List<AppActivity>> getActivitiesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final activities = await _activityRepo.getActivitiesInRange(
        startDate: startDate,
        endDate: endDate,
      );

      // Convert ActivityModel to AppActivity
      return activities.map((model) => _mapModelToEntity(model, null)).toList();
    } catch (e) {
      debugPrint('[WEB] Error getting activities by date range: $e');
      return [];
    }
  }

  /// Get activities for a specific date
  @override
  Future<List<AppActivity>> getActivitiesForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getActivitiesByDateRange(startOfDay, endOfDay);
  }

  /// Get activities for date with sessions
  /// This ensures we only show activities during actual working hours
  @override
  Future<List<AppActivity>> getActivitiesForDateWithSessions(
    DateTime date,
  ) async {
    // On web, all activities are already filtered by sessions in Supabase
    return getActivitiesForDate(date);
  }

  /// Get month statistics
  Future<Map<String, int>> getMonthStatistics(DateTime month) async {
    try {
      final startOfMonth = DateTime(month.year, month.month);
      final endOfMonth = DateTime(month.year, month.month + 1);

      final stats = await _activityRepo.getActivityStatistics(
        startDate: startOfMonth,
        endDate: endOfMonth,
      );

      return {
        'total_work_seconds':
            (stats['total_duration'] as Duration?)?.inSeconds ?? 0,
        'total_activities': stats['total_activities'] as int? ?? 0,
      };
    } catch (e) {
      debugPrint('[WEB] Error getting month statistics: $e');
      return {'total_work_seconds': 0, 'total_activities': 0};
    }
  }

  /// Get day statistics
  Future<Map<String, dynamic>> getDayStatistics(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final stats = await _activityRepo.getActivityStatistics(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      final breakdown = await _activityRepo.getActivityBreakdown(
        startDate: startOfDay,
        endDate: endOfDay,
      );

      return {
        'total_activities': stats['total_activities'] ?? 0,
        'total_work_seconds':
            (breakdown[ActivityType.work] ?? Duration.zero).inSeconds,
        'total_break_seconds':
            (breakdown[ActivityType.break_] ?? Duration.zero).inSeconds,
        'total_idle_seconds':
            (breakdown[ActivityType.idle] ?? Duration.zero).inSeconds,
        'unique_apps': stats['unique_apps'] ?? 0,
        'most_used_app': stats['most_used_app'],
      };
    } catch (e) {
      debugPrint('[WEB] Error getting day statistics: $e');
      return {
        'total_activities': 0,
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'total_idle_seconds': 0,
        'unique_apps': 0,
        'most_used_app': null,
      };
    }
  }

  /// Helper to parse UUID string to int (compatibility layer)
  /// For web, we'll use hashCode of the UUID string
  int _parseIntId(String uuid) {
    return uuid.hashCode.abs();
  }

  /// Get daily activity - NOT IMPLEMENTED on web
  @override
  Future<DailyActivity> getDailyActivity(DateTime date) async {
    final activities = await getActivitiesForDate(date);
    return DailyActivity(date: date, activities: activities);
  }

  /// Get last activity
  @override
  Future<AppActivity?> getLastActivity() async {
    try {
      final activities = await _activityRepo.getTodayActivities();
      if (activities.isEmpty) return null;

      final lastActivity = activities.last;
      return AppActivity(
        id: _parseIntId(lastActivity.id),
        sessionId: lastActivity.sessionId, // Keep as String (UUID)
        appName: lastActivity.appName,
        windowTitle: lastActivity.windowTitle,
        startTime: lastActivity.startTimeUtc.toLocal(),
        endTime: lastActivity.endTimeUtc?.toLocal(),
        durationSeconds: lastActivity.durationSeconds,
        activityType: lastActivity.activityType.name,
      );
    } catch (e) {
      debugPrint('[WEB] Error getting last activity: $e');
      return null;
    }
  }

  /// Get current activity - returns null on web (read-only)
  @override
  Future<AppActivity?> getCurrentActivity() async {
    // Web doesn't support active activity tracking
    return null;
  }

  /// Get active activity for window - NOT SUPPORTED on web
  @override
  Future<AppActivity?> getActiveActivityForWindow(
    String appName,
    String? windowTitle,
    dynamic sessionId,
  ) async {
    // Web doesn't support active activity tracking
    return null;
  }

  /// Get app usage for date
  @override
  Future<Map<String, Duration>> getAppUsageForDate(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      return await _activityRepo.getAppUsageSummary(
        startDate: startOfDay,
        endDate: endOfDay,
      );
    } catch (e) {
      debugPrint('[WEB] Error getting app usage for date: $e');
      return {};
    }
  }

  /// Get app usage for date range
  @override
  Future<Map<String, Duration>> getAppUsageForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      return await _activityRepo.getAppUsageSummary(
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      debugPrint('[WEB] Error getting app usage for date range: $e');
      return {};
    }
  }

  /// Delete activities by session - NOT SUPPORTED on web
  @override
  Future<void> deleteActivitiesBySession(int sessionId) async {
    throw UnsupportedError(
      'Deleting activities from web is not supported. Use desktop app.',
    );
  }

  /// Delete all activities - NOT SUPPORTED on web
  @override
  Future<void> deleteAllActivities() async {
    throw UnsupportedError(
      'Deleting activities from web is not supported. Use desktop app.',
    );
  }

  /// Closing orphaned open activities is the desktop tracker's job (it owns
  /// the local database); the portal only reads.
  @override
  Future<void> closeStaleActivities() async {}

  /// Only used while tracking, which the web portal never does.
  @override
  Future<DateTime?> getLatestActivityTime(dynamic sessionId) async => null;

  /// Soft delete - NOT SUPPORTED on web
  @override
  Future<void> softDeleteActivity(int activityId) async {
    throw UnsupportedError(
      'Deleting activities from web is not supported. Use desktop app.',
    );
  }

  /// Delete activities in a time range - NOT SUPPORTED on web
  @override
  Future<List<int>> deleteActivitiesInTimeRange(
    dynamic sessionId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    throw UnsupportedError(
      'Deleting activities from web is not supported. Use desktop app.',
    );
  }

  /// Get activities by hour
  @override
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
}
