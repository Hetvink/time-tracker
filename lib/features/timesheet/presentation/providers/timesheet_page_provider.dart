import 'package:flutter/foundation.dart';

class TimeSheetPageProvider extends ChangeNotifier {
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int _refreshKey = 0;

  DateTime get selectedDate => _selectedDate;
  int get selectedYear => _selectedYear;
  int get selectedMonth => _selectedMonth;
  int get refreshKey => _refreshKey;

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    _selectedYear = date.year;
    _selectedMonth = date.month;
    notifyListeners();
  }

  void setSelectedYearMonth(int year, int month) {
    _selectedYear = year;
    _selectedMonth = month;
    _selectedDate = DateTime(year, month);
    notifyListeners();
  }

  void selectToday() {
    _selectedDate = DateTime.now();
    _selectedYear = _selectedDate.year;
    _selectedMonth = _selectedDate.month;
    notifyListeners();
  }

  void refresh() {
    _refreshKey++;
    notifyListeners();
  }
}
