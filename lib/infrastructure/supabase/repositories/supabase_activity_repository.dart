import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/activity_model.dart';
import '../../../core/repositories/activity_repository.dart';

/// Supabase implementation of ActivityRepository
/// Used by WEB platform for read-only access to activity data
class SupabaseActivityRepository implements ActivityRepository {
  final SupabaseClient _supabase;

  SupabaseActivityRepository(this._supabase);

  String? get currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<List<ActivityModel>> getActivitiesInRange({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      debugPrint(
        '[SUPABASE_ACTIVITY] ========================================',
      );
      debugPrint('[SUPABASE_ACTIVITY] getActivitiesInRange called');
      debugPrint(
        '[SUPABASE_ACTIVITY] Start: $startDate (UTC: ${startDate.toUtc()})',
      );
      debugPrint('[SUPABASE_ACTIVITY] End: $endDate (UTC: ${endDate.toUtc()})');

      var query = _supabase
          .from('app_activities')
          .select()
          .gte('start_time_utc', startDate.toUtc().toIso8601String())
          .lt('start_time_utc', endDate.toUtc().toIso8601String())
          .eq('is_deleted', false);

      // If userId is provided, filter by it. Otherwise filter by current user.
      final targetUserId = userId ?? currentUserId;
      debugPrint('[SUPABASE_ACTIVITY] Filter User ID: $targetUserId');

      if (targetUserId != null) {
        query = query.eq('user_id', targetUserId);
      }

      // ATTEMPT 1: Standard query
      var response = await query.order('start_time_utc', ascending: false);
      var resultList = response as List;
      debugPrint(
        '[SUPABASE_ACTIVITY] Standard query returned ${resultList.length} activities',
      );

      // ATTEMPT 2: Fallback - Ignore user_id if valid ID was used but no results found
      if (resultList.isEmpty && targetUserId != null) {
        debugPrint(
          '[SUPABASE_ACTIVITY] Standard query empty. Trying Fallback (Ignore user_id)...',
        );
        final fallbackQuery = _supabase
            .from('app_activities')
            .select()
            .gte('start_time_utc', startDate.toUtc().toIso8601String())
            .lt('start_time_utc', endDate.toUtc().toIso8601String())
            .eq('is_deleted', false);

        response = await fallbackQuery.order(
          'start_time_utc',
          ascending: false,
        );
        resultList = response as List;

        if (resultList.isNotEmpty) {
          debugPrint(
            '[SUPABASE_ACTIVITY] Fallback SUCCEEDED! Found ${resultList.length} activities.',
          );
          debugPrint(
            '[SUPABASE_ACTIVITY] WARNING: User ID mismatch detected for range parameters.',
          );
        }
      }

      final activities = resultList
          .map((json) {
            try {
              return ActivityModel.fromJson(json);
            } catch (e) {
              debugPrint(
                '[SUPABASE_ACTIVITY] Error parsing activity in range: $e',
              );
              return null;
            }
          })
          .whereType<ActivityModel>()
          .toList();

      debugPrint(
        '[SUPABASE_ACTIVITY] Successfully returned ${activities.length} activities (Range)',
      );
      debugPrint(
        '[SUPABASE_ACTIVITY] ========================================',
      );

      return activities;
    } catch (e, stackTrace) {
      debugPrint('[SUPABASE_ACTIVITY] Error fetching activities in range: $e');
      debugPrint('[SUPABASE_ACTIVITY] Stack: $stackTrace');
      // Return empty list instead of rethrowing to prevent UI crashes
      return [];
    }
  }

