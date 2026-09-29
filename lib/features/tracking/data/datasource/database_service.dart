import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    // Web support: Prevent initialization of sqflite_common_ffi
    if (kIsWeb) {
      throw UnsupportedError(
        'Database operations are not supported on the web platform.',
      );
    }

    try {
      // Initialize FFI for desktop platforms
      debugPrint('[DB] Initializing FFI...');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      debugPrint('[DB] FFI initialized successfully');

      // Get application documents directory with fallback
      debugPrint('[DB] Getting documents directory...');
      Directory documentsDirectory;
      try {
        documentsDirectory = await getApplicationDocumentsDirectory();
        debugPrint('[DB] Using application documents directory');
      } catch (e) {
        debugPrint('[DB] Failed to get application documents directory: $e');
        debugPrint('[DB] Using support directory as fallback');
        documentsDirectory = await getApplicationSupportDirectory();
      }

      final path = join(documentsDirectory.path, 'attendance_tracker.db');
      debugPrint('[DB] Database path: $path');

      // Ensure the directory exists with proper permissions
      try {
        if (!await documentsDirectory.exists()) {
          debugPrint('[DB] Creating directory: ${documentsDirectory.path}');
          await documentsDirectory.create(recursive: true);
        }

        // Test directory permissions by trying to create a temp file
        final testFile = File(join(documentsDirectory.path, '.db_test'));
        await testFile.writeAsString('test');
        await testFile.delete();
        debugPrint('[DB] Directory permissions verified');
      } catch (e) {
        debugPrint('[DB] ❌ Directory permission error: $e');
        // Fallback to support directory if documents directory has issues
        documentsDirectory = await getApplicationSupportDirectory();

        // Ensure support directory exists
        if (!await documentsDirectory.exists()) {
          await documentsDirectory.create(recursive: true);
        }

        debugPrint(
          '[DB] Falling back to support directory: ${documentsDirectory.path}',
        );
      }

      // Check if we need to delete and recreate the database
      debugPrint('[DB] Checking if database needs recreation...');
      final needsRecreation = await _checkNeedsRecreation(path);
      if (needsRecreation) {
        debugPrint('[DB] Schema incompatible, deleting old database...');
        try {
          await databaseFactoryFfi.deleteDatabase(path);
          debugPrint('[DB] Old database deleted successfully');
          // Add a small delay to ensure file system operations complete
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('[DB] Error deleting database: $e');
        }
      }

      debugPrint('[DB] Opening database...');
      try {
        return await openDatabase(
          path,
          version: 10,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      } catch (e) {
        debugPrint(
          '[DB] ❌ Failed to open database, trying fallback location...',
        );
        // Fallback to support directory
        final supportDir = await getApplicationSupportDirectory();
        if (!await supportDir.exists()) {
          await supportDir.create(recursive: true);
        }
        final fallbackPath = join(supportDir.path, 'attendance_tracker.db');
        debugPrint('[DB] Fallback database path: $fallbackPath');
        return await openDatabase(
          fallbackPath,
          version: 10,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[DB] ❌ Error initializing database: $e');
      debugPrint('[DB] Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<bool> _checkNeedsRecreation(String path) async {
    try {
      // Try to open the database and check schema
      final db = await databaseFactoryFfi.openDatabase(path);

      try {
        // Check if users table exists
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
        );

        if (tables.isEmpty) {
          await db.close();
          debugPrint('[DB] Missing users table - recreation needed');
          return true; // Need to recreate - missing users table
        }

        // Check if app_activities table exists
        final appActivitiesTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='app_activities'",
        );

        if (appActivitiesTables.isEmpty) {
          await db.close();
          debugPrint('[DB] Missing app_activities table - recreation needed');
          return true; // Need to recreate - missing app_activities table
        }

        // Check if app_activities has required columns
        final appActivitiesInfo = await db.rawQuery(
          'PRAGMA table_info(app_activities)',
        );
        final hasUuid = appActivitiesInfo.any((col) => col['name'] == 'uuid');
        final hasStartTimeUtc = appActivitiesInfo.any(
          (col) => col['name'] == 'start_time_utc',
        );
        final hasEndTimeUtc = appActivitiesInfo.any(
          (col) => col['name'] == 'end_time_utc',
        );
        final hasUserId = appActivitiesInfo.any(
          (col) => col['name'] == 'user_id',
        );

        await db.close();

        if (!hasUuid) {
          debugPrint(
            '[DB] Missing uuid column in app_activities - recreation needed',
          );
          return true; // Need to recreate - missing uuid column
        }

        if (!hasStartTimeUtc || !hasEndTimeUtc) {
          debugPrint(
            '[DB] Missing UTC time columns in app_activities - recreation needed',
          );
          return true; // Need to recreate - missing UTC time columns
        }

        if (!hasUserId) {
          debugPrint(
            '[DB] Missing user_id column in app_activities - recreation needed',
          );
          return true; // Need to recreate - missing user_id column
        }

        debugPrint('[DB] Schema validation passed - no recreation needed');
        return false; // Schema is good
      } catch (e) {
        await db.close();
        debugPrint('[DB] Error checking schema: $e - recreation needed');
        return true; // Error checking schema, recreate to be safe
      }
    } catch (e) {
      // Database doesn't exist or can't be opened - if it can't be opened, we should recreate it
      debugPrint('[DB] Database does not exist or cannot be opened: $e');
      // Check if the file exists - if it does but can't be opened, it's likely corrupted
      final dbFile = File(path);
      if (await dbFile.exists()) {
        debugPrint(
          '[DB] Database file exists but cannot be opened - likely corrupted, marking for recreation',
        );
        return true; // File exists but can't be opened - recreate it
      }
      return false; // File doesn't exist - let onCreate handle it
    }
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // Add last_seen_time column for auto-save feature
      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN last_seen_time TEXT
      ''');
    }

    if (oldVersion < 3) {
      // Add multi-day continuation support
      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN continuation_of_session_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN continuation_reason TEXT
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN original_timezone TEXT
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN check_in_time_utc TEXT
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN check_out_time_utc TEXT
      ''');

      // Add UTC times to break_periods
      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN break_start_time_utc TEXT
      ''');

      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN break_end_time_utc TEXT
      ''');

      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN continuation_of_break_id INTEGER
      ''');

      // Create session_continuations table
      await db.execute('''
        CREATE TABLE session_continuations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          original_session_id INTEGER NOT NULL,
          new_session_id INTEGER NOT NULL,
          continuation_type TEXT NOT NULL,
          split_timestamp_utc TEXT NOT NULL,
          split_timestamp_local TEXT NOT NULL,
          metadata TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (original_session_id) REFERENCES attendance_sessions(id),
          FOREIGN KEY (new_session_id) REFERENCES attendance_sessions(id)
        )
      ''');

      // Create indexes for continuation queries
      await db.execute('''
        CREATE INDEX idx_sessions_continuation ON attendance_sessions(continuation_of_session_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_sessions_timezone ON attendance_sessions(original_timezone)
      ''');

      await db.execute('''
        CREATE INDEX idx_continuations_original ON session_continuations(original_session_id)
      ''');

      // Backfill existing data with UTC times
      final sessions = await db.query('attendance_sessions');
      for (final session in sessions) {
        final checkInLocal = DateTime.parse(session['check_in_time'] as String);
        final checkInUtc = checkInLocal.toUtc();

        final updates = <String, dynamic>{
          'check_in_time_utc': checkInUtc.toIso8601String(),
          'original_timezone': DateTime.now().timeZoneName,
        };

        if (session['check_out_time'] != null) {
          final checkOutLocal = DateTime.parse(
            session['check_out_time'] as String,
          );
          final checkOutUtc = checkOutLocal.toUtc();
          updates['check_out_time_utc'] = checkOutUtc.toIso8601String();
        }

        await db.update(
          'attendance_sessions',
          updates,
          where: 'id = ?',
          whereArgs: [session['id']],
        );
      }

      // Backfill break periods with UTC times
      final breaks = await db.query('break_periods');
      for (final breakPeriod in breaks) {
        final breakStartLocal = DateTime.parse(
          breakPeriod['break_start_time'] as String,
        );
        final breakStartUtc = breakStartLocal.toUtc();

        final updates = <String, dynamic>{
          'break_start_time_utc': breakStartUtc.toIso8601String(),
        };

        if (breakPeriod['break_end_time'] != null) {
          final breakEndLocal = DateTime.parse(
            breakPeriod['break_end_time'] as String,
          );
          final breakEndUtc = breakEndLocal.toUtc();
          updates['break_end_time_utc'] = breakEndUtc.toIso8601String();
        }

        await db.update(
          'break_periods',
          updates,
          where: 'id = ?',
          whereArgs: [breakPeriod['id']],
        );
      }
    }

    if (oldVersion < 4) {
      // Add app_activities table for tracking active applications
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_activities (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER,
          app_name TEXT NOT NULL,
          window_title TEXT,
          bundle_id TEXT,
          start_time TEXT NOT NULL,
          end_time TEXT,
          duration_seconds INTEGER,
          start_time_utc TEXT NOT NULL,
          end_time_utc TEXT,
          activity_type TEXT DEFAULT 'work',
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (session_id) REFERENCES attendance_sessions(id)
        )
      ''');

      // Create indexes for efficient queries (IF NOT EXISTS for safety)
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_activities_session ON app_activities(session_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_activities_start_time ON app_activities(start_time)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_activities_app_name ON app_activities(app_name)
      ''');
    }

    if (oldVersion < 5) {
      // Add note field to break_periods for storing work notes after sleep
      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN note TEXT
      ''');
    }

    if (oldVersion < 6) {
      // Create work_during_sleep_periods table for tracking work during system sleep
      await db.execute('''
        CREATE TABLE IF NOT EXISTS work_during_sleep_periods (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          sleep_start_time TEXT NOT NULL,
          wake_time TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          sleep_start_time_utc TEXT NOT NULL,
          wake_time_utc TEXT NOT NULL,
          note TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (session_id) REFERENCES attendance_sessions(id)
        )
      ''');

      // Create index for efficient queries
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_work_sleep_session ON work_during_sleep_periods(session_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_work_sleep_start_time ON work_during_sleep_periods(sleep_start_time)
      ''');
    }

    if (oldVersion < 7) {
      // Create users table for local user management
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          email TEXT NOT NULL UNIQUE,
          name TEXT,
          role TEXT NOT NULL DEFAULT 'member',
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          last_login_at TEXT,
          is_active INTEGER DEFAULT 1,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_users_uuid ON users(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)
      ''');

      // Add user_id, uuid, and sync fields to attendance_sessions
      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN user_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN uuid TEXT
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN synced_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE attendance_sessions ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sessions_uuid ON attendance_sessions(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON attendance_sessions(user_id)
      ''');

      // Add user_id, uuid, and sync fields to break_periods
      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN user_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN uuid TEXT
      ''');

      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN synced_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE break_periods ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_breaks_uuid ON break_periods(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_breaks_user_id ON break_periods(user_id)
      ''');

      // Add user_id, uuid, and sync fields to app_activities
      await db.execute('''
        ALTER TABLE app_activities ADD COLUMN user_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE app_activities ADD COLUMN uuid TEXT
      ''');

      await db.execute('''
        ALTER TABLE app_activities ADD COLUMN synced_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE app_activities ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_activities_uuid ON app_activities(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_activities_user_id ON app_activities(user_id)
      ''');

      // Add user_id, uuid, and sync fields to work_during_sleep_periods
      await db.execute('''
        ALTER TABLE work_during_sleep_periods ADD COLUMN user_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE work_during_sleep_periods ADD COLUMN uuid TEXT
      ''');

      await db.execute('''
        ALTER TABLE work_during_sleep_periods ADD COLUMN synced_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE work_during_sleep_periods ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_work_sleep_uuid ON work_during_sleep_periods(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_work_sleep_user_id ON work_during_sleep_periods(user_id)
      ''');

      // Add user_id, uuid, and sync fields to session_continuations
      await db.execute('''
        ALTER TABLE session_continuations ADD COLUMN user_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE session_continuations ADD COLUMN uuid TEXT
      ''');

      await db.execute('''
        ALTER TABLE session_continuations ADD COLUMN synced_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE session_continuations ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_continuations_uuid ON session_continuations(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_continuations_user_id ON session_continuations(user_id)
      ''');

      // Add user_id, uuid, and sync fields to event_log
      await db.execute('''
        ALTER TABLE event_log ADD COLUMN user_id INTEGER
      ''');

      await db.execute('''
        ALTER TABLE event_log ADD COLUMN uuid TEXT
      ''');

      await db.execute('''
        ALTER TABLE event_log ADD COLUMN synced_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE event_log ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_event_log_uuid ON event_log(uuid)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_event_log_user_id_idx ON event_log(user_id)
      ''');

      // Create sync_queue table for offline sync management
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          table_name TEXT NOT NULL,
          record_id INTEGER NOT NULL,
          record_uuid TEXT,
          operation TEXT NOT NULL,
          data TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          synced_at TEXT,
          retry_count INTEGER DEFAULT 0,
          last_error TEXT,
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_queue_user_id ON sync_queue(user_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_queue_synced_at ON sync_queue(synced_at)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_queue_table_name ON sync_queue(table_name)
      ''');
    }

    if (oldVersion < 8) {
      // Add updated_at column to all sync-enabled tables
      // Note: SQLite doesn't support DEFAULT CURRENT_TIMESTAMP in ALTER TABLE
      // So we add the column without default, then backfill
      final tables = [
        'attendance_sessions',
        'break_periods',
        'app_activities',
        'work_during_sleep_periods',
        'session_continuations',
        'event_log',
      ];

      for (final table in tables) {
        // Add updated_at column without default
        await db.execute('''
          ALTER TABLE $table ADD COLUMN updated_at TEXT
        ''');

        // Backfill existing records with current timestamp
        await db.execute('''
          UPDATE $table SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL
        ''');
      }
    }

    if (oldVersion < 9) {
      // Logic for version 9 was missing or handled previously,
      // just ensuring we don't break strict ordering
    }

    if (oldVersion < 10) {
      // Add session_backup table for crash recovery
      await db.execute('''
        CREATE TABLE IF NOT EXISTS session_backup (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT,
          access_token TEXT NOT NULL,
          refresh_token TEXT,
          expires_at INTEGER,
          token_type TEXT,
          user_json TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        email TEXT NOT NULL UNIQUE,
        name TEXT,
        role TEXT NOT NULL DEFAULT 'member',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_login_at TEXT,
        is_active INTEGER DEFAULT 1,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create session_backup table for crash recovery
    await db.execute('''
      CREATE TABLE session_backup (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        access_token TEXT NOT NULL,
        refresh_token TEXT,
        expires_at INTEGER,
        token_type TEXT,
        user_json TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create attendance_sessions table
    await db.execute('''
      CREATE TABLE attendance_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        uuid TEXT,
        check_in_time TEXT NOT NULL,
        check_out_time TEXT,
        check_in_source TEXT NOT NULL,
        check_out_source TEXT,
        total_work_seconds INTEGER,
        is_closed INTEGER DEFAULT 0,
        last_seen_time TEXT,
        continuation_of_session_id INTEGER,
        continuation_reason TEXT,
        original_timezone TEXT,
        check_in_time_utc TEXT,
        check_out_time_utc TEXT,
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create break_periods table
    await db.execute('''
      CREATE TABLE break_periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        user_id INTEGER,
        uuid TEXT,
        break_start_time TEXT NOT NULL,
        break_end_time TEXT,
        duration_seconds INTEGER,
        break_start_time_utc TEXT,
        break_end_time_utc TEXT,
        continuation_of_break_id INTEGER,
        note TEXT,
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create event_log table
    await db.execute('''
      CREATE TABLE event_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        uuid TEXT,
        event_type TEXT NOT NULL,
        event_source TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        metadata TEXT,
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create session_continuations table
    await db.execute('''
      CREATE TABLE session_continuations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        uuid TEXT,
        original_session_id INTEGER NOT NULL,
        new_session_id INTEGER NOT NULL,
        continuation_type TEXT NOT NULL,
        split_timestamp_utc TEXT NOT NULL,
        split_timestamp_local TEXT NOT NULL,
        metadata TEXT,
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (original_session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (new_session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create app_activities table
    await db.execute('''
      CREATE TABLE app_activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        user_id INTEGER,
        uuid TEXT,
        app_name TEXT NOT NULL,
        window_title TEXT,
        bundle_id TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_seconds INTEGER,
        start_time_utc TEXT NOT NULL,
        end_time_utc TEXT,
        activity_type TEXT DEFAULT 'work',
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create work_during_sleep_periods table
    await db.execute('''
      CREATE TABLE work_during_sleep_periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        user_id INTEGER,
        uuid TEXT,
        sleep_start_time TEXT NOT NULL,
        wake_time TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        sleep_start_time_utc TEXT NOT NULL,
        wake_time_utc TEXT NOT NULL,
        note TEXT NOT NULL,
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (session_id) REFERENCES attendance_sessions(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create sync_queue table
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        record_uuid TEXT,
        operation TEXT NOT NULL,
        data TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        synced_at TEXT,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create indexes
    // Users indexes
    await db.execute('''
      CREATE INDEX idx_users_uuid ON users(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_users_email ON users(email)
    ''');

    // Attendance sessions indexes
    await db.execute('''
      CREATE INDEX idx_sessions_closed ON attendance_sessions(is_closed)
    ''');

    await db.execute('''
      CREATE INDEX idx_sessions_check_in ON attendance_sessions(check_in_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_sessions_continuation ON attendance_sessions(continuation_of_session_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_sessions_timezone ON attendance_sessions(original_timezone)
    ''');

    await db.execute('''
      CREATE INDEX idx_sessions_uuid ON attendance_sessions(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_sessions_user_id ON attendance_sessions(user_id)
    ''');

    // Break periods indexes
    await db.execute('''
      CREATE INDEX idx_breaks_uuid ON break_periods(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_breaks_user_id ON break_periods(user_id)
    ''');

    // Session continuations indexes
    await db.execute('''
      CREATE INDEX idx_continuations_original ON session_continuations(original_session_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_continuations_uuid ON session_continuations(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_continuations_user_id ON session_continuations(user_id)
    ''');

    // App activities indexes
    await db.execute('''
      CREATE INDEX idx_activities_session ON app_activities(session_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_activities_start_time ON app_activities(start_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_activities_app_name ON app_activities(app_name)
    ''');

    await db.execute('''
      CREATE INDEX idx_activities_uuid ON app_activities(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_activities_user_id ON app_activities(user_id)
    ''');

    // Work during sleep indexes
    await db.execute('''
      CREATE INDEX idx_work_sleep_session ON work_during_sleep_periods(session_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_work_sleep_start_time ON work_during_sleep_periods(sleep_start_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_work_sleep_uuid ON work_during_sleep_periods(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_work_sleep_user_id ON work_during_sleep_periods(user_id)
    ''');

    // Event log indexes
    await db.execute('''
      CREATE INDEX idx_event_log_uuid ON event_log(uuid)
    ''');

    await db.execute('''
      CREATE INDEX idx_event_log_user_id_idx ON event_log(user_id)
    ''');

    // Sync queue indexes
    await db.execute('''
      CREATE INDEX idx_sync_queue_user_id ON sync_queue(user_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_sync_queue_synced_at ON sync_queue(synced_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_sync_queue_table_name ON sync_queue(table_name)
    ''');
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
  }

  /// Reset the database instance (useful for cleanup or testing)
  static Future<void> resetDatabase() async {
    if (_database != null) {
      try {
        await _database!.close();
        debugPrint('[DB] Database closed');
      } catch (e) {
        debugPrint('[DB] Error closing database: $e');
      }
      _database = null;
      debugPrint('[DB] Database instance reset');
    }
  }

  /// Get the database file path
  static Future<String> getDatabasePath() async {
    Directory appDocDir;
    try {
      appDocDir = await getApplicationDocumentsDirectory();
    } catch (e) {
      appDocDir = Directory.current;
    }
    return join(appDocDir.path, 'attendance_tracker.db');
  }

  /// Delete the database file completely
  static Future<void> deleteDatabase() async {
    try {
      // Close the database first
      await resetDatabase();

      // Get the database path
      final dbPath = await getDatabasePath();
      final dbFile = File(dbPath);

      // Delete main database file
      if (await dbFile.exists()) {
        await dbFile.delete();
        debugPrint('[DB] ✓ Deleted database file: $dbPath');
      }

      // Delete WAL file
      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) {
        await walFile.delete();
        debugPrint('[DB] ✓ Deleted WAL file');
      }

      // Delete SHM file
      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) {
        await shmFile.delete();
        debugPrint('[DB] ✓ Deleted SHM file');
      }

      debugPrint('[DB] Database deleted successfully');
    } catch (e) {
      debugPrint('[DB] ❌ Error deleting database: $e');
      rethrow;
    }
  }
}
