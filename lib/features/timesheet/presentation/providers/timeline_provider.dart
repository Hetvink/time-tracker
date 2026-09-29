import 'package:flutter/foundation.dart';
import '../../data/models/daily_timesheet.dart';
import 'timesheet_provider.dart';

class TimelineProvider extends ChangeNotifier {
  final TimeSheetProvider _timesheetProvider;

  List<AttendanceSession> _sessions = [];
  bool _isLoading = false;

  TimelineProvider(this._timesheetProvider);

  List<AttendanceSession> get sessions => _sessions;
  bool get isLoading => _isLoading;

  Future<void> loadTimelineForDate(DateTime date) async {
    _isLoading = true;
    notifyListeners();

    try {
      final timesheet = await _timesheetProvider.getTimesheetForDate(date);
      _sessions = timesheet.sessions;
    } catch (e) {
      debugPrint('Error loading timeline: $e');
      _sessions = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _sessions = [];
    notifyListeners();
  }
}
