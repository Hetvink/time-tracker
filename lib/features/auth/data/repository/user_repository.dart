import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class UserRepository {
  final Database _db;

  UserRepository(this._db);

  // Create or update user in local database
  Future<int> upsertUser({
    required String uuid,
    required String email,
    String? name,
    String? role,
  }) async {
    // Check if user exists
    final existingUser = await _db.query(
      'users',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );

    if (existingUser.isNotEmpty) {
      // Update existing user
      await _db.update(
        'users',
        {
          'email': email,
          'name': ?name,
          'role': ?role,
          'last_login_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      return existingUser.first['id'] as int;
    } else {
      // Check if user exists by email (to avoid unique constraint errors)
      final existingByEmail = await _db.query(
        'users',
        where: 'email = ?',
        whereArgs: [email],
      );

      if (existingByEmail.isNotEmpty) {
        // User exists with same email but different UUID
        // Update the UUID to match the new one (and other fields)
        await _db.update(
          'users',
          {
            'uuid': uuid,
            'name': ?name,
            'role': ?role,
            'last_login_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'email = ?',
          whereArgs: [email],
        );
        return existingByEmail.first['id'] as int;
      }

      // Insert new user
      return await _db.insert('users', {
        'uuid': uuid,
        'email': email,
        'name': name,
        'role': role ?? 'member',
        'created_at': DateTime.now().toIso8601String(),
        'last_login_at': DateTime.now().toIso8601String(),
        'is_active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  // Get user by UUID
  Future<Map<String, dynamic>?> getUserByUuid(String uuid) async {
    final results = await _db.query(
      'users',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );

    return results.isNotEmpty ? results.first : null;
  }

  // Get user by email
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final results = await _db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    return results.isNotEmpty ? results.first : null;
  }

  // Get user by local ID
  Future<Map<String, dynamic>?> getUserById(int id) async {
    final results = await _db.query('users', where: 'id = ?', whereArgs: [id]);

    return results.isNotEmpty ? results.first : null;
  }

  // Get current user (assumes single user for now, or most recently logged in)
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final results = await _db.query(
      'users',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'last_login_at DESC',
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  // Update last login time
  Future<void> updateLastLogin(String uuid) async {
    await _db.update(
      'users',
      {
        'last_login_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // Deactivate user
  Future<void> deactivateUser(String uuid) async {
    await _db.update(
      'users',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // Activate user
  Future<void> activateUser(String uuid) async {
    await _db.update(
      'users',
      {'is_active': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  // Get all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    return await _db.query('users', orderBy: 'last_login_at DESC');
  }

  // Delete user (hard delete - use with caution)
  Future<void> deleteUser(String uuid) async {
    await _db.delete('users', where: 'uuid = ?', whereArgs: [uuid]);
  }

  /// Deactivate all users except the specified one
  /// This is used when switching between different user accounts
  Future<void> deactivateAllExcept(String uuid) async {
    await _db.update(
      'users',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'uuid != ?',
      whereArgs: [uuid],
    );
  }

  /// Clear local cache for a specific user
  /// WARNING: This will delete all local data for the user
  /// The data should already be synced to Supabase before calling this
  Future<void> clearUserLocalData(String uuid) async {
    // Get user's local ID first
    final user = await getUserByUuid(uuid);
    if (user == null) return;

    final userId = user['id'] as int;

    // Delete all user-related data
    // Order matters due to foreign key constraints
    await _db.delete('sync_queue', where: 'user_id = ?', whereArgs: [userId]);
    await _db.delete(
      'app_activities',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    await _db.delete(
      'work_during_sleep_periods',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    await _db.delete(
      'break_periods',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    await _db.delete(
      'session_continuations',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    await _db.delete('event_log', where: 'user_id = ?', whereArgs: [userId]);
    await _db.delete(
      'attendance_sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Clear ALL local data (for logout/switch user scenarios)
  /// This removes all cached data but keeps user records
  Future<void> clearAllLocalData() async {
    // Clear all data tables but keep users table
    await _db.delete('sync_queue');
    await _db.delete('app_activities');
    await _db.delete('work_during_sleep_periods');
    await _db.delete('break_periods');
    await _db.delete('session_continuations');
    await _db.delete('event_log');
    await _db.delete('attendance_sessions');
  }
}
