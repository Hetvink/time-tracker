import 'package:flutter/foundation.dart';
import '../../data/models/daily_timesheet.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import 'timesheet_provider.dart';

class HistoryPageProvider extends ChangeNotifier {
  final TimeSheetProvider? _timesheetProvider;

  final Map<String, bool> _isExpanded = {};
  final Map<String, List<DailyTimeSheet>> _monthlyTimesheets = {};
  final Map<String, bool> _monthlyLoading = {};
  List<DailyTimeSheet> _timeSheets = [];
  bool _isLoading = false;

  HistoryPageProvider([this._timesheetProvider]);

  Map<String, bool> get isExpanded => _isExpanded;
  List<DailyTimeSheet> get timeSheets => _timeSheets;
  bool get isLoading => _isLoading;

  String _getKey(int year, int month) => '$year-$month';

  bool isMonthExpanded(String key) => _isExpanded[key] ?? false;
  bool isMonthLoading(int year, int month) =>
      _monthlyLoading[_getKey(year, month)] ?? false;
  List<DailyTimeSheet>? getMonthTimesheets(int year, int month) =>
      _monthlyTimesheets[_getKey(year, month)];

  void setMonthExpanded(int year, int month, bool expanded) {
    _isExpanded[_getKey(year, month)] = expanded;
    notifyListeners();
  }

  Future<void> fetchMonthData(
    int year,
    int month,
    AttendanceProvider attendanceProvider,
  ) async {
    final key = _getKey(year, month);
    if (_monthlyTimesheets.containsKey(key)) return;

    _monthlyLoading[key] = true;
    notifyListeners();

    try {
      final data = await attendanceProvider.getMonthlyDailyTimeSheets(
        year,
        month,
      );
      _monthlyTimesheets[key] = data;
    } catch (e) {
      debugPrint('Error fetching month data for $key: $e');
    } finally {
      _monthlyLoading[key] = false;
      notifyListeners();
    }
  }

  void toggleMonth(String monthKey) {
    _isExpanded[monthKey] = !(_isExpanded[monthKey] ?? false);
    notifyListeners();
  }

  Future<void> loadTimesheets() async {
    if (_timesheetProvider == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 3);
      final endDate = now;

      final loadedTimeSheets = <DailyTimeSheet>[];
      for (
        var date = startDate;
        date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
        date = date.add(const Duration(days: 1))
      ) {
        final timeSheet = await _timesheetProvider.getTimesheetForDate(date);
        if (timeSheet.sessions.isNotEmpty) {
          loadedTimeSheets.add(timeSheet);
        }
      }

      _timeSheets = loadedTimeSheets;
    } catch (e) {
      debugPrint('Error loading timesheets: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadTimesheets();
  }
}
