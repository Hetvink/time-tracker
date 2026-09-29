import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../data/models/attendance_state.dart';
import '../../../timesheet/data/models/daily_timesheet.dart';
import '../../data/repository/attendance_repository.dart';
import '../../data/repository/web_attendance_repository.dart';
import '../../data/datasource/platform_channel_service.dart';
import '../../../settings/presentation/providers/preferences_service.dart';
import '../../data/repository/app_activity_repository.dart';
import '../../data/models/app_activity.dart';

class AttendanceProvider extends ChangeNotifier {
  final AttendanceRepository _repository;
  final PlatformChannelService _platformService;
  final PreferencesService _preferencesService;
  final AppActivityRepository? _activityRepository;
  Timer? _updateTimer;
  Timer? _autoSaveTimer;
  Timer? _midnightMonitor;
  DateTime? _currentDay;
  Duration _todayClosedDuration = Duration.zero;
  Duration _todayClosedBreakDuration = Duration.zero;
  Duration _monthClosedDuration = Duration.zero;
  Duration _monthClosedBreakDuration = Duration.zero;
  Duration _allTimeClosedDuration = Duration.zero;

  AttendanceState _state = AttendanceState(
    status: AttendanceStatus.checkedOut,
    lastEventSource: EventSource.systemRecovery,
  );

  AttendanceState get state => _state;
  Duration get todayClosedDuration => _todayClosedDuration;
  Duration get todayClosedBreakDuration => _todayClosedBreakDuration;
  Duration get monthClosedDuration => _monthClosedDuration;
  Duration get monthClosedBreakDuration => _monthClosedBreakDuration;
  Duration get allTimeClosedDuration => _allTimeClosedDuration;
  int get totalSessionsCount => _totalSessionsCount;

  // Track if this is a boot event (vs manual launch)
  bool _isBootEvent = false;
  int _totalSessionsCount = 0;

  // Guard to prevent duplicate auto check-ins from multiple boot event retries
  bool _bootEventProcessed = false;
  DateTime? _lastBootEventTime;

  // Track if recovery has been completed (to prevent duplicate recovery)
  bool _recoveryCompleted = false;

  // CRITICAL: Flag to prevent manual check-in while boot check-in is in progress
  // This solves Bug #2 where user can manually check-in while native boot dialog is loading
  bool _bootCheckInInProgress = false;

  AttendanceProvider({
    required AttendanceRepository repository,
    required PlatformChannelService platformService,
    required PreferencesService preferencesService,
    AppActivityRepository? activityRepository,
  }) : _repository = repository,
       _platformService = platformService,
       _preferencesService = preferencesService,
       _activityRepository = activityRepository {
    _initialize();
  }

  Future<void> _initialize() async {
    // Note: Recovery is now handled by refresh() method which is called AFTER
    // Supabase data pull in _ensureLocalUser() (main_desktop.dart)
    // This ensures we have the latest last_seen_time before recovery

    // Initialize sleep threshold from preferences
    final sleepThresholdSeconds = _preferencesService.sleepThresholdSeconds;
    await _platformService.setSleepThreshold(sleepThresholdSeconds);

    // Listen to platform events
    _platformService.onSystemEvent.listen(_handleSystemEvent);
    _platformService.onUserAction.listen(_handleUserAction);
    _platformService.onBreakConfirmation.listen(_handleBreakConfirmation);

    // Start periodic UI updates (every second when checked in)
    _startUpdateTimer();

    // Note: Auto check-in will be triggered by the boot event from native side
    // The boot event is sent after Flutter's first frame to ensure handlers are ready
  }

  /// Refresh provider state after Supabase data pull
  /// This is called from _ensureLocalUser() AFTER pullFromSupabase()
  /// to ensure we have the latest session data before recovery
  Future<void> refresh() async {
    debugPrint('[REFRESH] Starting refresh (includes recovery)...');

    // Skip recovery process on web (read-only platform)
    if (_repository is WebAttendanceRepository) {
      debugPrint('[REFRESH] Web platform detected - skipping recovery process');
      await _updateDailyStats();
      notifyListeners();
      debugPrint('[REFRESH] Refresh complete (web mode)');
      return;
    }

    // CRITICAL FIX: Check for stale sessions FIRST
    // If user has been away for > 15 mins, close the session at last_seen_time
    // This prevents creating huge gaps or multi-day sessions when user just forgot to checkout
    final wasStale = await _checkAndCloseStaleSession();
    if (wasStale) {
      debugPrint(
        '[REFRESH] ✅ Stale session auto-closed. Skipping further recovery.',
      );
      await _updateDailyStats();
      notifyListeners();
      return;
    }

    // Perform recovery only once per app session (desktop only)
    if (!_recoveryCompleted) {
      debugPrint('[REFRESH] Running recovery logic (first time)...');

      // CRITICAL FIX: Run midnight transition recovery FIRST!
      // If a session spans multiple days (e.g., checked in at 6 PM, app reopened at 1 AM),
      // we need to split it into separate day sessions BEFORE closing.
      // This prevents the single-day recovery from closing a multi-day session without splitting.
      await _recoverFromIncompleteTransition();

      // Then check for any remaining unfinished sessions (crash recovery for single-day sessions)
      // This will now use the latest data from Supabase pull
      await _recoverUnfinishedSession();

      _recoveryCompleted = true;
      debugPrint('[REFRESH] ✅ Recovery completed');
    } else {
      debugPrint('[REFRESH] Skipping recovery (already completed)');
    }

    // Update daily stats
    await _updateDailyStats();

    notifyListeners();
    debugPrint('[REFRESH] Refresh complete');
  }

