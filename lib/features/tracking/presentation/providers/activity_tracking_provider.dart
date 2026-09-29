import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/app_activity.dart';
import '../../data/models/work_session.dart';
import '../../data/repository/app_activity_repository.dart';
import '../../data/repository/attendance_repository.dart';
import '../../data/datasource/platform_channel_service.dart';
import '../../../../core/network/supabase_sync_service.dart';

/// SIMPLIFIED: Activity tracking provider - UI state only
/// - Manages native activity tracking lifecycle
/// - Fetches and displays activity data
/// - Links activities to timesheet sessions
/// - NO activity type detection (native side handles this)
class ActivityTrackingProvider with ChangeNotifier {
  final AppActivityRepository _repository;
  final PlatformChannelService _platformService;
  final AttendanceRepository _attendanceRepository;
  final SupabaseSyncService? _syncService;

  bool _isTracking = false;
  AppActivity? _currentActivity;
  dynamic _currentSessionId; // dynamic (int or String)
  StreamSubscription? _activitySubscription;
  Timer? _autoSaveTimer;
  Timer? _syncTimer;

  // Month view state (merged from ActivityMonthProvider)
  DateTime _currentMonth = DateTime.now();
  Map<String, dynamic> _monthStats = {};
  bool _isLoadingMonth = false;
  bool _hasLoadedMonthOnce =
      false; // Track if data has been loaded at least once
  int _refreshCounter = 0; // Counter to notify listeners of refresh events

  bool get isTracking => _isTracking;
  AppActivity? get currentActivity => _currentActivity;
  DateTime get currentMonth => _currentMonth;
  Map<String, dynamic> get monthStats => _monthStats;
  bool get isLoadingMonth => _isLoadingMonth;
  int get refreshCounter => _refreshCounter; // Expose refresh counter

  ActivityTrackingProvider({
    required AppActivityRepository repository,
    required PlatformChannelService platformService,
    required AttendanceRepository attendanceRepository,
    SupabaseSyncService? syncService,
  }) : _repository = repository,
       _platformService = platformService,
       _attendanceRepository = attendanceRepository,
       _syncService = syncService {
    _initialize();
  }

  /// Initialize provider and restore state from database
  Future<void> _initialize() async {
    _setupActivityListener();
    await _restoreSessionState();
    await _loadMonthStats();
  }

  /// Restore activity tracking state when app reopens
  /// This fixes the issue where session ID is lost on app restart
  /// CRITICAL FIX: Also restarts native tracking if we had an active session
  Future<void> _restoreSessionState() async {
    debugPrint('[ACTIVITY] 🔄 Attempting to restore session state...');

    // FIX: Close any stale open activities from previous closed sessions.
    // This prevents the "21-hour duration" bug caused by activities that were
    // never properly ended when the app crashed or was force-quit.
    await _repository.closeStaleActivities();

    // Check if there's an active (unclosed) activity in the database
    final currentActivity = await _repository.getCurrentActivity();
    if (currentActivity != null) {
      _currentActivity = currentActivity;
      _currentSessionId = currentActivity.sessionId;
      _isTracking = true;

      debugPrint(
        '[ACTIVITY] ✅ Restored session state: session=$_currentSessionId, activity=${currentActivity.id}',
      );
      debugPrint(
        '[ACTIVITY] Activity: ${currentActivity.appName} - ${currentActivity.windowTitle}',
      );

      // CRITICAL: Restart native tracking since we had an active session
      // Without this, native side won't send activity events even though we think we're tracking
      debugPrint(
        '[ACTIVITY] 🔄 Restarting native tracking for restored session...',
      );
      await _platformService.startActivityTracking();

      // Start auto-save and sync timers
      _startAutoSaveTimer();
      _startSyncTimer();
      debugPrint('[ACTIVITY] ✅ Native tracking and timers restored');

      notifyListeners();
    } else {
      debugPrint('[ACTIVITY] ℹ️  No active session to restore');
    }
  }

  void _setupActivityListener() {
    debugPrint('[ACTIVITY] 📡 Setting up activity change listener...');
    _activitySubscription = _platformService.onActivityChange.listen(
      _handleActivityChange,
      onError: (error) {
        debugPrint('[ACTIVITY] ❌ Error in activity change stream: $error');
      },
      onDone: () {
        debugPrint('[ACTIVITY] ⚠️  Activity change stream closed');
      },
    );
    debugPrint('[ACTIVITY] ✅ Activity change listener ready');
  }

