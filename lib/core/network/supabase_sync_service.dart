import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../constants/supabase_config.dart';

class SupabaseSyncService {
  final Database _db;
  final SupabaseClient _supabase = SupabaseConfig.client;
  final Uuid _uuidGenerator = const Uuid();

  SupabaseSyncService(this._db);

  // Get current user ID
  String? get currentUserId => _supabase.auth.currentUser?.id;

  // Get local user ID from current Supabase user
  Future<int?> _getLocalUserId() async {
    final uuid = currentUserId;
    if (uuid == null) return null;

    final results = await _db.query(
      'users',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [uuid],
    );

    return results.isNotEmpty ? results.first['id'] as int : null;
  }

  /// Helper to ensure a time string is formatted as Local Iso8601 (no 'Z')
  /// Used for fields that must be stored as Local Time in Supabase
  String? _ensureLocalString(dynamic dateStr) {
    if (dateStr == null) return null;
    try {
      // Parse the string (handles both local and UTC inputs)
      final dt = DateTime.parse(dateStr.toString());
      // Convert to Local time and format without 'Z'
      return dt.toLocal().toIso8601String();
    } catch (_) {
      return dateStr.toString();
    }
  }

  /// RESTORED: Legacy helper used by other methods
  /// Now maps to _ensureLocalString to enforce strictness everywhere
  String? _preserveTimeString(dynamic dateStr) => _ensureLocalString(dateStr);

  /// Helper to ensure a time string is formatted as UTC Iso8601
  /// Used to sanitize SQLite data before sending to Supabase (for UTC fields only)
  String? _ensureUtcString(dynamic dateStr) {
    if (dateStr == null) return null;
    try {
      // Parse using local system notion (if no offset)
      final dt = DateTime.parse(dateStr.toString());
      // Convert to UTC string (e.g. "2023-10-10T04:30:00.000Z")
      return dt.toUtc().toIso8601String();
    } catch (_) {
      return dateStr.toString();
    }
  }

  // ============================================================================
  // ATTENDANCE SESSIONS SYNC
  // ============================================================================

