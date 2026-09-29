import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:time_trak/core/constants/platform_config.dart';

enum SystemEventType { boot, shutdown, sleep, wake, midnight }

enum UserActionType { checkIn, checkOut, breakIn, breakOut }

class SystemEvent {
  final SystemEventType type;
  final DateTime timestamp;

  SystemEvent({required this.type, required this.timestamp});
}

class UserAction {
  final UserActionType type;
  final DateTime timestamp;

  UserAction({required this.type, required this.timestamp});
}

class LongSleepEvent {
  final Duration duration;
  final DateTime sleepStart;
  final DateTime wakeTime;

  LongSleepEvent({
    required this.duration,
    required this.sleepStart,
    required this.wakeTime,
  });
}

class BreakConfirmationEvent {
  final bool wasOnBreak;
  final DateTime sleepStart;
  final DateTime wakeTime;
  final String? note;

  BreakConfirmationEvent({
    required this.wasOnBreak,
    required this.sleepStart,
    required this.wakeTime,
    this.note,
  });
}

class ActivityChangeEvent {
  final String appName;
  final String? windowTitle;
  final String? bundleId;
  final DateTime timestamp;

  ActivityChangeEvent({
    required this.appName,
    this.windowTitle,
    this.bundleId,
    required this.timestamp,
  });
}

class RecoveryConfirmationEvent {
  final RecoveryAction action;
  final DateTime? customCheckoutTime;
  final DateTime checkInTime;

  RecoveryConfirmationEvent({
    required this.action,
    this.customCheckoutTime,
    required this.checkInTime,
  });
}

enum RecoveryAction { useLastSeen, customTime, closeAtEndOfDay }

class PlatformChannelService {
  static const _channel = MethodChannel('com.attendance.tracker/system');

  final _systemEventController = StreamController<SystemEvent>.broadcast();
  final _userActionController = StreamController<UserAction>.broadcast();
  final _longSleepController = StreamController<LongSleepEvent>.broadcast();
  final _breakConfirmationController =
      StreamController<BreakConfirmationEvent>.broadcast();
  final _activityChangeController =
      StreamController<ActivityChangeEvent>.broadcast();
  final _recoveryConfirmationController =
      StreamController<RecoveryConfirmationEvent>.broadcast();

  Stream<SystemEvent> get onSystemEvent => _systemEventController.stream;
  Stream<UserAction> get onUserAction => _userActionController.stream;
  Stream<LongSleepEvent> get onLongSleep => _longSleepController.stream;
  Stream<BreakConfirmationEvent> get onBreakConfirmation =>
      _breakConfirmationController.stream;
  Stream<ActivityChangeEvent> get onActivityChange =>
      _activityChangeController.stream;
  Stream<RecoveryConfirmationEvent> get onRecoveryConfirmation =>
      _recoveryConfirmationController.stream;

  PlatformChannelService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onSystemEvent':
          final args = call.arguments as Map<dynamic, dynamic>;
          final eventStr = args['event'] as String;

          // Check if this is a long sleep event
          if (eventStr == 'longSleep') {
            final duration = args['duration'] as double;
            final sleepStart = DateTime.parse(args['sleepStart'] as String);
            final wakeTime = DateTime.parse(args['wakeTime'] as String);

            _longSleepController.add(
              LongSleepEvent(
                duration: Duration(seconds: duration.toInt()),
                sleepStart: sleepStart,
                wakeTime: wakeTime,
              ),
            );
          } else {
            final eventType = _parseSystemEventType(eventStr);
            _systemEventController.add(
              SystemEvent(type: eventType, timestamp: DateTime.now()),
            );
          }
          break;

        case 'onUserAction':
          final args = call.arguments as Map<dynamic, dynamic>;
          final actionType = _parseUserActionType(args['action'] as String);
          _userActionController.add(
            UserAction(type: actionType, timestamp: DateTime.now()),
          );
          break;