  @override
  Future<List<ActivityModel>> getActivitiesForSession(String sessionId) async {
    try {
      // Validate user is authenticated
      if (currentUserId == null) {
        debugPrint('[SUPABASE_ACTIVITY] ERROR: User not authenticated!');
        return [];
      }

      // Validate session ID is not empty
      if (sessionId.isEmpty) {
        debugPrint('[SUPABASE_ACTIVITY] ERROR: Session ID is empty!');
        return [];
      }

      var query = _supabase
          .from('app_activities')
          .select()
          .eq('session_id', sessionId)
          .eq('user_id', currentUserId!)
          .eq('is_deleted', false);

      // ATTEMPT 1: Standard query with all filters
      var response = await query.order('start_time_utc', ascending: true);
      var resultList = response as List;

      // ATTEMPT 2: Fallback - Ignore user_id (rely on RLS)
      if (resultList.isEmpty) {
        final fallbackQuery1 = _supabase
            .from('app_activities')
            .select()
            .eq('session_id', sessionId)
            .eq('is_deleted', false);

        response = await fallbackQuery1.order(
          'start_time_utc',
          ascending: true,
        );
        resultList = response as List;

        if (resultList.isNotEmpty) {
          debugPrint(
            '[SUPABASE_ACTIVITY] WARNING: User ID mismatch - found ${resultList.length} activities without user_id filter',
          );
        }
      }

      // ATTEMPT 3: Fallback - Check for soft-deleted records
      if (resultList.isEmpty) {
        final fallbackQuery2 = _supabase
            .from('app_activities')
            .select()
            .eq('session_id', sessionId);

        response = await fallbackQuery2.order(
          'start_time_utc',
          ascending: true,
        );
        resultList = response as List;

        if (resultList.isNotEmpty) {
          // Filter to only active records
          final activeCount = resultList
              .where((item) => item['is_deleted'] != true)
              .length;

          if (activeCount > 0) {
            resultList = resultList
                .where((item) => item['is_deleted'] != true)
                .toList();
            debugPrint(
              '[SUPABASE_ACTIVITY] Found $activeCount active activities (ignoring is_deleted filter)',
            );
          } else {
            return [];
          }
        }
      }

      if (resultList.isEmpty) {
        debugPrint(
          '[SUPABASE_ACTIVITY] No activities found for session: $sessionId',
        );
        return [];
      }

      final activities = resultList
          .map((json) {
            try {
              return ActivityModel.fromJson(json);
            } catch (e) {
              debugPrint('[SUPABASE_ACTIVITY] Error parsing activity: $e');
              return null;
            }
          })
          .whereType<ActivityModel>()
          .toList();

      if (activities.isNotEmpty) {
        final totalDuration = activities.fold<int>(
          0,
          (sum, a) => sum + (a.durationSeconds ?? 0),
        );
        debugPrint(
          '[SUPABASE_ACTIVITY] Loaded ${activities.length} activities for session $sessionId (${(totalDuration / 60).toStringAsFixed(1)}m total)',
        );
      }

      return activities;
    } catch (e) {
      debugPrint(
        '[SUPABASE_ACTIVITY] ERROR fetching activities for session $sessionId: $e',
      );
      return [];
    }
  }