  Future<String?> syncAttendanceSession({
    required int localId,
    required String operation, // 'insert', 'update', 'delete'
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final session = await _db.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [localId],
      );

      if (session.isEmpty) return null;

      final data = session.first;
      String? uuid = data['uuid'] as String?;

      // Generate UUID if not exists
      if (uuid == null) {
        uuid = _uuidGenerator.v4();
        await _db.update(
          'attendance_sessions',
          {'uuid': uuid},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      if (operation == 'delete' || data['is_deleted'] == 1) {
        // Soft delete in Supabase
        await _supabase
            .from('attendance_sessions')
            .update({
              'is_deleted': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', uuid);
      } else {
        // Prepare data for Supabase
        // Sanitize timestamps - FORCE strict formats
        final supabaseData = {
          'id': uuid,
          'user_id': userId,
          'check_in_time': _ensureLocalString(
            data['check_in_time'],
          ), // Force Local
          'check_out_time': _ensureLocalString(
            data['check_out_time'],
          ), // Force Local
          'check_in_time_utc': _ensureUtcString(
            data['check_in_time_utc'],
          ), // Ensure Clean UTC
          'check_out_time_utc': _ensureUtcString(
            data['check_out_time_utc'],
          ), // Ensure Clean UTC
          'check_in_source': data['check_in_source'],
          'check_out_source': data['check_out_source'],
          'total_work_seconds': data['total_work_seconds'],
          'is_closed': data['is_closed'] == 1,
          'last_seen_time': _ensureUtcString(
            data['last_seen_time'],
          ), // Ensure UTC
          'continuation_reason': data['continuation_reason'],
          'original_timezone': data['original_timezone'],
          'local_id': localId.toString(),
        };

        // Upsert to Supabase
        await _supabase.from('attendance_sessions').upsert(supabaseData);
      }

      // Update synced_at timestamp
      await _db.update(
        'attendance_sessions',
        {'synced_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [localId],
      );

      return uuid;
    } catch (e) {
      debugPrint('Error syncing attendance session: $e');
      await _addToSyncQueue(
        tableName: 'attendance_sessions',
        recordId: localId,
        operation: operation,
        error: e.toString(),
      );
      rethrow;
    }
  }

  // ============================================================================
  // HELPER: ENSURE SESSION IS SYNCED
  // ============================================================================

  /// Ensures that a session is synced to Supabase before syncing child records
  /// This prevents foreign key constraint violations
  Future<String?> _ensureSessionSynced(int sessionId) async {
    try {
      final session = await _db.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      if (session.isEmpty) return null;

      final data = session.first;
      String? uuid = data['uuid'] as String?;

      // Check if session needs syncing
      final syncedAt = data['synced_at'] as String?;
      final updatedAt = data['updated_at'] as String?;

      bool needsSync = syncedAt == null;
      if (!needsSync && updatedAt != null) {
        // Check if updated after last sync
        final syncedTime = DateTime.parse(syncedAt);
        final updatedTime = DateTime.parse(updatedAt);
        needsSync = updatedTime.isAfter(syncedTime);
      }

      // Sync the session if needed
      if (needsSync || uuid == null) {
        debugPrint(
          '[SYNC] Syncing parent session $sessionId before child record',
        );
        uuid = await syncAttendanceSession(
          localId: sessionId,
          operation: data['is_deleted'] == 1 ? 'delete' : 'update',
        );
      }

      return uuid;
    } catch (e) {
      debugPrint('Error ensuring session synced: $e');
      rethrow;
    }
  }

  // ============================================================================
  // BREAK PERIODS SYNC
  // ============================================================================

  Future<String?> syncBreakPeriod({
    required int localId,
    required String operation,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final breakPeriod = await _db.query(
        'break_periods',
        where: 'id = ?',
        whereArgs: [localId],
      );

      if (breakPeriod.isEmpty) return null;

      final data = breakPeriod.first;
      String? uuid = data['uuid'] as String?;

      if (uuid == null) {
        uuid = _uuidGenerator.v4();
        await _db.update(
          'break_periods',
          {'uuid': uuid},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      // Get session UUID - ensure session is synced first
      final sessionId = data['session_id'] as int?;
      String? sessionUuid;
      if (sessionId != null) {
        // Ensure parent session is synced before syncing break period
        sessionUuid = await _ensureSessionSynced(sessionId);
        if (sessionUuid == null) {
          throw Exception(
            'Session $sessionId not found or failed to sync - cannot sync break period',
          );
        }
      }

      if (operation == 'delete' || data['is_deleted'] == 1) {
        await _supabase
            .from('break_periods')
            .update({
              'is_deleted': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', uuid);
      } else {
        final supabaseData = {
          'id': uuid,
          'session_id': sessionUuid,
          'user_id': userId,
          'break_start_time': _preserveTimeString(data['break_start_time']),
          'break_end_time': _preserveTimeString(data['break_end_time']),
          'break_start_time_utc': _ensureUtcString(
            data['break_start_time_utc'],
          ),
          'break_end_time_utc': _ensureUtcString(data['break_end_time_utc']),
          'duration_seconds': data['duration_seconds'],
          'note': data['note'],
          'local_id': localId.toString(),
        };

        await _supabase.from('break_periods').upsert(supabaseData);
      }

      await _db.update(
        'break_periods',
        {'synced_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [localId],
      );

      return uuid;
    } catch (e) {
      debugPrint('Error syncing break period: $e');
      await _addToSyncQueue(
        tableName: 'break_periods',
        recordId: localId,
        operation: operation,
        error: e.toString(),
      );
      rethrow;
    }
  }

  // ============================================================================
  // APP ACTIVITIES SYNC
  // ============================================================================

  Future<String?> syncAppActivity({
    required int localId,
    required String operation,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final activity = await _db.query(
        'app_activities',
        where: 'id = ?',
        whereArgs: [localId],
      );

      if (activity.isEmpty) return null;

      final data = activity.first;
      String? uuid = data['uuid'] as String?;

      if (uuid == null) {
        uuid = _uuidGenerator.v4();
        await _db.update(
          'app_activities',
          {'uuid': uuid},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      // Get session UUID - ensure session is synced first
      final sessionId = data['session_id'] as int?;
      String? sessionUuid;
      if (sessionId != null) {
        // Ensure parent session is synced before syncing app activity
        sessionUuid = await _ensureSessionSynced(sessionId);
        if (sessionUuid == null) {
          throw Exception(
            'Session $sessionId not found or failed to sync - cannot sync app activity',
          );
        }
      }

      if (operation == 'delete' || data['is_deleted'] == 1) {
        await _supabase
            .from('app_activities')
            .update({
              'is_deleted': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', uuid);
      } else {
        final supabaseData = {
          'id': uuid,
          'session_id': sessionUuid,
          'user_id': userId,
          'app_name': data['app_name'],
          'window_title': data['window_title'],
          'bundle_id': data['bundle_id'],
          'start_time': _preserveTimeString(data['start_time']),
          'end_time': _preserveTimeString(data['end_time']),
          'start_time_utc': _ensureUtcString(data['start_time_utc']),
          'end_time_utc': _ensureUtcString(data['end_time_utc']),
          'duration_seconds': data['duration_seconds'],
          'activity_type': data['activity_type'],
          'local_id': localId.toString(),
        };

        await _supabase.from('app_activities').upsert(supabaseData);
      }

      await _db.update(
        'app_activities',
        {'synced_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [localId],
      );

      return uuid;
    } catch (e) {
      debugPrint('Error syncing app activity: $e');
      await _addToSyncQueue(
        tableName: 'app_activities',
        recordId: localId,
        operation: operation,
        error: e.toString(),
      );
      rethrow;
    }
  }

  // ============================================================================
  // WORK DURING SLEEP SYNC
  // ============================================================================

  Future<String?> syncWorkDuringSleep({
    required int localId,
    required String operation,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final workSleep = await _db.query(
        'work_during_sleep_periods',
        where: 'id = ?',
        whereArgs: [localId],
      );

      if (workSleep.isEmpty) return null;

      final data = workSleep.first;
      String? uuid = data['uuid'] as String?;

      if (uuid == null) {
        uuid = _uuidGenerator.v4();
        await _db.update(
          'work_during_sleep_periods',
          {'uuid': uuid},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      // Get session UUID - ensure session is synced first
      final sessionId = data['session_id'] as int?;
      String? sessionUuid;
      if (sessionId != null) {
        // Ensure parent session is synced before syncing work during sleep
        sessionUuid = await _ensureSessionSynced(sessionId);
        if (sessionUuid == null) {
          throw Exception(
            'Session $sessionId not found or failed to sync - cannot sync work during sleep period',
          );
        }
      }

      if (operation == 'delete' || data['is_deleted'] == 1) {
        await _supabase
            .from('work_during_sleep_periods')
            .update({
              'is_deleted': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', uuid);
      } else {
        final supabaseData = {
          'id': uuid,
          'session_id': sessionUuid,
          'user_id': userId,
          'sleep_start_time': _preserveTimeString(data['sleep_start_time']),
          'wake_time': _preserveTimeString(data['wake_time']),
          'sleep_start_time_utc': _ensureUtcString(
            data['sleep_start_time_utc'],
          ),
          'wake_time_utc': _ensureUtcString(data['wake_time_utc']),
          'duration_seconds': data['duration_seconds'],
          'note': data['note'],
          'local_id': localId.toString(),
        };

        await _supabase.from('work_during_sleep_periods').upsert(supabaseData);
      }

      await _db.update(
        'work_during_sleep_periods',
        {'synced_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [localId],
      );

      return uuid;
    } catch (e) {
      debugPrint('Error syncing work during sleep: $e');
      await _addToSyncQueue(
        tableName: 'work_during_sleep_periods',
        recordId: localId,
        operation: operation,
        error: e.toString(),
      );
      rethrow;
    }
  }

  // ============================================================================
  // SYNC ALL PENDING RECORDS
  // ============================================================================

  Future<void> syncAll() async {
    try {
      final localUserId = await _getLocalUserId();
      if (localUserId == null) return;

      // Sync attendance sessions
      final sessions = await _db.query(
        'attendance_sessions',
        where: 'user_id = ? AND (synced_at IS NULL OR synced_at < updated_at)',
        whereArgs: [localUserId],
      );

      for (final session in sessions) {
        try {
          await syncAttendanceSession(
            localId: session['id'] as int,
            operation: session['is_deleted'] == 1 ? 'delete' : 'update',
          );
        } catch (e) {
          debugPrint('Failed to sync session ${session['id']}: $e');
        }
      }

      // Sync break periods
      final breaks = await _db.query(
        'break_periods',
        where: 'user_id = ? AND (synced_at IS NULL OR synced_at < updated_at)',
        whereArgs: [localUserId],
      );

      for (final breakPeriod in breaks) {
        try {
          await syncBreakPeriod(
            localId: breakPeriod['id'] as int,
            operation: breakPeriod['is_deleted'] == 1 ? 'delete' : 'update',
          );
        } catch (e) {
          debugPrint('Failed to sync break ${breakPeriod['id']}: $e');
        }
      }

      // Sync app activities
      final activities = await _db.query(
        'app_activities',
        where: 'user_id = ? AND (synced_at IS NULL OR synced_at < updated_at)',
        whereArgs: [localUserId],
        limit: 100, // Batch activities to avoid overwhelming the server
      );

      for (final activity in activities) {
        try {
          await syncAppActivity(
            localId: activity['id'] as int,
            operation: activity['is_deleted'] == 1 ? 'delete' : 'update',
          );
        } catch (e) {
          debugPrint('Failed to sync activity ${activity['id']}: $e');
        }
      }

      // Sync work during sleep
      final workSleep = await _db.query(
        'work_during_sleep_periods',
        where: 'user_id = ? AND (synced_at IS NULL OR synced_at < updated_at)',
        whereArgs: [localUserId],
      );

      for (final work in workSleep) {
        try {
          await syncWorkDuringSleep(
            localId: work['id'] as int,
            operation: work['is_deleted'] == 1 ? 'delete' : 'update',
          );
        } catch (e) {
          debugPrint('Failed to sync work during sleep ${work['id']}: $e');
        }
      }

      // Process sync queue for failed items
      await _processSyncQueue();
    } catch (e) {
      debugPrint('Error in syncAll: $e');
      rethrow;
    }
  }

  // ============================================================================
  // SYNC QUEUE MANAGEMENT
  // ============================================================================

  Future<void> _addToSyncQueue({
    required String tableName,
    required int recordId,
    required String operation,
    required String error,
  }) async {
    try {
      final localUserId = await _getLocalUserId();
      if (localUserId == null) return;

      // Get record UUID if exists
      final record = await _db.query(
        tableName,
        columns: ['uuid'],
        where: 'id = ?',
        whereArgs: [recordId],
      );

      final recordUuid = record.isNotEmpty
          ? record.first['uuid'] as String?
          : null;

      await _db.insert('sync_queue', {
        'user_id': localUserId,
        'table_name': tableName,
        'record_id': recordId,
        'record_uuid': recordUuid,
        'operation': operation,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'last_error': error,
      });
    } catch (e) {
      debugPrint('Error adding to sync queue: $e');
    }
  }

  Future<void> _processSyncQueue() async {
    try {
      final localUserId = await _getLocalUserId();
      if (localUserId == null) return;

      final queueItems = await _db.query(
        'sync_queue',
        where: 'user_id = ? AND synced_at IS NULL AND retry_count < ?',
        whereArgs: [localUserId, 5], // Max 5 retries
        orderBy: 'created_at ASC',
        limit: 50,
      );

      for (final item in queueItems) {
        final tableName = item['table_name'] as String;
        final recordId = item['record_id'] as int;
        final operation = item['operation'] as String;
        final queueId = item['id'] as int;

        try {
          switch (tableName) {
            case 'attendance_sessions':
              await syncAttendanceSession(
                localId: recordId,
                operation: operation,
              );
              break;
            case 'break_periods':
              await syncBreakPeriod(localId: recordId, operation: operation);
              break;
            case 'app_activities':
              await syncAppActivity(localId: recordId, operation: operation);
              break;
            case 'work_during_sleep_periods':
              await syncWorkDuringSleep(
                localId: recordId,
                operation: operation,
              );
              break;
          }

          // Mark as synced
          await _db.update(
            'sync_queue',
            {'synced_at': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [queueId],
          );
        } catch (e) {
          // Increment retry count
          await _db.update(
            'sync_queue',
            {
              'retry_count': (item['retry_count'] as int) + 1,
              'last_error': e.toString(),
            },
            where: 'id = ?',
            whereArgs: [queueId],
          );
          debugPrint('Failed to process queue item $queueId: $e');
        }
      }
    } catch (e) {
      debugPrint('Error processing sync queue: $e');
    }
  }

  // Get pending sync count
  Future<int> getPendingSyncCount() async {
    try {
      final localUserId = await _getLocalUserId();
      if (localUserId == null) return 0;

      final result = await _db.rawQuery(
        '''
        SELECT COUNT(*) as count FROM sync_queue
        WHERE user_id = ? AND synced_at IS NULL
      ''',
        [localUserId],
      );

      return result.isNotEmpty ? result.first.values.first as int : 0;
    } catch (e) {
      debugPrint('Error getting pending sync count: $e');
      return 0;
    }
  }

  // Clear successfully synced queue items
  Future<void> clearSyncedQueue() async {
    try {
      await _db.delete('sync_queue', where: 'synced_at IS NOT NULL');
    } catch (e) {
      debugPrint('Error clearing synced queue: $e');
    }
  }

  // ============================================================================
  // PULL DATA FROM SUPABASE (DOWNLOAD)
  // ============================================================================

  /// Pull all data from Supabase for the current user
  /// This should be called when user logs in to sync cloud data to local DB
  Future<void> pullFromSupabase() async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        debugPrint('[PULL] No authenticated user');
        return;
      }

      final localUserId = await _getLocalUserId();
      if (localUserId == null) {
        debugPrint('[PULL] No local user ID found');
        return;
      }

      debugPrint('[PULL] Starting pull from Supabase for user: $userId');

      // Pull attendance sessions
      await _pullAttendanceSessions(userId, localUserId);

      // Pull break periods
      await _pullBreakPeriods(userId, localUserId);

      // Pull app activities
      await _pullAppActivities(userId, localUserId);

      // Pull work during sleep
      await _pullWorkDuringSleep(userId, localUserId);

      debugPrint('[PULL] ✅ Completed pull from Supabase');
    } catch (e) {
      debugPrint('[PULL] ❌ Error pulling from Supabase: $e');
      rethrow;
    }
  }

  Future<void> _pullAttendanceSessions(String userId, int localUserId) async {
    try {
      debugPrint('[PULL] Fetching attendance sessions...');

      final response = await _supabase
          .from('attendance_sessions')
          .select()
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('check_in_time', ascending: false);

      debugPrint('[PULL] Found ${response.length} attendance sessions');

      for (final session in response) {
        final uuid = session['id'] as String;

        // Check if session already exists locally
        final existing = await _db.query(
          'attendance_sessions',
          where: 'uuid = ?',
          whereArgs: [uuid],
        );

        final localData = {
          'uuid': uuid,
          'user_id': localUserId,
          'check_in_time': session['check_in_time'],
          'check_out_time': session['check_out_time'],
          'check_in_time_utc': session['check_in_time_utc'],
          'check_out_time_utc': session['check_out_time_utc'],
          'check_in_source': session['check_in_source'],
          'check_out_source': session['check_out_source'],
          'total_work_seconds': session['total_work_seconds'],
          'is_closed': session['is_closed'] ? 1 : 0,
          'last_seen_time': session['last_seen_time'],
          'continuation_reason': session['continuation_reason'],
          'original_timezone': session['original_timezone'],
          'synced_at': DateTime.now().toIso8601String(),
          'updated_at': session['updated_at'],
        };

        if (existing.isEmpty) {
          // Insert new session
          await _db.insert('attendance_sessions', localData);
          debugPrint('[PULL] ✅ Inserted session: $uuid');
        } else {
          // Update existing session if cloud version is newer
          final localUpdatedAt = existing.first['updated_at'] as String?;
          final cloudUpdatedAt = session['updated_at'] as String?;

          bool shouldUpdate = false;

          // Check updated_at
          if (cloudUpdatedAt != null &&
              (localUpdatedAt == null ||
                  DateTime.parse(
                    cloudUpdatedAt,
                  ).isAfter(DateTime.parse(localUpdatedAt)))) {
            shouldUpdate = true;
          }

          // CRITICAL FIX FOR POWER CUT RECOVERY:
          // For open sessions, always use whichever last_seen_time is NEWER
          // This handles both normal operation AND power cut recovery
          final localIsClosed = existing.first['is_closed'] == 1;
          final cloudIsClosed = session['is_closed'] == true;

          // For closed sessions, always trust cloud (no conflict possible)
          if (cloudIsClosed || localIsClosed) {
            shouldUpdate = true;
          } else {
            // Open session: Use whichever last_seen_time is newer
            final localLastSeenStr =
                existing.first['last_seen_time'] as String?;
            final cloudLastSeenStr = session['last_seen_time'] as String?;

            if (localLastSeenStr != null && cloudLastSeenStr != null) {
              try {
                final localLastSeen = DateTime.parse(localLastSeenStr);
                final cloudLastSeen = DateTime.parse(cloudLastSeenStr);

                // Compare and use the newer one
                if (cloudLastSeen.toUtc().isAfter(localLastSeen.toUtc())) {
                  shouldUpdate = true;
                } else {
                  shouldUpdate = false;
                }
              } catch (e) {
                debugPrint('[PULL] Error parsing last_seen_time: $e');
              }
            } else if (localLastSeenStr == null && cloudLastSeenStr != null) {
              shouldUpdate = true;
            } else if (localLastSeenStr != null && cloudLastSeenStr == null) {
              shouldUpdate = false;
            }
          }

          if (shouldUpdate) {
            await _db.update(
              'attendance_sessions',
              localData,
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
            debugPrint('[PULL] ✅ Updated session: $uuid');
          }
        }
      }
    } catch (e) {
      debugPrint('[PULL] Error pulling attendance sessions: $e');
      rethrow;
    }
  }

  Future<void> _pullBreakPeriods(String userId, int localUserId) async {
    try {
      debugPrint('[PULL] Fetching break periods...');

      final response = await _supabase
          .from('break_periods')
          .select()
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('break_start_time', ascending: false);

      debugPrint('[PULL] Found ${response.length} break periods');

      for (final breakPeriod in response) {
        final uuid = breakPeriod['id'] as String;
        final sessionUuid = breakPeriod['session_id'] as String?;

        // Find local session ID
        int? localSessionId;
        if (sessionUuid != null) {
          final sessionResult = await _db.query(
            'attendance_sessions',
            columns: ['id'],
            where: 'uuid = ?',
            whereArgs: [sessionUuid],
          );
          if (sessionResult.isNotEmpty) {
            localSessionId = sessionResult.first['id'] as int;
          }
        }

        // Skip if parent session not found
        if (localSessionId == null) {
          debugPrint(
            '[PULL] ⚠️ Skipping break $uuid - parent session not found',
          );
          continue;
        }

        // Check if break already exists locally
        final existing = await _db.query(
          'break_periods',
          where: 'uuid = ?',
          whereArgs: [uuid],
        );

        final localData = {
          'uuid': uuid,
          'session_id': localSessionId,
          'user_id': localUserId,
          'break_start_time': breakPeriod['break_start_time'],
          'break_end_time': breakPeriod['break_end_time'],
          'break_start_time_utc': breakPeriod['break_start_time_utc'],
          'break_end_time_utc': breakPeriod['break_end_time_utc'],
          'duration_seconds': breakPeriod['duration_seconds'],
          'note': breakPeriod['note'],
          'synced_at': DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await _db.insert('break_periods', localData);
          debugPrint('[PULL] ✅ Inserted break: $uuid');
        } else {
          await _db.update(
            'break_periods',
            localData,
            where: 'uuid = ?',
            whereArgs: [uuid],
          );
          debugPrint('[PULL] ✅ Updated break: $uuid');
        }
      }
    } catch (e) {
      debugPrint('[PULL] Error pulling break periods: $e');
      rethrow;
    }
  }

  Future<void> _pullAppActivities(String userId, int localUserId) async {
    try {
      debugPrint('[PULL] Fetching app activities...');

      // Only pull activities from last 7 days to avoid overwhelming local DB
      final sevenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .toUtc()
          .toIso8601String();

      final response = await _supabase
          .from('app_activities')
          .select()
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .gte('start_time_utc', sevenDaysAgo)
          .order('start_time', ascending: false)
          .limit(1000); // Limit to prevent excessive data

      debugPrint('[PULL] Found ${response.length} app activities');

      for (final activity in response) {
        final uuid = activity['id'] as String;
        final sessionUuid = activity['session_id'] as String?;

        // Find local session ID
        int? localSessionId;
        if (sessionUuid != null) {
          final sessionResult = await _db.query(
            'attendance_sessions',
            columns: ['id'],
            where: 'uuid = ?',
            whereArgs: [sessionUuid],
          );
          if (sessionResult.isNotEmpty) {
            localSessionId = sessionResult.first['id'] as int;
          }
        }

        // Check if activity already exists locally
        final existing = await _db.query(
          'app_activities',
          where: 'uuid = ?',
          whereArgs: [uuid],
        );

        final localData = {
          'uuid': uuid,
          'session_id': localSessionId,
          'user_id': localUserId,
          'app_name': activity['app_name'],
          'window_title': activity['window_title'],
          'bundle_id': activity['bundle_id'],
          'start_time': activity['start_time'],
          'end_time': activity['end_time'],
          'start_time_utc': activity['start_time_utc'],
          'end_time_utc': activity['end_time_utc'],
          'duration_seconds': activity['duration_seconds'],
          'activity_type': activity['activity_type'],
          'synced_at': DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await _db.insert('app_activities', localData);
        } else {
          await _db.update(
            'app_activities',
            localData,
            where: 'uuid = ?',
            whereArgs: [uuid],
          );
        }
      }

      debugPrint('[PULL] ✅ Pulled ${response.length} app activities');
    } catch (e) {
      debugPrint('[PULL] Error pulling app activities: $e');
      rethrow;
    }
  }

  Future<void> _pullWorkDuringSleep(String userId, int localUserId) async {
    try {
      debugPrint('[PULL] Fetching work during sleep periods...');

      final response = await _supabase
          .from('work_during_sleep_periods')
          .select()
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .order('sleep_start_time', ascending: false);

      debugPrint('[PULL] Found ${response.length} work during sleep periods');

      for (final work in response) {
        final uuid = work['id'] as String;
        final sessionUuid = work['session_id'] as String?;

        // Find local session ID
        int? localSessionId;
        if (sessionUuid != null) {
          final sessionResult = await _db.query(
            'attendance_sessions',
            columns: ['id'],
            where: 'uuid = ?',
            whereArgs: [sessionUuid],
          );
          if (sessionResult.isNotEmpty) {
            localSessionId = sessionResult.first['id'] as int;
          }
        }

        // Check if record already exists locally
        final existing = await _db.query(
          'work_during_sleep_periods',
          where: 'uuid = ?',
          whereArgs: [uuid],
        );

        final localData = {
          'uuid': uuid,
          'session_id': localSessionId,
          'user_id': localUserId,
          'sleep_start_time': work['sleep_start_time'],
          'wake_time': work['wake_time'],
          'sleep_start_time_utc': work['sleep_start_time_utc'],
          'wake_time_utc': work['wake_time_utc'],
          'duration_seconds': work['duration_seconds'],
          'note': work['note'],
          'synced_at': DateTime.now().toIso8601String(),
        };

        if (existing.isEmpty) {
          await _db.insert('work_during_sleep_periods', localData);
          debugPrint('[PULL] ✅ Inserted work during sleep: $uuid');
        } else {
          await _db.update(
            'work_during_sleep_periods',
            localData,
            where: 'uuid = ?',
            whereArgs: [uuid],
          );
          debugPrint('[PULL] ✅ Updated work during sleep: $uuid');
        }
      }
    } catch (e) {
      debugPrint('[PULL] Error pulling work during sleep: $e');
      rethrow;
    }
  }
}
