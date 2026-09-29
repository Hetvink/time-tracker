import '../../data/models/attendance_state.dart';
import '../../../timesheet/data/models/daily_timesheet.dart';

abstract class IAttendanceRepository {
  Future<void> saveCheckIn({
    required DateTime time,
    String? note,
    String? location,
  });
  Future<void> saveCheckOut({required DateTime time, String? note});
  Future<void> saveBreakStart({required DateTime time, String? note});
  Future<void> saveBreakEnd({required DateTime time});
  Future<AttendanceState> getCurrentState();
  Future<DailyTimeSheet> getTimesheetForDate(DateTime date);
  Future<List<Map<String, dynamic>>> getSessionsForDate(DateTime date);
  void setCurrentUserId(String? userId);
}
