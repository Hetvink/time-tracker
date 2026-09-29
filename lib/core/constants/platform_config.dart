import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'dart:io' show Platform;

/// Platform configuration and feature flags
/// Determines which features are available on each platform
class PlatformConfig {
  // Platform detection
  static bool get isWeb => kIsWeb;
  static bool get isDesktop => !kIsWeb && (isMacOS || isWindows);
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Desktop builds run the background tracker.
  static bool get isTracker => !kIsWeb && (isMacOS || isWindows || isLinux);

  /// Web and mobile run the read-only portal (reports, team, admin).
  static bool get isPortal => !isTracker;

  // Feature flags - Desktop only features (actual tracking)
  static bool get hasActivityTracking => isDesktop;
  static bool get hasBackgroundTracking => isDesktop;
  static bool get hasPlatformChannels => isDesktop;
  static bool get hasSystemTray => isDesktop;

  // Feature flags - UI features (available on all platforms)
  static bool get hasDashboard => true;
  static bool get hasTimesheet => true;
  static bool get hasActivityView => true;
  static bool get hasAnalytics => true;

  // Feature flags - Web-specific admin features
  static bool get hasAdminPanel => isWeb;

  // Data storage strategy
  /// Local database is ONLY for desktop runtime cache
  /// It stores current session data temporarily and syncs to Supabase
  static bool get useLocalDatabase => isDesktop;

  /// Supabase is the single source of truth for all platforms
  static bool get useSupabase => true;

  // Sync configuration
  static Duration get syncInterval => const Duration(minutes: 5);
  static int get maxSyncRetries => 5;
  static Duration get syncTimeout => const Duration(seconds: 30);

  // Platform display names
  static String get platformName {
    if (isWeb) return 'Web';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    if (!kIsWeb && Platform.isAndroid) return 'Android';
    if (!kIsWeb && Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  // Debug helpers
  static void printPlatformInfo() {
    if (kDebugMode) {
      debugPrint('=== Platform Configuration ===');
      debugPrint('Platform: $platformName');
      debugPrint('Is Web: $isWeb');
      debugPrint('Is Desktop: $isDesktop');
      debugPrint('Has Activity Tracking: $hasActivityTracking');
      debugPrint('Has Dashboard: $hasDashboard');
      debugPrint('Use Local Database: $useLocalDatabase');
      debugPrint('Use Supabase: $useSupabase');
      debugPrint('=============================');
    }
  }
}
