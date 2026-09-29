import 'package:flutter/foundation.dart';
import 'attendance_repository.dart';
import '../../../../core/network/supabase_sync_service.dart';
import '../../../auth/data/repository/user_repository.dart';
import '../models/attendance_state.dart';
import '../../../../core/constants/supabase_config.dart';

/// Wrapper around AttendanceRepository that adds sync functionality
/// Extends AttendanceRepository to maintain compatibility with existing code
class SyncedAttendanceRepository extends AttendanceRepository {
  final SupabaseSyncService _syncService;
  final UserRepository _userRepository;

  SyncedAttendanceRepository({
    required AttendanceRepository repository,
    required SupabaseSyncService syncService,
    required UserRepository userRepository,
  }) : _syncService = syncService,
       _userRepository = userRepository,
       super(repository.db);

  // Get current local user ID from Supabase auth
  Future<int?> _getCurrentUserId() async {
    try {
      final supabaseUserId = SupabaseConfig.client.auth.currentUser?.id;
      if (supabaseUserId == null) return null;

      final user = await _userRepository.getUserByUuid(supabaseUserId);
      return user?['id'] as int?;
    } catch (e) {
      // Silent error - return null if user lookup fails
      return null;
    }
  }

  /// Create session with user_id and sync to Supabase
  @override
  Future<int> createSession(
    DateTime checkInTime,
    EventSource source, {
    int? userId,
    int? continuationOfSessionId,
    String? continuationReason,
  }) async {
    try {
      // Get user ID if not provided
      final effectiveUserId = userId ?? await _getCurrentUserId();

      // Create session in local DB
      final sessionId = await super.createSession(
        checkInTime,
        source,
        userId: effectiveUserId,
        continuationOfSessionId: continuationOfSessionId,
        continuationReason: continuationReason,
      );

      // Trigger sync asynchronously (don't await to avoid blocking)
      _syncService
          .syncAttendanceSession(localId: sessionId, operation: 'insert')
          .catchError((e) => null); // Silent error

      return sessionId;
    } catch (e) {
      // Rethrow critical errors
      rethrow;
    }
  }

  /// Close session and sync
  @override
  Future<void> closeSession(
    int sessionId,
    DateTime checkOutTime,
    EventSource source,
  ) async {
    await super.closeSession(sessionId, checkOutTime, source);

    // Sync the updated session
    _syncService
        .syncAttendanceSession(localId: sessionId, operation: 'update')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync session $sessionId: $e');
          return null;
        });
  }

  /// Start break and sync
  /// Start break and sync
  @override
  Future<int> startBreak(
    int sessionId,
    DateTime breakStartTime, {
    int? continuationOfBreakId,
    int? userId,
  }) async {
    // Get user ID if not provided
    final effectiveUserId = userId ?? await _getCurrentUserId();

    final breakId = await super.startBreak(
      sessionId,
      breakStartTime,
      continuationOfBreakId: continuationOfBreakId,
      userId: effectiveUserId,
    );

    // Sync the break period
    _syncService
        .syncBreakPeriod(localId: breakId, operation: 'insert')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync break $breakId: $e');
          return null;
        });

    return breakId;
  }

  /// End break and sync
  @override
  Future<int?> endBreak(DateTime breakEndTime) async {
    final breakId = await super.endBreak(breakEndTime);

    // Sync the specific break period if it was ended successfully
    if (breakId != null) {
      _syncService
          .syncBreakPeriod(localId: breakId, operation: 'update')
          .catchError((e) {
            debugPrint('[SYNC] Failed to sync break $breakId: $e');
            return null;
          });
    }

    return breakId;
  }

  /// Add retroactive break and sync
  @override
  Future<int> addRetroactiveBreak(
    int sessionId,
    DateTime breakStart,
    DateTime breakEnd, {
    String? note,
    int? userId,
  }) async {
    // Get user ID if not provided
    final effectiveUserId = userId ?? await _getCurrentUserId();

    final breakId = await super.addRetroactiveBreak(
      sessionId,
      breakStart,
      breakEnd,
      note: note,
      userId: effectiveUserId,
    );

    // Sync the specific break period
    _syncService
        .syncBreakPeriod(localId: breakId, operation: 'insert')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync break $breakId: $e');
          return null;
        });

    return breakId;
  }

  /// Add work during sleep and sync
  @override
  Future<int> addWorkDuringSleep(
    int sessionId,
    DateTime sleepStart,
    DateTime wakeTime,
    String note, {
    int? userId,
  }) async {
    // Get user ID if not provided
    final effectiveUserId = userId ?? await _getCurrentUserId();

    final workId = await super.addWorkDuringSleep(
      sessionId,
      sleepStart,
      wakeTime,
      note,
      userId: effectiveUserId,
    );

    // Sync the specific work-during-sleep period
    _syncService
        .syncWorkDuringSleep(localId: workId, operation: 'insert')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync work-during-sleep $workId: $e');
          return null;
        });

    return workId;
  }

  /// Update session last_seen_time and sync to Supabase
  /// This is critical for power cut recovery - ensures cloud has latest heartbeat
  @override
  Future<void> updateSessionLastSeen(
    dynamic sessionId,
    DateTime lastSeenTime,
  ) async {
    // Update local database first
    await super.updateSessionLastSeen(sessionId, lastSeenTime);

    // Sync to Supabase asynchronously (don't block the auto-save timer)
    // This ensures that even if device crashes, Supabase has recent heartbeat
    _syncService
        .syncAttendanceSession(localId: sessionId, operation: 'update')
        .catchError((e) {
          // Don't fail the auto-save if sync fails - local DB is primary
          debugPrint('[SYNC] Failed to sync last_seen_time: $e');
          return null;
        });
  }
}
