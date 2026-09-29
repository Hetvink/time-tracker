import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _autoStartKey = 'auto_start_enabled';
  static const String _autoCheckInKey = 'auto_check_in_enabled';
  static const String _autoCheckInOnBootOnlyKey = 'auto_check_in_on_boot_only';
  static const String _sleepThresholdMinutesKey = 'sleep_threshold_minutes';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs);
  }

  // Auto-start preferences
  bool get autoStartEnabled => _prefs.getBool(_autoStartKey) ?? false;

  Future<void> setAutoStartEnabled(bool enabled) async {
    await _prefs.setBool(_autoStartKey, enabled);
  }

  // Auto check-in preferences
  bool get autoCheckInEnabled => _prefs.getBool(_autoCheckInKey) ?? true;

  Future<void> setAutoCheckInEnabled(bool enabled) async {
    await _prefs.setBool(_autoCheckInKey, enabled);
  }

  // Auto check-in on boot only (vs every launch)
  bool get autoCheckInOnBootOnly =>
      _prefs.getBool(_autoCheckInOnBootOnlyKey) ?? true;

  Future<void> setAutoCheckInOnBootOnly(bool onBootOnly) async {
    await _prefs.setBool(_autoCheckInOnBootOnlyKey, onBootOnly);
  }

  // Sleep threshold for break confirmation dialog (in minutes)
  int get sleepThresholdMinutes =>
      _prefs.getInt(_sleepThresholdMinutesKey) ?? 15;

  Future<void> setSleepThresholdMinutes(int minutes) async {
    await _prefs.setInt(_sleepThresholdMinutesKey, minutes);
  }

  // Get threshold in seconds for platform code
  int get sleepThresholdSeconds => sleepThresholdMinutes * 60;

  // Daily Work Goal (in minutes), default 8 hours (480 min)
  static const String _dailyGoalMinutesKey = 'daily_goal_minutes';

  int get dailyGoalMinutes => _prefs.getInt(_dailyGoalMinutesKey) ?? 480;

  Future<void> setDailyGoalMinutes(int minutes) async {
    await _prefs.setInt(_dailyGoalMinutesKey, minutes);
  }

  // Activity Tracking preferences
  static const String _activityTrackingEnabledKey = 'activity_tracking_enabled';
  static const String _trackingIntervalSecondsKey = 'tracking_interval_seconds';
  static const String _hasShownAccessibilityAlertKey =
      'has_shown_accessibility_alert';

  bool get activityTrackingEnabled =>
      _prefs.getBool(_activityTrackingEnabledKey) ?? true;

  Future<void> setActivityTrackingEnabled(bool enabled) async {
    await _prefs.setBool(_activityTrackingEnabledKey, enabled);
  }

  int get trackingIntervalSeconds =>
      _prefs.getInt(_trackingIntervalSecondsKey) ?? 60;

  Future<void> setTrackingIntervalSeconds(int seconds) async {
    await _prefs.setInt(_trackingIntervalSecondsKey, seconds);
  }

  bool get hasShownAccessibilityAlert =>
      _prefs.getBool(_hasShownAccessibilityAlertKey) ?? false;

  Future<void> setHasShownAccessibilityAlert(bool shown) async {
    await _prefs.setBool(_hasShownAccessibilityAlertKey, shown);
  }
}