  @override
  Future<List<ActivityModel>> getTodayActivities() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    return getActivitiesInRange(startDate: todayStart, endDate: todayEnd);
  }

  @override
  Future<ActivityModel> createActivity(ActivityModel activity) async {
    // Web platform should NOT create activities - this is desktop only
    throw UnsupportedError(
      'Creating activities from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<void> updateActivity(ActivityModel activity) async {
    // Web platform should NOT update activities - this is desktop only
    throw UnsupportedError(
      'Updating activities from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<void> endActivity(
    String activityId, {
    required DateTime endTime,
  }) async {
    // Web platform should NOT end activities - this is desktop only
    throw UnsupportedError(
      'Ending activities from web is not supported. Use desktop app.',
    );
  }

  @override
  Future<Map<String, Duration>> getAppUsageSummary({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      final activities = await getActivitiesInRange(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
      );

      final Map<String, Duration> usage = {};
      for (final activity in activities) {
        final appName = activity.appName;
        usage[appName] = (usage[appName] ?? Duration.zero) + activity.duration;
      }

      return usage;
    } catch (e) {
      debugPrint('[SUPABASE] Error getting app usage summary: $e');
      rethrow;
    }
  }

  @override
  Future<List<MapEntry<String, Duration>>> getTopApps({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 10,
    String? userId,
  }) async {
    try {
      final usage = await getAppUsageSummary(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
      );

      final sorted = usage.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sorted.take(limit).toList();
    } catch (e) {
      debugPrint('[SUPABASE] Error getting top apps: $e');
      rethrow;
    }
  }

  @override
  Future<Map<ActivityType, Duration>> getActivityBreakdown({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      final activities = await getActivitiesInRange(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
      );

      final Map<ActivityType, Duration> breakdown = {
        ActivityType.work: Duration.zero,
        ActivityType.break_: Duration.zero,
        ActivityType.idle: Duration.zero,
      };

      for (final activity in activities) {
        breakdown[activity.activityType] =
            (breakdown[activity.activityType] ?? Duration.zero) +
            activity.duration;
      }

      return breakdown;
    } catch (e) {
      debugPrint('[SUPABASE] Error getting activity breakdown: $e');
      rethrow;
    }
  }

  @override
  Stream<List<ActivityModel>>? watchActivities({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Real-time subscription for live activity updates
    final userId = currentUserId;
    if (userId == null) return null;

    return _supabase.from('app_activities').stream(primaryKey: ['id']).map((
      data,
    ) {
      // Filter data in memory since stream doesn't support .eq()
      return data
          .where(
            (json) => json['user_id'] == userId && json['is_deleted'] == false,
          )
          .map((json) => ActivityModel.fromJson(json))
          .toList();
    });
  }

  /// Get hourly activity breakdown for timeline visualization
  Future<Map<int, Duration>> getHourlyActivityBreakdown({
    required DateTime date,
    String? userId,
  }) async {
    try {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final activities = await getActivitiesInRange(
        startDate: dayStart,
        endDate: dayEnd,
        userId: userId,
      );

      // Initialize all hours with zero duration
      final Map<int, Duration> hourlyBreakdown = {};
      for (int hour = 0; hour < 24; hour++) {
        hourlyBreakdown[hour] = Duration.zero;
      }

      // Aggregate activities by hour
      for (final activity in activities) {
        final hour = activity.startTime.hour;
        hourlyBreakdown[hour] =
            (hourlyBreakdown[hour] ?? Duration.zero) + activity.duration;
      }

      return hourlyBreakdown;
    } catch (e) {
      debugPrint('[SUPABASE] Error getting hourly breakdown: $e');
      rethrow;
    }
  }

  /// Get activity statistics for a date range
  @override
  Future<Map<String, dynamic>> getActivityStatistics({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      final activities = await getActivitiesInRange(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
      );

      if (activities.isEmpty) {
        return {
          'total_activities': 0,
          'total_duration': Duration.zero,
          'average_duration': Duration.zero,
          'unique_apps': 0,
          'most_used_app': null,
        };
      }

      final totalDuration = activities.fold<Duration>(
        Duration.zero,
        (sum, activity) => sum + activity.duration,
      );

      final averageDuration = Duration(
        microseconds: totalDuration.inMicroseconds ~/ activities.length,
      );

      final uniqueApps = activities.map((a) => a.appName).toSet();

      final appUsage = await getAppUsageSummary(
        startDate: startDate,
        endDate: endDate,
        userId: userId,
      );

      final mostUsedApp = appUsage.entries.isEmpty
          ? null
          : appUsage.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      return {
        'total_activities': activities.length,
        'total_duration': totalDuration,
        'average_duration': averageDuration,
        'unique_apps': uniqueApps.length,
        'most_used_app': mostUsedApp,
      };
    } catch (e) {
      debugPrint('[SUPABASE] Error getting activity statistics: $e');
      rethrow;
    }
  }
}
