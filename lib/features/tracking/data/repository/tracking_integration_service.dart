import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../presentation/providers/attendance_provider.dart';
import '../../presentation/providers/activity_tracking_provider.dart';
import '../models/attendance_state.dart';

/// SIMPLIFIED: Integrates activity tracking with timesheet attendance
/// - Starts tracking when checked in
/// - Stops tracking when checked out
/// - Updates session ID for proper timesheet linkage
/// - NO activity type management (handled by attendance state in DB queries)
class TrackingIntegrationService {
  final AttendanceProvider _attendanceProvider;
  final ActivityTrackingProvider _activityProvider;
  StreamSubscription? _attendanceSubscription;

  TrackingIntegrationService({
    required AttendanceProvider attendanceProvider,
    required ActivityTrackingProvider activityProvider,
  }) : _attendanceProvider = attendanceProvider,
       _activityProvider = activityProvider {
    _initialize();
  }

  void _initialize() {
    debugPrint('[INTEGRATION] 🔧 Initializing tracking integration service...');
    _attendanceProvider.addListener(_handleAttendanceChange);
    debugPrint('[INTEGRATION] ✅ Added listener to attendance provider');

    // FIX: Start tracking if already checked in OR on break
    // This ensures activity tracking resumes when app is reopened during a session
    final currentStatus = _attendanceProvider.state.status;
    final sessionId = _attendanceProvider.state.currentSessionId;

    debugPrint('[INTEGRATION] Current attendance status: $currentStatus');
    debugPrint('[INTEGRATION] Current session ID: $sessionId');

    if (currentStatus == AttendanceStatus.checkedIn ||
        currentStatus == AttendanceStatus.onBreak) {
      debugPrint(
        '[INTEGRATION] 🎯 User is checked in, starting activity tracking...',
      );
      _startTracking();
      debugPrint('[INTEGRATION] ✅ Resumed tracking for recovered session');
    } else {
      debugPrint(
        '[INTEGRATION] ⏸️  User not checked in, tracking will start on check-in',
      );
    }
  }

  void _handleAttendanceChange() {
    // FIX: Schedule update for next frame to avoid "setState() or markNeedsBuild() called during build"
    // This happens when AttendanceProvider notifies listeners (during build/layout)
    // and we try to synchronously update ActivityTrackingProvider which also notifies listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _attendanceProvider.state;
      final sessionId = state.currentSessionId;

      debugPrint('[INTEGRATION] 🔄 Attendance state changed: ${state.status}');
      debugPrint('[INTEGRATION] Session ID: $sessionId');

      switch (state.status) {
        case AttendanceStatus.checkedIn:
          // Start or update tracking with session ID
          if (_activityProvider.isTracking) {
            debugPrint('[INTEGRATION] 🔄 Updating session ID to $sessionId');
            _activityProvider.setSessionId(sessionId);
          } else {
            debugPrint(
              '[INTEGRATION] ▶️  Starting tracking for session $sessionId',
            );
            _activityProvider.startTracking(sessionId: sessionId);
          }
          break;

        case AttendanceStatus.onBreak:
          // Keep tracking, update session ID if needed
          if (_activityProvider.isTracking && sessionId != null) {
            debugPrint(
              '[INTEGRATION] 🔄 Updating session ID during break to $sessionId',
            );
            _activityProvider.setSessionId(sessionId);
          } else {
            debugPrint('[INTEGRATION] ⏸️  On break but tracking not active');
          }
          break;

        case AttendanceStatus.checkedOut:
          debugPrint('[INTEGRATION] ⏹️  Check-out detected, stopping tracking');
          _stopTracking();
          break;
      }
    });
  }

  void _startTracking() {
    final sessionId = _attendanceProvider.state.currentSessionId;
    debugPrint(
      '[INTEGRATION] 🚀 Starting activity tracking for session $sessionId',
    );
    _activityProvider.startTracking(sessionId: sessionId);
  }

  void _stopTracking() {
    debugPrint('[INTEGRATION] 🛑 Stopping activity tracking');
    _activityProvider.stopTracking();
  }

  void dispose() {
    _attendanceProvider.removeListener(_handleAttendanceChange);
    _attendanceSubscription?.cancel();
  }
}
