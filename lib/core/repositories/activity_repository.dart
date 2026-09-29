import '../models/activity_model.dart';

/// Abstract repository for Activity operations
/// Implementations:
/// - Desktop: LocalActivityRepository (SQLite + sync to Supabase)
/// - Web: SupabaseActivityRepository (read-only from Supabase)
abstract class ActivityRepository {
  /// Get activities within a date range
  Future<List<ActivityModel>> getActivitiesInRange({
    required DateTime startDate,
    required DateTime endDate,
    String? userId, // For admin viewing other users
  });

  /// Get activities for a specific session
  Future<List<ActivityModel>> getActivitiesForSession(String sessionId);

  /// Get today's activities
  Future<List<ActivityModel>> getTodayActivities();

  /// Create a new activity (desktop only)
  Future<ActivityModel> createActivity(ActivityModel activity);

  /// Update an existing activity (desktop only)
  Future<void> updateActivity(ActivityModel activity);

  /// End an active activity (desktop only)
  Future<void> endActivity(String activityId, {required DateTime endTime});

  /// Get app usage summary for a date range
  /// Returns map of app name to total duration
  Future<Map<String, Duration>> getAppUsageSummary({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  });

  /// Get top N apps by usage duration
  Future<List<MapEntry<String, Duration>>> getTopApps({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 10,
    String? userId,
  });

  /// Get activity breakdown by type (work, break, idle)
  Future<Map<ActivityType, Duration>> getActivityBreakdown({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  });

  /// Stream of activity updates (for real-time dashboard)
  Stream<List<ActivityModel>>? watchActivities({
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Get activity statistics for a date range
  /// Returns total activities, unique apps, most used app, total duration, etc.
  Future<Map<String, dynamic>> getActivityStatistics({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  });
}