  Future<void> startTracking({dynamic sessionId}) async {
    debugPrint('[ACTIVITY] 🎬 startTracking called with sessionId: $sessionId');

    if (_isTracking) {
      debugPrint('[ACTIVITY] ⚠️  Already tracking, ignoring start request');
      return;
    }

    _currentSessionId = sessionId;
    _isTracking = true;
    debugPrint(
      '[ACTIVITY] ✅ Set tracking state: isTracking=$_isTracking, sessionId=$_currentSessionId',
    );

    // Start native tracking
    debugPrint('[ACTIVITY] 📡 Calling native startActivityTracking...');
    await _platformService.startActivityTracking();
    debugPrint('[ACTIVITY] ✅ Native tracking started');

    // Get initial activity
    debugPrint('[ACTIVITY] 🔍 Getting current activity from native...');
    final current = await _platformService.getCurrentActivity();
    if (current != null) {
      debugPrint(
        '[ACTIVITY] ✅ Current activity: ${current['appName']} - ${current['windowTitle']}',
      );
      await _recordActivity(
        appName: current['appName'] as String,
        windowTitle: current['windowTitle'] as String?,
        bundleId: current['bundleId'] as String?,
      );
    } else {
      debugPrint('[ACTIVITY] ⚠️  No current activity available');
    }

    // Start auto-save timer to update activity every 30 seconds
    debugPrint('[ACTIVITY] ⏰ Starting auto-save timer (30s interval)');
    _startAutoSaveTimer();

    // Start periodic sync timer to sync activities every 30 seconds
    debugPrint('[ACTIVITY] ⏰ Starting sync timer (30s interval)');
    _startSyncTimer();

    debugPrint('[ACTIVITY] ✅ 🎉 Tracking fully started and operational!');
    notifyListeners();
  }

  /// Start auto-save timer to update current activity every 30 seconds
  /// This ensures activity tracking stays synchronized even if app closes unexpectedly
  /// Reduced from 60s to 30s for better data protection during power cuts
  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();