        case 'onBreakConfirmation':
          try {
            debugPrint('=== PLATFORM: Break confirmation received ===');
            final args = call.arguments as Map<dynamic, dynamic>;
            final wasOnBreak = args['wasOnBreak'] as bool;

            // Parse ISO8601 timestamps (sent in local time from native)
            // DateTime.parse() handles ISO8601 format correctly
            final sleepStartStr = args['sleepStart'] as String;
            final wakeTimeStr = args['wakeTime'] as String;

            debugPrint(
              'Platform data: wasOnBreak=$wasOnBreak, sleepStart=$sleepStartStr, wakeTime=$wakeTimeStr',
            );

            // Parse as local time directly (native sends local time without UTC suffix)
            final sleepStart = DateTime.parse(sleepStartStr);
            final wakeTime = DateTime.parse(wakeTimeStr);

            // Get the optional note (for when user was working)
            final note = args['note'] as String?;

            debugPrint(
              'Parsed: sleepStart=$sleepStart, wakeTime=$wakeTime, note=$note',
            );

            _breakConfirmationController.add(
              BreakConfirmationEvent(
                wasOnBreak: wasOnBreak,
                sleepStart: sleepStart,
                wakeTime: wakeTime,
                note: note,
              ),
            );
            debugPrint('=== PLATFORM: Break confirmation event sent ===');
          } catch (e, stackTrace) {
            debugPrint('=== PLATFORM: Error in break confirmation ===');
            debugPrint('Error: $e');
            debugPrint('StackTrace: $stackTrace');
            debugPrint('Call arguments: ${call.arguments}');
          }
          break;

        case 'onActivityChange':
          final args = call.arguments as Map<dynamic, dynamic>;
          final appName = args['appName'] as String;
          final windowTitle = args['windowTitle'] as String?;
          final bundleId = args['bundleId'] as String?;
          final timestampStr = args['timestamp'] as String;

          final timestamp = DateTime.parse(timestampStr).toLocal();

          _activityChangeController.add(
            ActivityChangeEvent(
              appName: appName,
              windowTitle: windowTitle,
              bundleId: bundleId,
              timestamp: timestamp,
            ),
          );
          break;

        case 'onRecoveryConfirmation':
          final args = call.arguments as Map<dynamic, dynamic>;
          final actionStr = args['action'] as String;
          final checkInTimeStr = args['checkInTime'] as String;

          // Parse action
          RecoveryAction action;
          switch (actionStr) {
            case 'useLastSeen':
              action = RecoveryAction.useLastSeen;
              break;
            case 'customTime':
              action = RecoveryAction.customTime;
              break;
            case 'closeAtEndOfDay':
              action = RecoveryAction.closeAtEndOfDay;
              break;
            default:
              throw ArgumentError('Unknown recovery action: $actionStr');
          }

          // Parse times
          final checkInTime = DateTime.parse(checkInTimeStr).toLocal();
          DateTime? customCheckoutTime;
          if (args['customTime'] != null) {
            customCheckoutTime = DateTime.parse(
              args['customTime'] as String,
            ).toLocal();
          }

