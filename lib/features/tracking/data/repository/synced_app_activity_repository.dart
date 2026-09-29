import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'app_activity_repository.dart';
import '../../../../core/network/supabase_sync_service.dart';
import '../../../auth/data/repository/user_repository.dart';
import '../datasource/database_service.dart';
import '../models/app_activity.dart';
import '../../../../core/constants/supabase_config.dart';

/// Wrapper around AppActivityRepository that adds sync functionality
class SyncedAppActivityRepository extends AppActivityRepository {
  final SupabaseSyncService _syncService;
  final UserRepository _userRepository;
  final Uuid _uuidGenerator = const Uuid();

  SyncedAppActivityRepository({
    required SupabaseSyncService syncService,
    required UserRepository userRepository,
  }) : _syncService = syncService,
       _userRepository = userRepository;

  // Get current local user ID from Supabase auth
  Future<int?> _getCurrentUserId() async {
    final supabaseUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (supabaseUserId == null) return null;

    final user = await _userRepository.getUserByUuid(supabaseUserId);
    return user?['id'] as int?;
  }

  /// Insert activity with user_id and UUID, then sync
  @override
  Future<int> insertActivity(AppActivity activity) async {
    final userId = await _getCurrentUserId();
    final uuid = _uuidGenerator.v4();
    final db = await DatabaseService.database;

    // Insert with user_id and uuid
    final activityId = await db.insert('app_activities', {
      ...activity.toMap(),
      'user_id': userId,
      'uuid': uuid,
    });

    // Trigger sync asynchronously
    _syncService
        .syncAppActivity(localId: activityId, operation: 'insert')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync activity $activityId: $e');
          return null;
        });

    return activityId;
  }

  /// Update activity and sync
  @override
  Future<void> updateActivity(AppActivity activity) async {
    await super.updateActivity(activity);

    if (activity.id != null) {
      _syncService
          .syncAppActivity(localId: activity.id!, operation: 'update')
          .catchError((e) {
            debugPrint('[SYNC] Failed to sync activity ${activity.id}: $e');
            return null;
          });
    }
  }

  /// Soft delete an activity and sync deletion to Supabase
  @override
  Future<void> softDeleteActivity(int activityId) async {
    await super.softDeleteActivity(activityId);

    _syncService
        .syncAppActivity(localId: activityId, operation: 'delete')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync deleted activity $activityId: $e');
          return null;
        });
  }

  /// End activity and sync
  @override
  Future<void> endActivity(int activityId, DateTime endTime) async {
    await super.endActivity(activityId, endTime);

    _syncService
        .syncAppActivity(localId: activityId, operation: 'update')
        .catchError((e) {
          debugPrint('[SYNC] Failed to sync activity $activityId: $e');
          return null;
        });
  }
}