  /// Save session state when app is paused or closed
  /// This ensures we have a recent timestamp to use for recovery
  Future<void> saveSessionOnPause() async {
    if (_state.currentSessionId != null &&
        _state.status != AttendanceStatus.checkedOut) {
      final now = DateTime.now();

      // Update last_seen_time to current time
      await _repository.updateSessionLastSeen(_state.currentSessionId, now);

      debugPrint('[LIFECYCLE] Saved session state - last_seen: $now');
    }
  }

  Future<void> _updateDailyStats() async {
    // FIX: Use new unified methods that include active sessions
    // This ensures dashboard shows real-time durations including current session
    _todayClosedDuration = await _repository.getTodayWorkDuration();
    _todayClosedBreakDuration = await _repository.getTodayBreakDuration();
    _monthClosedDuration = await _repository.getMonthClosedWorkDuration();
    _monthClosedBreakDuration = await _repository.getMonthBreakDuration();
    _allTimeClosedDuration = await _repository.getAllTimeClosedWorkDuration();
    _totalSessionsCount = await _repository.getTotalSessionsCount();
    notifyListeners();
  }

  Future<List<DailyTimeSheet>> getMonthlyDailyTimeSheets(
    int year,
    int month, {
    bool refresh = false,
  }) {
    return _repository.getMonthlyDailyTimeSheets(year, month, refresh: refresh);
  }

  Future<List<Map<String, int>>> getAvailableMonths() {
    return _repository.getAvailableMonths();
  }

