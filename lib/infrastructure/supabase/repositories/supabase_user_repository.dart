import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/user_model.dart';
import '../../../core/repositories/user_repository_interface.dart';
import '../../../features/auth/data/models/user_role.dart';

/// Supabase implementation of UserRepository
/// Used by both desktop and web platforms
class SupabaseUserRepository implements UserRepositoryInterface {
  final SupabaseClient _supabase;

  SupabaseUserRepository(this._supabase);

  String? get currentUserId => _supabase.auth.currentUser?.id;

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final userId = currentUserId;
      if (userId == null) return null;

      return getUserById(userId);
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching current user: $e');
      rethrow;
    }
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;

      return UserModel.fromJson(response);
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching user by ID: $e');
      rethrow;
    }
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (response == null) return null;

      return UserModel.fromJson(response);
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching user by email: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateUser(UserModel user) async {
    try {
      await _supabase.from('users').update(user.toJson()).eq('id', user.id);

      debugPrint('[SUPABASE] User updated successfully: ${user.id}');
    } catch (e) {
      debugPrint('[SUPABASE] Error updating user: $e');
      rethrow;
    }
  }

  @override
  Future<List<UserModel>> getAllUsers() async {
    try {
      // Check if current user is admin
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('Only admins can fetch all users');
      }

      final response = await _supabase
          .from('users')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => UserModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('[SUPABASE] Error fetching all users: $e');
      rethrow;
    }
  }

  @override
  Future<bool> isCurrentUserAdmin() async {
    try {
      final user = await getCurrentUser();
      return user?.role == UserRole.admin;
    } catch (e) {
      debugPrint('[SUPABASE] Error checking admin status: $e');
      return false;
    }
  }

  /// Upsert user (create or update)
  /// Role and company are managed by the database, never sent from here.
  Future<UserModel> upsertUser({
    required String id,
    required String email,
    String? name,
  }) async {
    try {
      final userData = {
        'id': id,
        'email': email,
        'name': ?name,
        'last_login_at': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await _supabase
          .from('users')
          .upsert(userData)
          .select()
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      debugPrint('[SUPABASE] Error upserting user: $e');
      rethrow;
    }
  }

  /// Update last login timestamp
  Future<void> updateLastLogin(String userId) async {
    try {
      await _supabase
          .from('users')
          .update({'last_login_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (e) {
      debugPrint('[SUPABASE] Error updating last login: $e');
      // Don't rethrow - this is not critical
    }
  }

  /// Deactivate user (soft delete)
  Future<void> deactivateUser(String userId) async {
    try {
      // Check if current user is admin
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('Only admins can deactivate users');
      }

      await _supabase.rpc(
        'set_member_active',
        params: {'p_user_id': userId, 'p_active': false},
      );

      debugPrint('[SUPABASE] User deactivated: $userId');
    } catch (e) {
      debugPrint('[SUPABASE] Error deactivating user: $e');
      rethrow;
    }
  }

  /// Reactivate user
  Future<void> reactivateUser(String userId) async {
    try {
      // Check if current user is admin
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('Only admins can reactivate users');
      }

      await _supabase.rpc(
        'set_member_active',
        params: {'p_user_id': userId, 'p_active': true},
      );

      debugPrint('[SUPABASE] User reactivated: $userId');
    } catch (e) {
      debugPrint('[SUPABASE] Error reactivating user: $e');
      rethrow;
    }
  }

  /// Change user role (admin only)
  Future<void> changeUserRole(String userId, UserRole newRole) async {
    try {
      // Check if current user is admin
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('Only admins can change user roles');
      }

      await _supabase.rpc(
        'update_member_role',
        params: {'p_user_id': userId, 'p_role': newRole.value},
      );

      debugPrint('[SUPABASE] User role changed: $userId -> ${newRole.value}');
    } catch (e) {
      debugPrint('[SUPABASE] Error changing user role: $e');
      rethrow;
    }
  }

  /// Get user statistics (admin only)
  Future<Map<String, dynamic>> getUserStatistics(String userId) async {
    try {
      // Check if current user is admin or viewing own stats
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        throw Exception('Not authenticated');
      }

      if (currentUser.id != userId && !currentUser.isAdmin) {
        throw Exception('Unauthorized to view user statistics');
      }

      // Get session count
      final sessionCountResponse = await _supabase
          .from('attendance_sessions')
          .select('id')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .count();
      final sessionCount = sessionCountResponse.count;

      // Get activity count
      final activityCountResponse = await _supabase
          .from('app_activities')
          .select('id')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .count();
      final activityCount = activityCountResponse.count;

      // Get total work time
      final sessions = await _supabase
          .from('attendance_sessions')
          .select('total_work_seconds')
          .eq('user_id', userId)
          .eq('is_closed', true)
          .eq('is_deleted', false);

      int totalWorkSeconds = 0;
      for (final session in sessions as List) {
        totalWorkSeconds += (session['total_work_seconds'] as int?) ?? 0;
      }

      return {
        'session_count': sessionCount,
        'activity_count': activityCount,
        'total_work_seconds': totalWorkSeconds,
        'total_work_duration': Duration(seconds: totalWorkSeconds),
      };
    } catch (e) {
      debugPrint('[SUPABASE] Error getting user statistics: $e');
      rethrow;
    }
  }
}
