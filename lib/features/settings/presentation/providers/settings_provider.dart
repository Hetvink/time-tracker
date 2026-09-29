import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _autoStartEnabled = false;
  bool _autoCheckInEnabled = false;
  bool _autoCheckInOnBootOnly = true;
  int _sleepThresholdMinutes = 30;
  int _dailyGoalMinutes = 480;
  bool _activityTrackingEnabled = true;
  int _trackingIntervalSeconds = 60;
  bool _accessibilityPermissionGranted = false;

  bool get isLoading => _isLoading;
  bool get autoStartEnabled => _autoStartEnabled;
  bool get autoCheckInEnabled => _autoCheckInEnabled;
  bool get autoCheckInOnBootOnly => _autoCheckInOnBootOnly;
  int get sleepThresholdMinutes => _sleepThresholdMinutes;
  int get dailyGoalMinutes => _dailyGoalMinutes;
  bool get activityTrackingEnabled => _activityTrackingEnabled;
  int get trackingIntervalSeconds => _trackingIntervalSeconds;
  bool get accessibilityPermissionGranted => _accessibilityPermissionGranted;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _autoStartEnabled = prefs.getBool('autoStartEnabled') ?? false;
      _autoCheckInEnabled = prefs.getBool('autoCheckInEnabled') ?? false;
      _autoCheckInOnBootOnly = prefs.getBool('autoCheckInOnBootOnly') ?? true;
      _sleepThresholdMinutes = prefs.getInt('sleepThresholdMinutes') ?? 30;
      _dailyGoalMinutes = prefs.getInt('dailyGoalMinutes') ?? 480;
      _activityTrackingEnabled =
          prefs.getBool('activityTrackingEnabled') ?? true;
      _trackingIntervalSeconds = prefs.getInt('trackingIntervalSeconds') ?? 60;
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setAutoStartEnabled(bool value) async {
    _autoStartEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoStartEnabled', value);
  }

  Future<void> setAutoCheckInEnabled(bool value) async {
    _autoCheckInEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoCheckInEnabled', value);
  }

  Future<void> setAutoCheckInOnBootOnly(bool value) async {
    _autoCheckInOnBootOnly = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoCheckInOnBootOnly', value);
  }

  void setAutoStartEnabledSync(bool value) {
    _autoStartEnabled = value;
    notifyListeners();
  }

  Future<void> setSleepThresholdMinutes(int value) async {
    _sleepThresholdMinutes = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sleepThresholdMinutes', value);
  }

  Future<void> setDailyGoalMinutes(int value) async {
    _dailyGoalMinutes = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dailyGoalMinutes', value);
  }

  Future<void> setActivityTrackingEnabled(bool value) async {
    _activityTrackingEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('activityTrackingEnabled', value);
  }

  Future<void> setTrackingIntervalSeconds(int value) async {
    _trackingIntervalSeconds = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('trackingIntervalSeconds', value);
  }

  void setAccessibilityPermissionGranted(bool value) {
    _accessibilityPermissionGranted = value;
    notifyListeners();
  }
}