  int _updateTickCounter = 0;

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTickCounter = 0;
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_state.status != AttendanceStatus.checkedOut) {
        _updateMenuBar();
        _updateTickCounter++;
        // Update daily stats every 5 seconds to refresh dashboard display
        // This ensures the "Today's Working Hours" card updates in real-time
        if (_updateTickCounter % 5 == 0) {
          await _updateDailyStats();
        }
        // notifyListeners(); // Removed to prevent global rebuilds (flickering). Dashboard handles its own timer.
      }
    });
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();

    final sessionId = _state.currentSessionId;
    final checkInTime = _state.checkInTime ?? DateTime.now();

    // SMART AUTO-SAVE STRATEGY:
    // 1. First save: 30 seconds after check-in
    // 2. First 10 minutes: save every 1 minute
    // 3. After 10 minutes: save every 5 minutes
    //
    // Example: Check-in at 1:00 PM, power cut at 1:47 PM
    // Saves at: 1:00:30, 1:01:30, 1:02:30... 1:10:30, 1:15:30, 1:20:30, 1:25:30, 1:30:30, 1:35:30, 1:40:30, 1:45:30
    // Last save: 1:45:30 PM → checkout time = 1:45:30 PM (max 5 min data loss)

    debugPrint('[AUTO-SAVE] Started for session $sessionId');

    // Save immediately after 30 seconds
    Timer(const Duration(seconds: 30), () => _saveLastSeen(sessionId));

    // Then schedule periodic saves with smart intervals
    int saveCounter = 0;
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_state.currentSessionId != sessionId ||
          _state.status == AttendanceStatus.checkedOut) {
        return; // Session changed or ended
      }

      saveCounter++;
      final now = DateTime.now();
      final elapsed = now.difference(checkInTime);

      // Determine save frequency based on elapsed time
      bool shouldSave = false;

      if (elapsed.inMinutes <= 10) {
        // First 10 minutes: save every 1 minute (every 2nd check at 30s interval)
        shouldSave = (saveCounter % 2 == 0);
      } else {
        // After 10 minutes: save every 5 minutes (every 10th check at 30s interval)
        shouldSave = (saveCounter % 10 == 0);
      }

      if (shouldSave) {
        await _saveLastSeen(sessionId);
      }
    });
  }

  Future<void> _saveLastSeen(dynamic sessionId) async {
    if (sessionId == null) return;

    try {
      final now = DateTime.now();
      await _repository.updateSessionLastSeen(sessionId, now);
    } catch (e) {
      debugPrint('[AUTO-SAVE] Failed to save: $e');
    }
  }

  void _stopAutoSaveTimer() {
    if (_autoSaveTimer != null) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;
      debugPrint(
        '[AUTO-SAVE] Timer stopped for session ${_state.currentSessionId}',
      );
    }
  }

  void _startMidnightMonitor() {
    _currentDay = DateTime.now();
    _midnightMonitor?.cancel();

    // FIX: Check every 10 seconds for midnight transition (was 1 minute)
    // This ensures we don't miss midnight and create long single-day sessions
    _midnightMonitor = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkForMidnightTransition();
    });
  }

  void _stopMidnightMonitor() {
    _midnightMonitor?.cancel();
    _midnightMonitor = null;
    _currentDay = null;
  }

  Future<void> _checkForMidnightTransition() async {
    if (_state.status != AttendanceStatus.checkedIn &&
        _state.status != AttendanceStatus.onBreak) {
      return; // Only monitor when actively working
    }

    if (_currentDay == null) return;

    final now = DateTime.now();
    final currentDayStart = DateTime(now.year, now.month, now.day);
    final previousDayStart = DateTime(
      _currentDay!.year,
      _currentDay!.month,
      _currentDay!.day,
    );

    // Check if day has changed
    if (currentDayStart != previousDayStart) {
      await _handleMidnightTransition(previousDayStart, currentDayStart);
      _currentDay = now;
    }
  }

  Future<void> _handleMidnightTransition(
    DateTime previousDay,
    DateTime newDay,
  ) async {
    debugPrint('[MIDNIGHT] Handling midnight transition...');

    final wasOnBreak = _state.status == AttendanceStatus.onBreak;
    final currentSessionId = _state.currentSessionId;

    if (currentSessionId == null) {
      debugPrint('[MIDNIGHT] No active session, skipping transition');
      return;
    }

    // Step 1: Close previous day session at 23:59:59.999
    final previousDayEnd = DateTime(
      previousDay.year,
      previousDay.month,
      previousDay.day,
      23,
      59,
      59,
      999,
    );

    dynamic activeBreakId;
    if (wasOnBreak) {
      // End current break at day boundary
      activeBreakId = await _repository.getActiveBreakId(currentSessionId);
      if (activeBreakId != null) {
        await _repository.completeBreak(activeBreakId, previousDayEnd);
        debugPrint('[MIDNIGHT] ✓ Closed break at $previousDayEnd');
      }
    }

    // Close the session
    await _repository.closeSession(
      currentSessionId,
      previousDayEnd,
      EventSource.autoMidnightTransition,
    );
    debugPrint(
      '[MIDNIGHT] ✓ Closed session $currentSessionId at $previousDayEnd',
    );

    // Step 2: Create new day session at 00:00:00.000
    final newDayStart = DateTime(newDay.year, newDay.month, newDay.day);

    final newSessionId = await _repository.createSession(
      newDayStart,
      EventSource.autoMidnightTransition,
      continuationOfSessionId: currentSessionId,
      continuationReason: 'midnight_transition',
    );

    // Step 3: Record continuation in audit trail
    await _repository.recordSessionContinuation(
      originalSessionId: currentSessionId,
      newSessionId: newSessionId,
      continuationType: 'midnight',
      splitTimestamp: newDayStart,
      metadata: {
        'was_on_break': wasOnBreak,
        'timezone': newDayStart.timeZoneName,
      },
    );

    // Step 4: Restore break state if needed
    if (wasOnBreak && activeBreakId != null) {
      await _repository.startBreak(
        newSessionId,
        newDayStart,
        continuationOfBreakId: activeBreakId,
      );
    }

    // Step 5: Update in-memory state
    _state = _state.copyWith(
      currentSessionId: newSessionId,
      checkInTime: newDayStart,
      breaks: wasOnBreak ? [BreakPeriod(startTime: newDayStart)] : [],
      breakStartTime: wasOnBreak ? newDayStart : null,
      lastEventSource: EventSource.autoMidnightTransition,
    );

    // FIX: Notify listeners FIRST to ensure TrackingIntegrationService picks up new session ID
    // This is critical for activity tracking to update its session ID during midnight transition
    notifyListeners();

    _updateMenuBar();
    await _updateDailyStats();

    // Log event
    await _repository.logEvent(
      'midnight_transition',
      EventSource.autoMidnightTransition,
      metadata: {
        'previous_session_id': currentSessionId,
        'new_session_id': newSessionId,
        'was_on_break': wasOnBreak,
        'transition_time': newDayStart.toIso8601String(),
      },
    );
  }

  Future<void> _recoverUnfinishedSession() async {
    final unfinishedSession = await _repository.getUnfinishedSession();

    if (unfinishedSession != null) {
      final sessionId = unfinishedSession['id'];
      final checkInTime = DateTime.parse(
        unfinishedSession['check_in_time'] as String,
      );
      final activeBreakId = await _repository.getActiveBreakId(sessionId);

      // CRITICAL: Check if this is a multi-day gap
      final now = DateTime.now();
      final daysSinceCheckIn = now.difference(checkInTime).inDays;

      debugPrint('[RECOVERY] Session from $checkInTime found');
      debugPrint('[RECOVERY] Days since check-in: $daysSinceCheckIn');

      // Determine the last active time using multiple sources:
      // Priority: 1. Latest activity time  2. last_seen_time  3. checkInTime
      DateTime? lastActiveTime;
      String timeSource = 'unknown';

      // Try to get latest activity time from app tracking
      if (_activityRepository != null) {
        try {
          final latestActivityTime = await _activityRepository
              .getLatestActivityTime(sessionId);
          if (latestActivityTime != null &&
              latestActivityTime.isAfter(checkInTime)) {
            lastActiveTime = latestActivityTime;
            timeSource = 'latest_activity';
          }
        } catch (e) {
          debugPrint('[RECOVERY] Failed to get latest activity time: $e');
        }
      }

      // Fallback to last_seen_time (auto-save heartbeat)
      if ((lastActiveTime == null || timeSource != 'latest_activity') &&
          unfinishedSession['last_seen_time'] != null) {
        final lastSeenStr = unfinishedSession['last_seen_time'] as String;

        try {
          DateTime lastSeenTime = DateTime.parse(lastSeenStr);

          // Ensure proper timezone handling
          if (!lastSeenTime.isUtc && !lastSeenStr.endsWith('Z')) {
            // Already in local time
          } else if (lastSeenTime.isUtc) {
            // Convert UTC to local for comparison
            lastSeenTime = lastSeenTime.toLocal();
          }

          if (lastActiveTime == null || lastSeenTime.isAfter(lastActiveTime)) {
            lastActiveTime = lastSeenTime;
            timeSource = 'last_seen_time';
          }
        } catch (e) {
          debugPrint('[RECOVERY] Failed to parse last_seen_time: $e');
        }
      }

      // If gap is >= 1 day, close it automatically (no dialog)
      if (daysSinceCheckIn >= 1) {
        debugPrint(
          '[RECOVERY] Multi-day gap detected ($daysSinceCheckIn days) - auto-closing session',
        );
        // Fall through to auto-close logic below
      }

      // Same-day recovery - auto-close with validation
      debugPrint('[RECOVERY] Same-day recovery - auto-closing session');

      // CRITICAL: Never fallback to DateTime.now() for old sessions
      // If we have no tracking data, use checkInTime + 1 second as minimum
      lastActiveTime ??= checkInTime.add(const Duration(seconds: 1));
      if (timeSource == 'unknown') {
        timeSource = 'check_in_time_fallback';
      }

      // Validate and correct for timezone issues
      final localOffset = now.timeZoneOffset;

      // Ensure checkout time is in local timezone
      DateTime checkOutTime = lastActiveTime.isUtc
          ? lastActiveTime.toLocal()
          : lastActiveTime;

      // Fix future timestamps (timezone corruption)
      if (checkOutTime.isAfter(now)) {
        final corrected = checkOutTime.subtract(localOffset);
        if (corrected.isBefore(now) && corrected.isAfter(checkInTime)) {
          checkOutTime = corrected;
        } else {
          // Use end of check-in day as safe fallback
          final checkInDate = DateTime(
            checkInTime.year,
            checkInTime.month,
            checkInTime.day,
          );
          checkOutTime = DateTime(
            checkInDate.year,
            checkInDate.month,
            checkInDate.day,
            23,
            59,
            59,
            999,
          );
        }
      }

      // Validate checkout is after check-in
      try {
        final checkInUtcStr =
            unfinishedSession['check_in_time_utc'] as String? ??
            '${unfinishedSession['check_in_time']}Z';
        final checkInUtc = DateTime.parse(checkInUtcStr);
        final checkOutUtc = checkOutTime.toUtc();

        if (checkOutUtc.isBefore(checkInUtc)) {
          // Try timezone correction
          final correctedCheckOut = checkOutTime.add(localOffset);
          if (correctedCheckOut.toUtc().isAfter(checkInUtc)) {
            checkOutTime = correctedCheckOut;
          } else {
            // Use check-in time + 1 second as absolute minimum
            checkOutTime = checkInTime.add(const Duration(seconds: 1));
          }
        }
      } catch (e) {
        debugPrint('[RECOVERY] Validation error: $e');
      }

      // End active break if exists
      if (activeBreakId != null) {
        await _repository.completeBreak(activeBreakId, checkOutTime);
      }

      // Close session at last active time
      await _repository.closeSession(
        sessionId,
        checkOutTime,
        EventSource.systemRecovery,
      );

      // Update in-memory state to reflect checkout
      _state = _state.copyWith(
        status: AttendanceStatus.checkedOut,
        checkOutTime: checkOutTime,
        lastEventSource: EventSource.systemRecovery,
        clearBreakStartTime: true,
      );

      // Stop timers
      _stopAutoSaveTimer();
      _stopMidnightMonitor();

      // Log recovery event
      await _repository.logEvent(
        'session_recovered',
        EventSource.systemRecovery,
        metadata: {
          'session_id': sessionId,
          'action': 'closed_auto',
          'recovered_at': DateTime.now().toIso8601String(),
          'checkout_time': checkOutTime.toIso8601String(),
          'checkout_time_source': timeSource,
        },
      );

      debugPrint(
        '[RECOVERY] Session $sessionId closed (source: $timeSource, checkout: $checkOutTime)',
      );
    }
  }

  Future<void> _recoverFromIncompleteTransition() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // Find sessions that are open but have check_in_time on previous day(s)
    final unfinishedSession = await _repository.getUnfinishedSession();

    if (unfinishedSession == null) return;

    final checkInTime = DateTime.parse(
      unfinishedSession['check_in_time'] as String,
    );
    final checkInDate = DateTime(
      checkInTime.year,
      checkInTime.month,
      checkInTime.day,
    );
    final sessionId = unfinishedSession['id']; // dynamic

    // If session started before today, need to create continuation chain
    if (checkInDate.isBefore(todayStart)) {
      debugPrint(
        '[RECOVERY] Found session spanning multiple days. Creating continuation chain...',
      );

      DateTime currentDay = checkInDate;
      dynamic currentSessionId = sessionId;

      while (currentDay.isBefore(todayStart)) {
        final nextDay = currentDay.add(const Duration(days: 1));
        final dayEnd = DateTime(
          currentDay.year,
          currentDay.month,
          currentDay.day,
          23,
          59,
          59,
          999,
        );
        final dayStart = DateTime(nextDay.year, nextDay.month, nextDay.day);

        // Close current day
        await _repository.closeSession(
          currentSessionId,
          dayEnd,
          EventSource.systemRecovery,
        );

        debugPrint('[RECOVERY] Closed session $currentSessionId at $dayEnd');

        // Create next day
        final newSessionId = await _repository.createSession(
          dayStart,
          EventSource.systemRecovery,
          continuationOfSessionId: currentSessionId,
          continuationReason: 'recovery_midnight_transition',
        );

        await _repository.recordSessionContinuation(
          originalSessionId: currentSessionId,
          newSessionId: newSessionId,
          continuationType: 'midnight',
          splitTimestamp: dayStart,
          metadata: {'recovery': true},
        );

        debugPrint('[RECOVERY] Created session $newSessionId at $dayStart');

        currentDay = nextDay;
        currentSessionId = newSessionId;
      }

      // Update state to new session if it's still today
      if (currentSessionId != sessionId) {
        _state = _state.copyWith(
          status: AttendanceStatus.checkedIn,
          currentSessionId: currentSessionId,
          checkInTime: DateTime(
            todayStart.year,
            todayStart.month,
            todayStart.day,
          ),
          lastEventSource: EventSource.systemRecovery,
        );

        // Start monitors
        _startAutoSaveTimer();
        _startMidnightMonitor();

        await _updateMenuBar();

        debugPrint('[RECOVERY] Restored to session $currentSessionId');
      }
    }
  }

  /// Checks if the current unfinished session is "stale" (inactive for > 15 mins)
  /// and closes it at the last_seen_time if so.
  /// Returns true if a session was closed, false otherwise.
  Future<bool> _checkAndCloseStaleSession() async {
    try {
      final unfinishedSession = await _repository.getUnfinishedSession();
      if (unfinishedSession == null) return false;

      final sessionId = unfinishedSession['id'];
      final lastSeenStr = unfinishedSession['last_seen_time'] as String?;

      if (lastSeenStr == null) {
        debugPrint(
          '[STALE CHECK] No last_seen_time found for session $sessionId',
        );
        return false;
      }

      final now = DateTime.now();
      DateTime lastSeenTime = DateTime.parse(lastSeenStr);

      // Ensure UTC comparison if needed, or convert to local
      if (lastSeenTime.isUtc) {
        lastSeenTime = lastSeenTime.toLocal();
      }

      final gap = now.difference(lastSeenTime);

      final threshold = const Duration(hours: 2);

      if (gap > threshold) {
        debugPrint('[STALE CHECK] ⚠️ Session $sessionId is stale!');
        debugPrint('[STALE CHECK] Last seen: $lastSeenTime');
        debugPrint('[STALE CHECK] Current time: $now');
        debugPrint(
          '[STALE CHECK] Gap: ${gap.inMinutes} minutes (Threshold: 15)',
        );

        // Close the session at last_seen_time
        debugPrint('[STALE CHECK] Auto-closing session at $lastSeenTime...');

        // Also close any active break
        final activeBreakId = await _repository.getActiveBreakId(sessionId);
        if (activeBreakId != null) {
          await _repository.completeBreak(activeBreakId, lastSeenTime);
          debugPrint('[STALE CHECK] Closed active break $activeBreakId');
        }

        await _repository.closeSession(
          sessionId,
          lastSeenTime,
          EventSource.systemRecovery, // Or a new source like autoTimeout?
        );

        // Update local state
        _state = _state.copyWith(
          status: AttendanceStatus.checkedOut,
          checkOutTime: lastSeenTime,
          lastEventSource: EventSource.systemRecovery,
          clearBreakStartTime: true,
        );

        // Stop timers
        _stopAutoSaveTimer();
        _stopMidnightMonitor();

        await _repository.logEvent(
          'stale_session_closed',
          EventSource.systemRecovery,
          metadata: {
            'session_id': sessionId,
            'last_seen_time': lastSeenTime.toIso8601String(),
            'closed_at': now.toIso8601String(),
            'gap_minutes': gap.inMinutes,
          },
        );

        return true;
      } else {
        debugPrint(
          '[STALE CHECK] Session $sessionId is active (Gap: ${gap.inSeconds}s)',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[STALE CHECK] Error checking stale session: $e');
      return false;
    }
  }

  Future<void> _handleSystemEvent(SystemEvent event) async {
    debugPrint('System event received: ${event.type}');

    switch (event.type) {
      case SystemEventType.boot:
        // Guard: prevent multiple auto check-ins from boot event retries
        final now = DateTime.now();
        if (_bootEventProcessed && _lastBootEventTime != null) {
          final timeSinceLast = now.difference(_lastBootEventTime!).inSeconds;
          if (timeSinceLast < 30) {
            // Ignore repeated boot events within 30 seconds (from retry timer)
            debugPrint(
              '[AUTO CHECK-IN] ⚠️ Boot event ignored (already processed ${timeSinceLast}s ago)',
            );
            return;
          }
        }

        _bootEventProcessed = true;
        _lastBootEventTime = now;
        _isBootEvent = true;
        _bootCheckInInProgress = true; // Block manual check-ins
        debugPrint(
          '[AUTO CHECK-IN] Boot event detected, attempting auto check-in...',
        );
        try {
          await _autoCheckIn();
        } finally {
          _isBootEvent = false; // Reset flag after processing
          _bootCheckInInProgress = false; // Allow manual check-ins again
          debugPrint(
            '[AUTO CHECK-IN] Boot check-in complete, manual check-ins now allowed',
          );
        }
        break;
      case SystemEventType.shutdown:
        debugPrint(
          '[AUTO CHECK-OUT] Shutdown event detected, forcing check-out...',
        );
        await _autoCheckOut();
        break;
      case SystemEventType.sleep:
        // Do nothing - keep session active
        debugPrint('System sleeping - session remains active');
        await _repository.logEvent('system_sleep', EventSource.autoSystemStart);
        break;
      case SystemEventType.wake:
        // Update UI timer
        debugPrint('System woke up - updating display');
        await _updateMenuBar();
        await _repository.logEvent('system_wake', EventSource.autoSystemStart);
        break;
      case SystemEventType.midnight:
        // Midnight event from platform (macOS/Windows)
        // Flutter-side timer also handles this, so this is a redundant trigger
        debugPrint('Midnight event received from platform');
        await _checkForMidnightTransition();
        break;
    }
  }

  Future<void> _handleUserAction(UserAction action) async {
    debugPrint('User action received: ${action.type}');

    switch (action.type) {
      case UserActionType.checkIn:
        await checkIn(EventSource.manualUser);
        break;
      case UserActionType.checkOut:
        await checkOut(EventSource.manualUser);
        break;
      case UserActionType.breakIn:
        await breakIn();
        break;
      case UserActionType.breakOut:
        await breakOut();
        break;
    }
  }

  Future<void> _autoCheckIn() async {
    try {
      if (!_preferencesService.autoCheckInEnabled) return;
      if (_preferencesService.autoCheckInOnBootOnly && !_isBootEvent) return;
      if (_state.status == AttendanceStatus.checkedIn ||
          _state.status == AttendanceStatus.onBreak) {
        return;
      }

      await checkIn(EventSource.autoSystemStart);
    } catch (e) {
      // Silent error - app continues running
    }
  }

  Future<void> _autoCheckOut() async {
    // Only check out if currently checked in or on break
    if (_state.status == AttendanceStatus.checkedOut) {
      return;
    }

    await checkOut(EventSource.autoSystemShutdown);
  }

  Future<void> checkIn(EventSource source) async {
    try {
      if (_bootCheckInInProgress && source == EventSource.manualUser) return;
      if (!_state.canCheckIn) return;
      if (_state.status == AttendanceStatus.checkedIn ||
          _state.status == AttendanceStatus.onBreak) {
        return;
      }

      final now = DateTime.now();
      final sessionId = await _repository.createSession(now, source);

      _state = _state.copyWith(
        status: AttendanceStatus.checkedIn,
        checkInTime: now,
        lastEventSource: source,
        currentSessionId: sessionId,
        breaks: [],
        clearCheckOutTime: true,
        clearBreakStartTime: true,
      );

      await _repository.logEvent('check_in', source);
      notifyListeners();
      await _updateMenuBar();
      _startAutoSaveTimer();
      _startMidnightMonitor();
    } catch (e) {
      _state = _state.copyWith(
        status: AttendanceStatus.checkedOut,
        clearCurrentSessionId: true,
        clearCheckInTime: true,
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> checkOut(EventSource source) async {
    if (!_state.canCheckOut && _state.status != AttendanceStatus.onBreak) {
      debugPrint('Cannot check out - current status: ${_state.status}');
      return;
    }

    final now = DateTime.now();

    // If on break, force break out first
    if (_state.status == AttendanceStatus.onBreak) {
      await breakOut(forceClose: true);
    }

    // Close session
    if (_state.currentSessionId != null) {
      await _repository.closeSession(_state.currentSessionId!, now, source);
    }

    _state = _state.copyWith(
      status: AttendanceStatus.checkedOut,
      checkOutTime: now,
      lastEventSource: source,
      clearBreakStartTime: true,
    );

    await _repository.logEvent('check_out', source);

    notifyListeners();
    await _updateMenuBar();

    // Stop auto-save timer
    _stopAutoSaveTimer();

    // Stop midnight monitor
    _stopMidnightMonitor();

    // Update daily stats
    await _updateDailyStats();

    debugPrint('Checked out at $now (source: $source)');
    debugPrint('Total work time: ${_formatDuration(_state.totalWorkTime)}');
  }

  Future<void> breakIn() async {
    if (!_state.canBreakIn) {
      debugPrint('Cannot start break - current status: ${_state.status}');
      return;
    }

    final now = DateTime.now();

    if (_state.currentSessionId != null) {
      await _repository.startBreak(_state.currentSessionId!, now);
    }

    _state = _state.copyWith(
      status: AttendanceStatus.onBreak,
      breakStartTime: now,
      lastEventSource: EventSource.manualUser,
    );

    await _repository.logEvent('break_in', EventSource.manualUser);

    notifyListeners();
    await _updateMenuBar();

    debugPrint('Break started at $now');
  }

  Future<void> breakOut({bool forceClose = false}) async {
    if (!_state.canBreakOut && !forceClose) {
      debugPrint('Cannot end break - current status: ${_state.status}');
      return;
    }

    final now = DateTime.now();

    await _repository.endBreak(now);

    final newBreak = BreakPeriod(
      startTime: _state.breakStartTime!,
      endTime: now,
    );

    _state = _state.copyWith(
      status: AttendanceStatus.checkedIn,
      breaks: [..._state.breaks, newBreak],
      clearBreakStartTime: true,
      lastEventSource: EventSource.manualUser,
    );

    await _repository.logEvent('break_out', EventSource.manualUser);

    notifyListeners();
    await _updateMenuBar();

    debugPrint(
      'Break ended at $now (duration: ${_formatDuration(newBreak.duration)})',
    );
  }

  Future<void> _updateMenuBar() async {
    final statusText = _getStatusText();
    final enabledItems = _getEnabledMenuItems();

    await _platformService.updateMenuBar(statusText);
    await _platformService.updateMenuItems(enabledItems);
  }

  String _getStatusText() {
    switch (_state.status) {
      case AttendanceStatus.checkedOut:
        if (_state.checkOutTime != null) {
          final time = DateFormat('hh:mm a').format(_state.checkOutTime!);
          return 'Checked Out at $time';
        }
        return 'Checked Out';
      case AttendanceStatus.checkedIn:
        final duration = _state.totalWorkTime;
        return 'Working - ${_formatDuration(duration)}';
      case AttendanceStatus.onBreak:
        if (_state.breakStartTime != null) {
          final breakDuration = DateTime.now().difference(
            _state.breakStartTime!,
          );
          return 'On Break - ${_formatDuration(breakDuration)}';
        }
        return 'On Break';
    }
  }

  List<String> _getEnabledMenuItems() {
    return [
      if (_state.canCheckIn) 'Check In',
      if (_state.canCheckOut) 'Check Out',
      if (_state.canBreakIn) 'Break In',
      if (_state.canBreakOut) 'Break Out',
      'Quit',
    ];
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Unified status change method with validation
  /// Returns error message if transition fails, null on success
  Future<String?> changeStatus(AttendanceStatus targetStatus) async {
    // Validate transition
    final error = _state.getTransitionError(targetStatus);
    if (error != null) {
      debugPrint('Status change denied: $error');
      return error;
    }

    try {
      // Execute the appropriate transition
      switch (targetStatus) {
        case AttendanceStatus.checkedIn:
          if (_state.status == AttendanceStatus.checkedOut) {
            await checkIn(EventSource.manualUser);
          } else if (_state.status == AttendanceStatus.onBreak) {
            await breakOut();
          }
          break;

        case AttendanceStatus.onBreak:
          if (_state.status == AttendanceStatus.checkedIn) {
            await breakIn();
          }
          break;

        case AttendanceStatus.checkedOut:
          if (_state.status == AttendanceStatus.checkedIn ||
              _state.status == AttendanceStatus.onBreak) {
            await checkOut(EventSource.manualUser);
          }
          break;
      }

      debugPrint(
        'Status changed successfully: ${_state.status} -> $targetStatus',
      );
      return null; // Success
    } catch (e) {
      final errorMsg = 'Failed to change status: $e';
      debugPrint(errorMsg);
      return errorMsg;
    }
  }

  Future<void> _handleBreakConfirmation(BreakConfirmationEvent event) async {
    try {
      debugPrint('=== BREAK CONFIRMATION RECEIVED ===');
      debugPrint('Was on break: ${event.wasOnBreak}');
      debugPrint('Sleep start: ${event.sleepStart}');
      debugPrint('Wake time: ${event.wakeTime}');
      debugPrint('Note: ${event.note}');
      debugPrint('Current status: ${_state.status}');

      // Only process if checked in
      if (_state.status != AttendanceStatus.checkedIn) {
        debugPrint(
          'Break confirmation ignored - not checked in (status: ${_state.status})',
        );
        return;
      }

      if (!event.wasOnBreak) {
        // User was working - do NOT add a break period
        // The session continued through the sleep, so time is already counted as work
        debugPrint('User confirmed they were working during sleep');

        final String note =
            (event.note != null && event.note!.trim().isNotEmpty)
            ? event.note!.trim()
            : 'Working';

        // Store the work-during-sleep period with note
        // We avoid addRetroactiveBreak because that would SUBTRACT the time from work duration
        final duration = event.wakeTime.difference(event.sleepStart);
        debugPrint(
          'Recording work-during-sleep for ${duration.inMinutes} minutes: $note',
        );

        if (_activityRepository != null && _state.currentSessionId != null) {
          try {
            // 1. Delete any existing background tracking events during sleep
            final deletedIds = await _activityRepository
                .deleteActivitiesInTimeRange(
                  _state.currentSessionId,
                  event.sleepStart,
                  event.wakeTime,
                );
            debugPrint(
              '🗑️ Deleted ${deletedIds.length} overlapping activities during sleep',
            );

            // 2. Explicitly insert a continuous work activity to bridge the sleep period
            final manualActivity = AppActivity(
              sessionId: _state.currentSessionId,
              appName: 'Working While Sleeping',
              windowTitle: 'WS - $note',
              startTime: event.sleepStart,
              endTime: event.wakeTime,
              durationSeconds: duration.inSeconds,
            );
            await _activityRepository.insertActivity(manualActivity);
          } catch (e, stackTrace) {
            debugPrint('❌ Error appending WS note to activities: $e');
            debugPrint('Stack trace: $stackTrace');
          }
        }

        // Check if work spans multiple days
        final workStartDate = DateTime(
          event.sleepStart.year,
          event.sleepStart.month,
          event.sleepStart.day,
        );
        final workEndDate = DateTime(
          event.wakeTime.year,
          event.wakeTime.month,
          event.wakeTime.day,
        );

        if (workStartDate != workEndDate) {
          debugPrint(
            '[WORK SPLIT] Work spans multiple days: $workStartDate to $workEndDate',
          );
          try {
            await _repository.addWorkDuringSleepWithDaySplit(
              event.sleepStart,
              event.wakeTime,
              note,
            );
            // Notify listeners to refresh UI
            notifyListeners();
            await _updateDailyStats(); // Ensure stats update across days
          } catch (e, stackTrace) {
            debugPrint('❌ Error adding split work-during-sleep: $e');
            debugPrint('Stack trace: $stackTrace');
            // Continue execution - don't crash the app
          }
        } else {
          // Single day - use existing logic
          if (_state.currentSessionId != null) {
            try {
              await _repository.addWorkDuringSleep(
                _state.currentSessionId!,
                event.sleepStart,
                event.wakeTime,
                note,
              );
              // Notify listeners to refresh UI
              notifyListeners();
            } catch (e, stackTrace) {
              debugPrint('❌ Error adding work-during-sleep: $e');
              debugPrint('Stack trace: $stackTrace');
              // Continue execution - don't crash the app
            }
          }
        }
        return;
      }

      // User confirms they were on break
      final duration = event.wakeTime.difference(event.sleepStart);
      debugPrint('Adding retroactive break: ${duration.inMinutes} minutes');

      // Check if break spans multiple days
      final breakStartDate = DateTime(
        event.sleepStart.year,
        event.sleepStart.month,
        event.sleepStart.day,
      );
      final breakEndDate = DateTime(
        event.wakeTime.year,
        event.wakeTime.month,
        event.wakeTime.day,
      );

      if (breakStartDate != breakEndDate) {
        debugPrint(
          '[BREAK SPLIT] Break spans multiple days: $breakStartDate to $breakEndDate',
        );

        // Use the new day-split method
        try {
          final breakIds = await _repository.addRetroactiveBreakWithDaySplit(
            event.sleepStart,
            event.wakeTime,
          );

          debugPrint(
            '[BREAK SPLIT] Successfully added ${breakIds.length} break segments',
          );

          // Create break period objects for UI state (for current day only)
          final today = DateTime.now();
          final todayDate = DateTime(today.year, today.month, today.day);

          // Only add to state if the break includes today
          if (breakEndDate == todayDate) {
            final todayBreakStart = DateTime(
              todayDate.year,
              todayDate.month,
              todayDate.day,
            );
            final breakPeriod = BreakPeriod(
              startTime: todayBreakStart,
              endTime: event.wakeTime,
            );

            _state = _state.copyWith(breaks: [..._state.breaks, breakPeriod]);
          }

          notifyListeners();
          await _updateMenuBar();
          await _updateDailyStats();

          debugPrint(
            'Retroactive break(s) added successfully across multiple days',
          );
        } catch (e, stackTrace) {
          debugPrint('❌ Error adding split retroactive break: $e');
          debugPrint('Stack trace: $stackTrace');
          // Continue execution - don't crash the app
        }
      } else {
        // Break is within a single day - use original method
        debugPrint('Break is within a single day');

        if (_state.currentSessionId != null) {
          try {
            await _repository.addRetroactiveBreak(
              _state.currentSessionId!,
              event.sleepStart,
              event.wakeTime,
            );

            // Create break period object
            final breakPeriod = BreakPeriod(
              startTime: event.sleepStart,
              endTime: event.wakeTime,
            );

            // Update state with new break
            _state = _state.copyWith(breaks: [..._state.breaks, breakPeriod]);

            notifyListeners();
            await _updateMenuBar();

            debugPrint('Retroactive break added successfully');
          } catch (e, stackTrace) {
            debugPrint('❌ Error adding retroactive break: $e');
            debugPrint('Stack trace: $stackTrace');
            // Continue execution - don't crash the app
          }
        } else {
          debugPrint('Error: No current session ID for retroactive break');
        }
      }

      debugPrint('=== END BREAK CONFIRMATION ===');
    } catch (e, stackTrace) {
      // CRITICAL: Catch all errors to prevent app crashes on Windows
      // This handles database errors, sync failures, and any other unexpected issues
      debugPrint('❌ CRITICAL ERROR in _handleBreakConfirmation: $e');
      debugPrint('Stack trace: $stackTrace');
      // App continues running - user can try the operation again
    }
  }

  Future<void> clearData() async {
    _stopAutoSaveTimer();
    _stopMidnightMonitor();

    await _repository.clearAllData();

    _state = AttendanceState(
      status: AttendanceStatus.checkedOut,
      lastEventSource: EventSource.manualUser,
    );

    _todayClosedDuration = Duration.zero;
    _todayClosedBreakDuration = Duration.zero;
    _monthClosedDuration = Duration.zero;
    _allTimeClosedDuration = Duration.zero;
    _totalSessionsCount = 0;
    _currentDay = null;

    notifyListeners();
    await _updateMenuBar();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}
