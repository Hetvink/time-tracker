import 'package:flutter/foundation.dart';

/// Shell destinations. The desktop tracker only uses [dashboard] and
/// [desktopSettings].
abstract final class NavIndex {
  static const dashboard = 0;
  static const activity = 1;
  static const timesheet = 2;
  static const settings = 4;
  static const team = 5;
  static const platformAdmin = 6;

  static const desktopSettings = 2;
}

class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = NavIndex.dashboard;
  bool _isCollapsed = false;
  String? _userId;

  int get selectedIndex => _selectedIndex;
  bool get isCollapsed => _isCollapsed;

  void selectIndex(int index) {
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  /// Back to the dashboard.
  void reset() => selectIndex(NavIndex.dashboard);

  /// Every new session starts on the dashboard. Called from a
  /// ChangeNotifierProxyProvider during build, so it must not notify.
  void onUserChanged(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _selectedIndex = NavIndex.dashboard;
  }

  void toggleSidebar() {
    _isCollapsed = !_isCollapsed;
    notifyListeners();
  }
}
