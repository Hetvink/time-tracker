import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

/// Service to persist Supabase sessions to SQLite for crash recovery
///
/// This service provides a backup mechanism for session storage.
/// Standard SharedPreferences storage is not crash-safe (data may not be flushed to disk).
/// SQLite with synchronous=FULL ensures data is written to disk immediately.
class SessionPersistenceService {
  static const String tableName = 'session_backup';

  /// Save session to SQLite backup
  Future<void> saveSession(Session session) async {
    try {
      if (kIsWeb) return; // Not needed/supported on web

      final db = await DatabaseService.database;

      // Ensure immediate disk write
      await db.rawQuery('PRAGMA synchronous = FULL');

      final sessionData = {
        'user_id': session.user.id,
        'access_token': session.accessToken,
        'refresh_token': session.refreshToken,
        'expires_at': session.expiresAt,
        'token_type': session.tokenType,
        'user_json': jsonEncode(session.user.toJson()),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Use transaction to ensure atomicity
      await db.transaction((txn) async {
        // Clear existing sessions for this user (or all sessions if single user app)
        // For simple desktop app, we usually have one active user
        await txn.delete(tableName);

        // Insert new session
        await txn.insert(
          tableName,
          sessionData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      debugPrint('[SessionPersistence] ✅ Session backed up to SQLite');
    } catch (e) {
      debugPrint('[SessionPersistence] ❌ Failed to backup session: $e');
    }
  }

  /// Restore session from SQLite backup
  ///
  /// Returns the stored session or null if not found/expired
  Future<Session?> restoreSession() async {
    try {
      if (kIsWeb) return null;

      final db = await DatabaseService.database;
      final results = await db.query(
        tableName,
        orderBy: 'created_at DESC',
        limit: 1,
      );

      if (results.isEmpty) {
        debugPrint('[SessionPersistence] No backup session found');
        return null;
      }

      final data = results.first;
      final expiresAt = data['expires_at'] as int?;

      // CRITICAL CHANGE: We do NOT check for access token expiration here anymore.
      // Even if the access token is expired, the refresh token might still be valid.
      // We return the session so AuthService can attempt to use the refresh token.

      /* 
      // Old logic that caused auto-logouts after 1 hour:
      if (expiresAt != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
        if (DateTime.now().isAfter(expiry)) {
          debugPrint('[SessionPersistence] Backup session expired');
          await clearSession();
          return null;
        }
      }
      */

      // Reconstruct user object
      final userJsonStr = data['user_json'] as String;
      final userJson = jsonDecode(userJsonStr) as Map<String, dynamic>;
      final user = User.fromJson(userJson)!;

      // Reconstruct session
      final session = Session(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String?,
        expiresIn: expiresAt != null
            ? expiresAt - (DateTime.now().millisecondsSinceEpoch ~/ 1000)
            : null,
        tokenType: data['token_type'] as String,
        user: user,
      );

      debugPrint('[SessionPersistence] ✅ Session restored from SQLite backup');
      return session;
    } catch (e) {
      debugPrint('[SessionPersistence] ❌ Failed to restore session: $e');
      return null;
    }
  }

  /// Clear session backup
  Future<void> clearSession() async {
    try {
      if (kIsWeb) return;

      final db = await DatabaseService.database;
      await db.delete(tableName);
      debugPrint('[SessionPersistence] ✅ Session backup cleared');
    } catch (e) {
      debugPrint('[SessionPersistence] ❌ Failed to clear session backup: $e');
    }
  }

  /// Check if a valid backup exists
  Future<bool> hasValidBackup() async {
    final session = await restoreSession();
    return session != null;
  }
}
