import '../../data/models/app_activity.dart';

abstract class IAppActivityRepository {
  Future<void> recordActivity(AppActivity activity);
  Future<List<AppActivity>> getActivitiesForSession(String sessionId);
  Future<List<AppActivity>> getActivitiesForDateRange(
    DateTime start,
    DateTime end,
  );
}