          _recoveryConfirmationController.add(
            RecoveryConfirmationEvent(
              action: action,
              customCheckoutTime: customCheckoutTime,
              checkInTime: checkInTime,
            ),
          );
          break;
      }
    } catch (e) {
      debugPrint('Error handling method call: $e');
    }
  }

  SystemEventType _parseSystemEventType(String event) {
    switch (event) {
      case 'boot':
        return SystemEventType.boot;
      case 'shutdown':
        return SystemEventType.shutdown;
      case 'sleep':
        return SystemEventType.sleep;
      case 'wake':
        return SystemEventType.wake;
      case 'midnight':
        return SystemEventType.midnight;
      default:
        throw ArgumentError('Unknown system event: $event');
    }
  }

  UserActionType _parseUserActionType(String action) {
    switch (action) {
      case 'checkIn':
        return UserActionType.checkIn;
      case 'checkOut':
        return UserActionType.checkOut;
      case 'breakIn':
        return UserActionType.breakIn;
      case 'breakOut':
        return UserActionType.breakOut;
      default:
        throw ArgumentError('Unknown user action: $action');
    }
  }

  Future<void> updateMenuBar(String status) async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('updateMenuBar', {'status': status});
    } catch (e) {
      debugPrint('Error updating menu bar: $e');
    }
  }

  Future<void> updateMenuItems(List<String> enabledItems) async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('updateMenuItems', {
        'enabledItems': enabledItems,
      });
    } catch (e) {
      debugPrint('Error updating menu items: $e');
    }
  }

  Future<bool> getAutoStartStatus() async {
    if (!PlatformConfig.isTracker) return false;
    try {
      final result = await _channel.invokeMethod<bool>('getAutoStartStatus');
      return result ?? false;
    } catch (e) {
      debugPrint('Error getting auto-start status: $e');
      return false;
    }
  }

  Future<bool> setAutoStart(bool enabled) async {
    if (!PlatformConfig.isTracker) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setAutoStart', {
        'enabled': enabled,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting auto-start: $e');
      return false;
    }
  }

  Future<void> openSystemPreferences() async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('openSystemPreferences');
    } catch (e) {
      debugPrint('Error opening system preferences: $e');
    }
  }

  Future<void> setSleepThreshold(int seconds) async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('setSleepThreshold', {'seconds': seconds});
    } catch (e) {
      debugPrint('Error setting sleep threshold: $e');
    }
  }

  Future<void> startActivityTracking() async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('startActivityTracking');
    } catch (e) {
      debugPrint('Error starting activity tracking: $e');
    }
  }

  Future<void> stopActivityTracking() async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('stopActivityTracking');
    } catch (e) {
      debugPrint('Error stopping activity tracking: $e');
    }
  }

  Future<Map<String, dynamic>?> getCurrentActivity() async {
    if (!PlatformConfig.isTracker) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getCurrentActivity',
      );
      if (result == null) return null;
      return {
        'appName': result['appName'] as String,
        'windowTitle': result['windowTitle'] as String?,
        'bundleId': result['bundleId'] as String?,
      };
    } catch (e) {
      debugPrint('Error getting current activity: $e');
      return null;
    }
  }

  Future<bool> getAccessibilityPermissionStatus() async {
    if (!PlatformConfig.isTracker) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'getAccessibilityPermissionStatus',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error getting accessibility permission status: $e');
      return false;
    }
  }

  Future<void> openAccessibilityPreferences() async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('openAccessibilityPreferences');
    } catch (e) {
      debugPrint('Error opening accessibility preferences: $e');
    }
  }

  Future<void> setTrackingInterval(int seconds) async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('setTrackingInterval', {'seconds': seconds});
    } catch (e) {
      debugPrint('Error setting tracking interval: $e');
    }
  }

  // Set authentication status to control native dialogs
  Future<void> setAuthenticationStatus(bool isAuthenticated) async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('setAuthenticationStatus', {
        'isAuthenticated': isAuthenticated,
      });
    } catch (e) {
      debugPrint('Error setting authentication status: $e');
    }
  }

  // Trigger boot event manually (for auto check-in after login)
  Future<void> triggerBootEvent() async {
    if (!PlatformConfig.isTracker) return;
    try {
      await _channel.invokeMethod('triggerBootEvent');
      debugPrint('[PLATFORM] Triggered boot event for auto check-in');
    } catch (e) {
      debugPrint('Error triggering boot event: $e');
    }
  }

  void dispose() {
    _systemEventController.close();
    _userActionController.close();
    _longSleepController.close();
    _breakConfirmationController.close();
    _activityChangeController.close();
    _recoveryConfirmationController.close();
  }

  /// Show recovery confirmation dialog for multi-day sessions
  Future<void> showRecoveryDialog({
    required DateTime checkInTime,
    DateTime? lastSeenTime,
    required int daysMissing,
  }) async {
    if (!PlatformConfig.isTracker) return;
    try {
      final args = <String, dynamic>{
        'checkInTime': checkInTime.toIso8601String(),
        'daysMissing': daysMissing,
      };
      if (lastSeenTime != null) {
        args['lastSeenTime'] = lastSeenTime.toIso8601String();
      }
      await _channel.invokeMethod('showRecoveryDialog', args);
    } catch (e) {
      debugPrint('Error showing recovery dialog: $e');
    }
  }
}
