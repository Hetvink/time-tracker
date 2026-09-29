import 'package:flutter/foundation.dart';

/// Stub crash reporting service — Firebase Crashlytics has been removed.
/// All methods are no-ops to allow a smooth transition without breaking
/// any code that still references this service.
class CrashReportingService {
  static final CrashReportingService _instance =
      CrashReportingService._internal();
  factory CrashReportingService() => _instance;
  CrashReportingService._internal();

  bool get isSupported => false;
  bool get isInitialized => true;

  Future<bool> initialize() async {
    debugPrint(
      '[CrashReporting] Crashlytics removed — crash reporting disabled',
    );
    return false;
  }

  Future<void> setUserIdentifier(String userId) async {}
  Future<void> setCustomKey(String key, dynamic value) async {}
  Future<void> log(String message) async {}
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    debugPrint('[CrashReporting] Error: $exception');
    if (stackTrace != null) {
      debugPrint('[CrashReporting] Stack trace: $stackTrace');
    }
  }

  Future<void> clearUserIdentifier() async {}
  Future<void> testCrash() async {
    debugPrint(
      '[CrashReporting] testCrash() called but Crashlytics is removed',
    );
  }
}
