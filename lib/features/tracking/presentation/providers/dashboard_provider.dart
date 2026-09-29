import 'package:flutter/foundation.dart';

class DashboardProvider extends ChangeNotifier {
  bool _isRefreshing = false;
  int _refreshKey = 0;

  bool get isRefreshing => _isRefreshing;
  int get refreshKey => _refreshKey;

  void incrementRefreshKey() {
    _refreshKey++;
    notifyListeners();
  }

  void setRefreshing(bool value) {
    _isRefreshing = value;
    notifyListeners();
  }

  Future<void> refresh(Future<void> Function() refreshAction) async {
    if (_isRefreshing) return;

    _isRefreshing = true;
    notifyListeners();

    try {
      await refreshAction();
      _refreshKey++;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }
}