    // Update current activity every 30 seconds (reduced from 60s)
    // This ensures max 30s of activity data loss during unexpected shutdown
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _updateCurrentActivity();
    });
  }

  /// Checkpoint the current activity's end_time on the existing DB row every 30s.
  ///
  /// KEY DESIGN:
  /// - Updates end_time IN-PLACE on the SAME row — no new record is created.
  /// - The in-memory `_currentActivity` is intentionally NOT changed.
  ///   It stays "active" (endTime == null) so `_recordActivity()` can detect
  ///   window changes and properly close this row when the user switches apps.
  /// - Crash protection: if the app dies, the DB row has an end_time ≤30s stale.
  ///
  /// PREVIOUS BUG: Creating a NEW record every 30s caused Mixed Activities
  /// to count N records for N×30s of uninterrupted use — inflating every
  /// app's reported usage by a factor of N.
  Future<void> _updateCurrentActivity() async {
    if (_currentActivity != null && _currentActivity!.id != null) {
      final now = DateTime.now();
      // Checkpoint end_time on the same row — in-memory state unchanged.
      await _repository.endActivity(_currentActivity!.id!, now);
      debugPrint(
        '[ACTIVITY] Checkpointed: ${_currentActivity!.appName}'
        ' - ${_currentActivity!.windowTitle} @ $now',
      );
    }
  }

  void _stopAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// Start periodic sync timer to sync activities to Supabase every 30 seconds
  /// Aligned with auto-save timer for consistent data protection
  void _startSyncTimer() {
    _syncTimer?.cancel();

    // Only start sync timer if syncService is available
    if (_syncService != null) {
      // Sync activities every 30 seconds (aligned with auto-save)
      // This ensures cloud backup is recent for power cut recovery
      _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _performPeriodicSync();
      });
    }
  }

  /// Perform periodic sync of all activities to Supabase
  Future<void> _performPeriodicSync() async {
    final syncService = _syncService;
    if (syncService != null) {
      try {
        debugPrint('[SYNC] Performing periodic sync...');
        await syncService.syncAll();
        debugPrint('[SYNC] Periodic sync complete');
      } catch (e) {
        debugPrint('[SYNC] Periodic sync failed: $e');
      }
    }
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> stopTracking() async {
    if (!_isTracking) {
      debugPrint('[ACTIVITY] Not tracking');
      return;
    }

    // End current activity
    if (_currentActivity != null && _currentActivity!.isActive) {
      await _repository.endActivity(_currentActivity!.id!, DateTime.now());
    }

    _isTracking = false;
    _currentActivity = null;
    _currentSessionId = null;

    // Stop auto-save timer
    _stopAutoSaveTimer();

    // Stop sync timer
    _stopSyncTimer();

    // Stop native tracking
    await _platformService.stopActivityTracking();

    debugPrint('[ACTIVITY] Tracking stopped');
    notifyListeners();
  }

  /// Save current activity state when app is paused or closed
  /// This ensures we have an accurate end time for recovery
  Future<void> saveStateOnPause() async {
    if (_isTracking && _currentActivity != null) {
      await _updateCurrentActivity();
      debugPrint('[ACTIVITY] State saved on app pause');
    }
  }

  Future<void> _handleActivityChange(ActivityChangeEvent event) async {
    debugPrint(
      '[ACTIVITY] 📥 Activity change event received: ${event.appName} - ${event.windowTitle}',
    );
    debugPrint(
      '[ACTIVITY] Tracking state: isTracking=$_isTracking, sessionId=$_currentSessionId',
    );

    if (!_isTracking) {
      debugPrint('[ACTIVITY] ⚠️  Ignoring event - tracking is not active');
      return;
    }

    await _recordActivity(
      appName: event.appName,
      windowTitle: event.windowTitle,
      bundleId: event.bundleId,
      timestamp: event.timestamp,
    );
  }

  /// Records a new activity when the active window changes.
  ///
  /// LOGIC:
  /// - If same app+title is already being tracked in memory → no-op (duplicate event)
  /// - If app or title changed → end the previous activity, start a new one
  /// - Every title change within the same app creates a SEPARATE activity record
  ///   so time per screen (e.g. VS Code Settings vs VS Code editor) is tracked independently
  ///
  /// Example: VS Code main (2m) → VS Code Settings (1m) → VS Code main (3m)
  ///   3 separate DB records, each with accurate start/end times
  Future<void> _recordActivity({
    required String appName,
    String? windowTitle,
    String? bundleId,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();

    // If the current in-memory activity is the SAME app and title → nothing changed
    // (duplicate event from the 2-second polling or app-activation firing twice)
    if (_currentActivity != null &&
        _currentActivity!.appName == appName &&
        _currentActivity!.windowTitle == windowTitle) {
      // Same window — do nothing; auto-save timer will keep end_time updated
      return;
    }

    // App or window title changed — end the previous activity
    if (_currentActivity != null &&
        _currentActivity!.isActive &&
        _currentActivity!.id != null) {
      await _repository.endActivity(_currentActivity!.id!, now);
      debugPrint(
        '[ACTIVITY] Ended: ${_currentActivity!.appName} - ${_currentActivity!.windowTitle} '
        '(${now.difference(_currentActivity!.startTime).inSeconds}s)',
      );
    }

    // Start a fresh activity record for the new app+window combination
    final newActivity = AppActivity(
      sessionId: _currentSessionId,
      appName: appName,
      windowTitle: windowTitle,
      bundleId: bundleId,
      startTime: now,
    );

    final activityId = await _repository.insertActivity(newActivity);
    _currentActivity = newActivity.copyWith(id: activityId);

    debugPrint('[ACTIVITY] Started: $appName - $windowTitle');
    notifyListeners();
  }

  /// Get daily activity summary - ONLY activities linked to timesheet sessions
  Future<DailyActivity> getDailyActivity(DateTime date) async {
    final activities = await _repository.getActivitiesForDateWithSessions(date);
    return DailyActivity(date: date, activities: activities);
  }

  /// Get timeline blocks - ONLY for activities during working hours
  /// FIXED: Properly recalculates duration when merging activities
  Future<List<ActivityBlock>> getTimelineBlocks(DateTime date) async {
    final activities = await _repository.getActivitiesForDateWithSessions(date);
    if (activities.isEmpty) return [];

    final List<ActivityBlock> blocks = [];
    AppActivity? currentBlock;

    for (final activity in activities) {
      if (currentBlock == null) {
        currentBlock = activity;
      } else {
        final blockEndTime = currentBlock.endTime ?? DateTime.now();
        blocks.add(
          ActivityBlock(
            startTime: currentBlock.startTime,
            endTime: blockEndTime,
            appName: currentBlock.appName,
            windowTitle: currentBlock.windowTitle,
            activityType: currentBlock.activityType,
            duration: blockEndTime.difference(currentBlock.startTime),
          ),
        );
        currentBlock = activity;
      }
    }

    if (currentBlock != null) {
      final blockEndTime = currentBlock.endTime ?? DateTime.now();
      blocks.add(
        ActivityBlock(
          startTime: currentBlock.startTime,
          endTime: blockEndTime,
          appName: currentBlock.appName,
          windowTitle: currentBlock.windowTitle,
          activityType: currentBlock.activityType,
          duration: blockEndTime.difference(currentBlock.startTime),
        ),
      );
    }

    return blocks;
  }

  Future<Map<int, List<AppActivity>>> getActivitiesByHour(DateTime date) async {
    final activities = await _repository.getActivitiesForDateWithSessions(date);
    final Map<int, List<AppActivity>> hourlyActivities = {};

    for (final activity in activities) {
      final hour = activity.startTime.hour;
      hourlyActivities[hour] = hourlyActivities[hour] ?? [];
      hourlyActivities[hour]!.add(activity);
    }

    return hourlyActivities;
  }

  /// Get activities for a specific session ID
  /// Works with both int (desktop) and String (web) session IDs
  Future<List<AppActivity>> getActivitiesForSession(dynamic sessionId) async {
    try {
      debugPrint('[ACTIVITY] Fetching activities for session: $sessionId');
      final activities = await _repository.getActivitiesBySession(sessionId);
      debugPrint(
        '[ACTIVITY] Found ${activities.length} activities for session $sessionId',
      );
      return activities;
    } catch (e, stackTrace) {
      debugPrint(
        '[ACTIVITY] Error fetching activities for session $sessionId: $e',
      );
      debugPrint('[ACTIVITY] Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get work sessions for a given date (based on timesheet sessions)
  /// FIXED: Uses actual timesheet session times, not activity times
  /// FIXED: Clamps multi-day sessions to the queried day's boundaries
  ///        so "Mixed Activities" only shows activities for that exact day.
  Future<List<WorkSession>> getWorkSessions(DateTime date) async {
    final activities = await _repository.getActivitiesForDateWithSessions(date);
    if (activities.isEmpty) return [];

    // Boundaries for the queried date (local time)
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // FIXED: Get actual attendance sessions to use their check-in/check-out times
    // Use injected repository which handles web/desktop transparently
    final sessionMaps = await _attendanceRepository.getSessionsForDate(date);

    // Create a map of session ID to session times
    // FIXED: Clamp times to the queried day so multi-day sessions only
    //        contribute their portion that falls within today's boundaries.
    final Map<dynamic, Map<String, DateTime>> sessionTimes = {};
    for (final sessionMap in sessionMaps) {
      final sessionId = sessionMap['id']; // dynamic (int or String)
      final rawCheckIn = DateTime.parse(sessionMap['check_in_time'] as String);
      final rawCheckOut = sessionMap['check_out_time'] != null
          ? DateTime.parse(sessionMap['check_out_time'] as String)
          : DateTime.now();

      // Clamp to the queried day: sessions that started yesterday or end
      // tomorrow are limited to just the slice that falls within today.
      final clampedCheckIn = rawCheckIn.isBefore(startOfDay)
          ? startOfDay
          : rawCheckIn;
      final clampedCheckOut = rawCheckOut.isAfter(endOfDay)
          ? endOfDay
          : rawCheckOut;

      sessionTimes[sessionId] = {
        'checkIn': clampedCheckIn,
        'checkOut': clampedCheckOut,
      };
    }

    return _groupIntoSessionsBySessionId(activities, sessionTimes);
  }

  /// Group activities by attendance session ID
  /// FIXED: Uses timesheet session times for accurate duration
  List<WorkSession> _groupIntoSessionsBySessionId(
    List<AppActivity> activities,
    Map<dynamic, Map<String, DateTime>> sessionTimes,
  ) {
    if (activities.isEmpty) return [];

    // Group by session ID only
    final Map<dynamic, List<AppActivity>> sessionGroups = {};

    for (final activity in activities) {
      final sessionId = activity.sessionId;
      if (!sessionGroups.containsKey(sessionId)) {
        sessionGroups[sessionId] = [];
      }
      sessionGroups[sessionId]!.add(activity);
    }

    // Create work sessions
    List<WorkSession> sessions = [];
    for (final entry in sessionGroups.entries) {
      if (entry.value.isNotEmpty && entry.key != null) {
        entry.value.sort((a, b) => a.startTime.compareTo(b.startTime));
        final sessionId = entry.key;
        final times = sessionTimes[sessionId];
        if (times != null) {
          sessions.add(
            _createWorkSession(
              entry.value,
              sessionId,
              times['checkIn']!,
              times['checkOut']!,
            ),
          );
        }
      }
    }

    sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
    return sessions;
  }

  /// Create work session from activities
  /// FIXED: Use actual timesheet check-in/check-out times
  WorkSession _createWorkSession(
    List<AppActivity> activities,
    dynamic sessionId,
    DateTime checkInTime,
    DateTime checkOutTime,
  ) {
    // FIXED: Use timesheet session times, NOT activity times
    // This ensures activity tracking duration exactly matches timesheet
    final sessionDuration = checkOutTime.difference(checkInTime);

    final segments = _divideIntoSegments(activities, checkInTime, checkOutTime);

    return WorkSession(
      sessionId: sessionId,
      startTime: checkInTime, // Use timesheet check-in
      endTime: checkOutTime, // Use timesheet check-out
      totalDuration: sessionDuration, // Timesheet session duration
      segments: segments,
    );
  }

  /// Divide into 15-minute segments
  List<TimeSegment> _divideIntoSegments(
    List<AppActivity> activities,
    DateTime sessionStart,
    DateTime sessionEnd,
  ) {
    List<TimeSegment> segments = [];
    DateTime segmentStart = sessionStart;

    debugPrint(
      'DEBUG: Dividing session $sessionStart to $sessionEnd into segments. Activities: ${activities.length}',
    );
    if (activities.isNotEmpty) {
      debugPrint(
        'DEBUG: First activity start: ${activities.first.startTime}, isUtc: ${activities.first.startTime.isUtc}',
      );
      debugPrint(
        'DEBUG: Session start: $sessionStart, isUtc: ${sessionStart.isUtc}',
      );
    }

    while (segmentStart.isBefore(sessionEnd)) {
      DateTime segmentEnd = _getNext15MinuteBoundary(segmentStart);
      if (segmentEnd.isAfter(sessionEnd)) {
        segmentEnd = sessionEnd;
      }

      final segmentActivities = activities.where((activity) {
        return _activitiesOverlap(
          activity.startTime,
          activity.endTime ?? DateTime.now(),
          segmentStart,
          segmentEnd,
        );
      }).toList();

      if (segmentActivities.isNotEmpty) {
        debugPrint(
          'DEBUG: Segment $segmentStart has ${segmentActivities.length} activities',
        );
        final primary = _findPrimaryActivity(
          segmentActivities,
          segmentStart,
          segmentEnd,
        );
        segments.add(
          TimeSegment(
            startTime: segmentStart,
            endTime: segmentEnd,
            activities: segmentActivities,
            primaryActivity: primary,
          ),
        );
      }

      segmentStart = segmentEnd;
    }

    return segments;
  }

  DateTime _getNext15MinuteBoundary(DateTime time) {
    final minute = time.minute;
    final nextBoundary = ((minute ~/ 15) + 1) * 15;

    if (nextBoundary >= 60) {
      return DateTime(time.year, time.month, time.day, time.hour + 1);
    } else {
      return DateTime(time.year, time.month, time.day, time.hour, nextBoundary);
    }
  }

  bool _activitiesOverlap(
    DateTime start1,
    DateTime end1,
    DateTime start2,
    DateTime end2,
  ) {
    return start1.isBefore(end2) && end1.isAfter(start2);
  }

  AppActivity _findPrimaryActivity(
    List<AppActivity> activities,
    DateTime segmentStart,
    DateTime segmentEnd,
  ) {
    AppActivity? primary;
    Duration maxDuration = Duration.zero;

    for (final activity in activities) {
      final activityEnd = activity.endTime ?? DateTime.now();
      final overlapStart = activity.startTime.isAfter(segmentStart)
          ? activity.startTime
          : segmentStart;
      final overlapEnd = activityEnd.isBefore(segmentEnd)
          ? activityEnd
          : segmentEnd;

      final overlapDuration = overlapEnd.difference(overlapStart);

      if (overlapDuration > maxDuration) {
        maxDuration = overlapDuration;
        primary = activity;
      }
    }

    return primary ?? activities.first;
  }

  /// Update session ID for current and future activities
  void setSessionId(dynamic sessionId) {
    _currentSessionId = sessionId;
    if (_currentActivity != null) {
      _currentActivity = _currentActivity!.copyWith(sessionId: sessionId);
    }
    notifyListeners();
  }

  // clearAllActivities() removed — deleting activity data is not a supported operation.

  /// Set current month for calendar view
  Future<void> setMonth(DateTime month) async {
    if (_currentMonth.year == month.year &&
        _currentMonth.month == month.month) {
      return;
    }

    _currentMonth = month;
    _hasLoadedMonthOnce =
        false; // Reset for new month - show loading on first load
    notifyListeners();
    await _loadMonthStats();
  }

  /// Refresh month stats and notify all day columns to reload
  /// ENHANCED: Forces complete data reload from database
  /// FIXED: Silent refresh after first load - no loading indicator on subsequent refreshes
  Future<void> refreshMonth() async {
    debugPrint('[ACTIVITY] Refresh requested - reloading all data');

    _refreshCounter++; // Increment to trigger reload in day columns

    // Only show loading state if this is the first load
    // Subsequent refreshes update silently to avoid UI flicker
    if (!_hasLoadedMonthOnce) {
      _isLoadingMonth = true;
      notifyListeners(); // Notify immediately so UI can show loading state
    }

    // Force reload of month stats from database
    await _loadMonthStats();

    debugPrint('[ACTIVITY] Refresh complete - counter: $_refreshCounter');
  }

  /// Load month statistics directly from timesheet repository
  /// FIX: This ensures activity tracking page shows EXACT same times as timesheet
  /// Previously calculated from activities which caused time mismatches
  /// ENHANCED: Silent updates after first load to prevent UI flicker
  Future<void> _loadMonthStats() async {
    // Only show loading state on first load
    if (!_hasLoadedMonthOnce) {
      _isLoadingMonth = true;
      notifyListeners();
    }

    try {
      final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month);
      final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);

      // FIX: Get work and break durations directly from attendance repository
      // This is the SINGLE SOURCE OF TRUTH - same data shown in timesheet
      final workDuration = await _attendanceRepository.getPeriodWorkDuration(
        start: startOfMonth,
        end: endOfMonth,
      );

      // Get break duration for the month
      int totalBreakSeconds = 0;
      final Set<dynamic> processedSessionIds = {};

      // Iterate through days to get all sessions
      final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
      for (int day = 1; day <= lastDay.day; day++) {
        final date = DateTime(_currentMonth.year, _currentMonth.month, day);
        try {
          final sessions = await _attendanceRepository.getSessionsForDate(date);
          for (var session in sessions) {
            final sessionId =
                session['id']; // Can be int (SQLite) or String (Supabase UUID)
            if (!processedSessionIds.contains(sessionId)) {
              final breaks = await _attendanceRepository.getSessionBreaks(
                sessionId,
              );
              for (var breakPeriod in breaks) {
                totalBreakSeconds += breakPeriod.duration.inSeconds;
              }
              processedSessionIds.add(sessionId);
            }
          }
        } catch (e) {
          debugPrint('[ACTIVITY STATS] Error loading day $day: $e');
        }
      }

      _monthStats = {
        'total_work_seconds': workDuration.inSeconds,
        'total_break_seconds': totalBreakSeconds,
      };
      _isLoadingMonth = false;
      _hasLoadedMonthOnce = true; // Mark that we've loaded at least once
      notifyListeners();
    } catch (e) {
      debugPrint('[ACTIVITY STATS] Error loading month stats: $e');
      _isLoadingMonth = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    _stopAutoSaveTimer();
    _stopSyncTimer();
    super.dispose();
  }
}
