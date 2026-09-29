import 'package:flutter/foundation.dart';
import 'package:time_trak/features/admin/data/repository/admin_repository.dart';

enum AdminViewTab { day, month, overview, monthlySummary }

class AdminDashboardProvider extends ChangeNotifier {
  AdminViewTab _currentTab = AdminViewTab.day;
  DateTime _selectedDate = DateTime.now();
  String? _selectedUserId;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int _refreshKey = 0;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String? _sortColumn;
  bool _sortAscending = true;

  AdminViewTab get currentTab => _currentTab;
  DateTime get selectedDate => _selectedDate;
  String? get selectedUserId => _selectedUserId;
  int get selectedYear => _selectedYear;
  int get selectedMonth => _selectedMonth;
  int get refreshKey => _refreshKey;

  List<Map<String, dynamic>> get users => _users;
  List<Map<String, dynamic>> get filteredUsers => _filteredUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  String? get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  void setTab(AdminViewTab tab) {
    _currentTab = tab;
    notifyListeners();
  }

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

  void setSelectedUserId(String? userId) {
    _selectedUserId = userId;
    notifyListeners();
  }

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? get userProfile => _userProfile;

  Future<void> loadUserProfile(
    AdminRepository repository,
    String userId,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _userProfile = await repository.getUserById(userId);
      _isLoading = false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> loadUsers(AdminRepository repository) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _users = await repository.getAllUsers();
      _applyFilters();
      _isLoading = false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void sortByColumn(String column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    var filtered = _users.where((user) {
      final email = (user['email'] as String? ?? '').toLowerCase();
      final name = (user['name'] as String? ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return email.contains(query) || name.contains(query);
    }).toList();

    if (_sortColumn != null) {
      filtered.sort((a, b) {
        dynamic aVal = a[_sortColumn!] ?? '';
        dynamic bVal = b[_sortColumn!] ?? '';
        final cmp = aVal.toString().compareTo(bVal.toString());
        return _sortAscending ? cmp : -cmp;
      });
    }

    _filteredUsers = filtered;
  }

  void refreshData() {
    _refreshKey++;
    notifyListeners();
  }
}
