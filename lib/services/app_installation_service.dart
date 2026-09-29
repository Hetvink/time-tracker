import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../features/tracking/data/datasource/database_service.dart';

/// Service to detect fresh installations and clean up persisted data
class AppInstallationService {
  static const String _firstRunKey = 'app_has_run_before';
  static const String _installationIdKey = 'installation_id';
  static const String _appVersionKey = 'last_app_version';

  /// Check if this is the first run after a fresh installation
  static Future<bool> isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final hasRunBefore = prefs.getBool(_firstRunKey) ?? false;
    return !hasRunBefore;
  }

  /// Mark that the app has run, storing installation info
  static Future<void> markAsRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstRunKey, true);

    // Store a unique installation ID if not present
    if (!prefs.containsKey(_installationIdKey)) {
      final installationId = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString(_installationIdKey, installationId);
    }

    // Store app version for future migration tracking
    // You can replace '1.0.0' with actual version from package_info
    await prefs.setString(_appVersionKey, '1.0.0');
  }

  /// Clean all persisted data - use with caution!
  static Future<void> cleanAllPersistedData() async {
    debugPrint('🧹 Starting complete data cleanup...');

    try {
      // 1. Clear all SharedPreferences except the first-run flag
      final prefs = await SharedPreferences.getInstance();
      final keysToPreserve = {_firstRunKey, _installationIdKey};
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (!keysToPreserve.contains(key)) {
          await prefs.remove(key);
          debugPrint('  ✓ Removed SharedPreferences key: $key');
        }
      }

      // 2. Delete the SQLite database
      await _deleteDatabaseFile();

      // 3. Clear database service instance
      await DatabaseService.resetDatabase();

      debugPrint('✅ Data cleanup completed successfully');
    } catch (e) {
      debugPrint('❌ Error during data cleanup: $e');
      rethrow;
    }
  }

  /// Delete the SQLite database file
  static Future<void> _deleteDatabaseFile() async {
    try {
      // Try to get the application documents directory
      Directory? appDocDir;
      try {
        appDocDir = await getApplicationDocumentsDirectory();
      } catch (e) {
        debugPrint('⚠️  Could not get documents directory: $e');
        // Fallback to current directory
        appDocDir = Directory.current;
      }

      final dbPath = path.join(appDocDir.path, 'attendance_tracker.db');
      final dbFile = File(dbPath);

      if (await dbFile.exists()) {
        await dbFile.delete();
        debugPrint('  ✓ Deleted database file: $dbPath');

        // Also delete WAL and SHM files if they exist
        final walFile = File('$dbPath-wal');
        final shmFile = File('$dbPath-shm');

        if (await walFile.exists()) {
          await walFile.delete();
          debugPrint('  ✓ Deleted WAL file: $dbPath-wal');
        }

        if (await shmFile.exists()) {
          await shmFile.delete();
          debugPrint('  ✓ Deleted SHM file: $dbPath-shm');
        }
      } else {
        debugPrint('  ℹ️  Database file not found: $dbPath');
      }
    } catch (e) {
      debugPrint('❌ Error deleting database: $e');
      // Don't rethrow - we want to continue cleanup even if DB delete fails
    }
  }

  /// Perform cleanup for fresh installation
  static Future<void> handleFirstRun() async {
    final isFirst = await isFirstRun();

    if (isFirst) {
      debugPrint('🆕 First run detected - performing cleanup...');
      await cleanAllPersistedData();
      await markAsRun();
      debugPrint('✅ First run setup completed');
    } else {
      debugPrint('📱 Existing installation detected');
    }
  }

  /// Force cleanup (for testing or troubleshooting)
  /// This will reset everything including the first-run flag
  static Future<void> forceCompleteReset() async {
    debugPrint(
      '⚠️  FORCE RESET: Cleaning ALL data including first-run markers...',
    );

    try {
      // Clear absolutely everything
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('  ✓ Cleared all SharedPreferences');

      // Delete database
      await _deleteDatabaseFile();

      // Reset database service
      await DatabaseService.resetDatabase();

      debugPrint('✅ Force reset completed - app will behave as fresh install');
    } catch (e) {
      debugPrint('❌ Error during force reset: $e');
      rethrow;
    }
  }

  /// Get installation information for debugging
  static Future<Map<String, dynamic>> getInstallationInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final hasRunBefore = prefs.getBool(_firstRunKey) ?? false;
    final installationId = prefs.getString(_installationIdKey);
    final lastVersion = prefs.getString(_appVersionKey);

    Directory? appDocDir;
    try {
      appDocDir = await getApplicationDocumentsDirectory();
    } catch (e) {
      appDocDir = Directory.current;
    }

    final dbPath = path.join(appDocDir.path, 'attendance_tracker.db');
    final dbExists = await File(dbPath).exists();

    return {
      'hasRunBefore': hasRunBefore,
      'installationId': installationId,
      'lastVersion': lastVersion,
      'databasePath': dbPath,
      'databaseExists': dbExists,
      'isFirstRun': !hasRunBefore,
    };
  }
}
