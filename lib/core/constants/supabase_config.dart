import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/tracking/data/datasource/session_persistence_service.dart';
import 'app_env.dart';

class SupabaseConfig {
  static SupabaseClient? _client;
  static String? _supabaseUrl;

  static Future<void> initialize() async {
    await AppEnv.load();
    final supabaseUrl = AppEnv.supabaseUrl;
    final supabaseKey = AppEnv.supabaseKey;

    // Store the URL for later use
    _supabaseUrl = supabaseUrl;

    // Initialize Supabase with persistent storage for desktop
    debugPrint(
      '[Supabase] Initializing with ${kIsWeb ? "default web storage" : "SharedPreferences storage"}',
    );

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
      ),
    );

    _client = Supabase.instance.client;
    debugPrint('[Supabase] ✅ Initialized successfully with persistent storage');

    // Setup session backup mechanism (for desktop crash recovery)
    if (!kIsWeb) {
      await _setupSessionPersistence();
    }
  }

  static Future<void> _setupSessionPersistence() async {
    try {
      debugPrint(
        '[Supabase] 🛡️ Setting up crash-resistant session persistence...',
      );
      final persistenceService = SessionPersistenceService();

      // Listen for auth changes to backup session
      _client?.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final session = data.session;

        if (session != null) {
          if (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.userUpdated) {
            debugPrint(
              '[Supabase] 💾 Auth event: $event - Backing up session...',
            );
            persistenceService.saveSession(session);
          }
        } else if (event == AuthChangeEvent.signedOut) {
          debugPrint('[Supabase] 🗑️ User signed out - Clearing backup...');
          persistenceService.clearSession();
        }
      });
    } catch (e) {
      debugPrint('[Supabase] ❌ Error setting up session persistence: $e');
    }
  }

  static SupabaseClient get client {
    if (_client == null) {
      throw Exception(
        'Supabase client not initialized. Call SupabaseConfig.initialize() first.',
      );
    }
    return _client!;
  }

  static String get supabaseUrl {
    if (_supabaseUrl == null) {
      throw Exception(
        'Supabase not initialized. Call SupabaseConfig.initialize() first.',
      );
    }
    return _supabaseUrl!;
  }

  static bool get isInitialized => _client != null;
}
