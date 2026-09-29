import 'package:flutter/foundation.dart';

import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../../data/models/daily_timesheet.dart';

/// Selected month + its day-by-day timesheet (newest first).
class MonthlyTimesheetController extends ChangeNotifier {
  final AttendanceProvider attendance;

  MonthlyTimesheetController(this.attendance) {
    _load();
  }

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<DailyTimeSheet>? _days;
  Object? _error;
  bool _loading = false;
  int _request = 0;
  bool _disposed = false;

  DateTime get month => _month;
  List<DailyTimeSheet>? get days => _days;
  Object? get error => _error;
  bool get isLoading => _loading;

  bool get isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void setMonth(DateTime month) {
    final m = DateTime(month.year, month.month);
    if (m == _month) return;
    _month = m;
    _days = null;
    _load();
  }

  void shift(int months) =>
      setMonth(DateTime(_month.year, _month.month + months));
  void currentMonth() => setMonth(DateTime.now());

  Future<void> refresh() => _load(refresh: true);

  Future<void> _load({bool refresh = false}) async {
    final request = ++_request;
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await attendance.getMonthlyDailyTimeSheets(
        _month.year,
        _month.month,
        refresh: refresh,
      );
      if (request != _request) return;
      _days = [...result]..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      if (request == _request) _error = e;
    } finally {
      if (request == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
