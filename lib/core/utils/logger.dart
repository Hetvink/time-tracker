// Logs must reach device logs in release builds too.
// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

/// Universal logging utility that works in both debug and production modes
///
/// In debug mode: Uses debugPrint with detailed formatting
/// In production mode: Uses print for essential logs (can be viewed in device logs)
///
/// Usage:
/// ```dart
/// Logger.info('User logged in', {'userId': '123', 'email': 'user@example.com'});
/// Logger.error('Failed to load data', error, stackTrace);
/// Logger.debug('Processing activity', {'activityId': '456'});
/// ```
class Logger {
  static const String _tag = '[TimeTrak]';

  /// Log info messages - always shown in both debug and production
  static void info(String message, [Map<String, dynamic>? context]) {
    _log('INFO', message, context: context);
  }

  /// Log error messages - always shown in both debug and production
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _log('ERROR', message, error: error, stackTrace: stackTrace);
  }

  /// Log warning messages - always shown in both debug and production
  static void warning(String message, [Map<String, dynamic>? context]) {
    _log('WARNING', message, context: context);
  }

  /// Log debug messages - only shown in debug mode
  static void debug(String message, [Map<String, dynamic>? context]) {
    if (kDebugMode) {
      _log('DEBUG', message, context: context);
    }
  }

  /// Log verbose messages - only shown in debug mode with extra detail
  static void verbose(String message, [Map<String, dynamic>? context]) {
    if (kDebugMode) {
      _log('VERBOSE', message, context: context);
    }
  }

  static void _log(
    String level,
    String message, {
    Map<String, dynamic>? context,
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();

    // Basic format: [TAG] [LEVEL] [TIMESTAMP] Message
    buffer.write('$_tag [$level] [$timestamp] $message');

    // Add context if provided
    if (context != null && context.isNotEmpty) {
      buffer.write(' | Context: $context');
    }

    // Add error if provided
    if (error != null) {
      buffer.write(' | Error: $error');
    }

    final logMessage = buffer.toString();

    // Use appropriate logging method based on build mode
    if (kDebugMode) {
      // In debug mode, use debugPrint for better formatting
      debugPrint(logMessage);

      // Also print stack trace for errors in debug mode
      if (stackTrace != null) {
        debugPrint('Stack Trace:\n$stackTrace');
      }
    } else {
      // In production mode, use print for essential logs
      // These will appear in device logs and crash reports
      if (level == 'ERROR' || level == 'WARNING' || level == 'INFO') {
        print(logMessage);

        // For errors, also print stack trace if available
        if (level == 'ERROR' && stackTrace != null) {
          print('Stack Trace:\n$stackTrace');
        }
      }
    }
  }
}

/// Convenience extension for logging with specific tags
extension LoggerExt on String {
  void logInfo([Map<String, dynamic>? context]) => Logger.info(this, context);
  void logError([dynamic error, StackTrace? stackTrace]) =>
      Logger.error(this, error, stackTrace);
  void logWarning([Map<String, dynamic>? context]) =>
      Logger.warning(this, context);
  void logDebug([Map<String, dynamic>? context]) => Logger.debug(this, context);
  void logVerbose([Map<String, dynamic>? context]) =>
      Logger.verbose(this, context);
}
