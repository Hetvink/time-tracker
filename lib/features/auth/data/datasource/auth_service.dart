import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_env.dart';
import '../../../../core/constants/platform_config.dart';
import '../../../../core/constants/supabase_config.dart';
import 'package:time_trak/core/utils/web_oauth_popup.dart'
    if (dart.library.io) 'package:time_trak/core/utils/web_oauth_popup_stub.dart';
import '../../../tracking/data/datasource/session_persistence_service.dart';

class AuthService {
  /// OAuth redirect for the mobile apps (registered in AndroidManifest.xml /
  /// Info.plist and in Supabase → Auth → Redirect URLs).
  static const mobileRedirectUrl = 'timetrak://login-callback';

  final SupabaseClient _supabase = SupabaseConfig.client;

  /// Initialize the service
  ///
  /// Sets up listeners for auth state changes to persist session
  void initialize() {
    _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (session != null &&
          (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.userUpdated)) {
        _log('Auth state change: $event - persisting session...');
        if (!kIsWeb) {
          SessionPersistenceService().saveSession(session);
        }
      }
    });

    _log('AuthService initialized with persistence listener');
  }

  /// Extract user name from User metadata with fallbacks
  static String extractUserName(User user) {
    debugPrint('[AuthService] Extracting name for user: ${user.id}');
    debugPrint('[AuthService] User Metadata: ${user.userMetadata}');

    final metadata = user.userMetadata ?? {};
    final fullName = metadata['full_name'] as String?;
    final name = metadata['name'] as String?;
    final givenName = metadata['given_name'] as String?;
    final familyName = metadata['family_name'] as String?;
    final preferredUsername = metadata['preferred_username'] as String?;

    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (name != null && name.isNotEmpty) return name;
    if (givenName != null || familyName != null) {
      return '${givenName ?? ""} ${familyName ?? ""}'.trim();
    }
    if (preferredUsername != null && preferredUsername.isNotEmpty) {
      return preferredUsername;
    }

    return user.email?.split('@')[0] ?? 'User';
  }

  // Stream for auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Current user
  User? get currentUser => _supabase.auth.currentUser;

  // Current session
  Session? get currentSession => _supabase.auth.currentSession;

  // Check if user is authenticated
  bool get isLoggedIn => currentUser != null;

  // Get current user ID
  String? get currentUserId => currentUser?.id;

  /// Sign in with Google using browser-based OAuth flow
  ///
  /// This method works across all platforms:
  /// - Desktop (macOS/Windows/Linux): Opens system browser, redirects to localhost (OAUTH_CALLBACK_PORT)
  /// - Web: Opens OAuth in a popup window, waits for callback
  Future<bool> signInWithGoogle() async {
    try {
      // Platform-specific redirect URL
      final redirectTo = _getRedirectUrl();
      _log('🔐 Starting Google sign-in with redirect URL: $redirectTo');

      if (kIsWeb) {
        // Web: Use tab-based OAuth flow (better UX than popups)
        _log('Platform: WEB - Opening OAuth in new tab');

        // Get the OAuth URL for the tab
        final oauthUrl = _getSupabaseOAuthUrl(redirectTo);

        _log('Opening new tab with OAuth URL: $oauthUrl');

        // Open the OAuth flow in a new tab and wait for callback
        final callbackUri = await WebOAuthPopup.openTabAndWaitForCallback(
          authUrl: oauthUrl,
        );

        if (callbackUri == null) {
          _log('User closed the tab or cancelled authentication');
          return false;
        }

        // Check for OAuth errors in the callback URL
        if (WebOAuthPopup.hasOAuthError(callbackUri)) {
          final errors = WebOAuthPopup.extractErrorFromUrl(callbackUri);
          final errorCode = errors['error'] ?? 'unknown_error';
          final errorDesc =
              errors['error_description'] ?? 'Unknown error occurred';
          _log('❌ OAuth error: $errorCode - $errorDesc');
          throw AuthException(errorDesc);
        }

        // Process the OAuth callback to establish the session
        _log('Processing OAuth callback...');
        final response = await _supabase.auth.getSessionFromUrl(callbackUri);
        await _updateUserProfile(response.session.user);

        _log('✅ Web OAuth completed successfully via new tab');
        return true;
      } else {
        // Desktop (macOS/Windows): Manual browser flow
        _log('Platform: DESKTOP - Opening browser for OAuth...');
        final result = await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectTo,
          authScreenLaunchMode: LaunchMode.externalApplication,
        );

        // The browser will open, user completes OAuth
        // Deep link/localhost will handle the callback
        _log('OAuth browser opened. Waiting for callback at: $redirectTo');
        return result;
      }
    } on AuthException catch (e) {
      _logError('Google sign-in failed', e);
      rethrow;
    } catch (e) {
      _logError('Unexpected error during Google sign-in', e);
      rethrow;
    }
  }

  /// Sign in with Email and Password
  Future<bool> signInWithEmailPassword(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session != null) {
        await _updateUserProfile(response.session!.user);
        return true;
      }
      return false;
    } on AuthException catch (e) {
      _logError('Email sign-in failed', e);
      rethrow;
    } catch (e) {
      _logError('Unexpected error during email sign-in', e);
      rethrow;
    }
  }

  /// Sign up with Email and Password
  Future<bool> signUpWithEmailPassword(
    String email,
    String password, {
    String? name,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: name != null ? {'full_name': name} : null,
      );
      if (response.user != null) {
        await _updateUserProfile(response.user!);
        return true;
      }
      return false;
    } on AuthException catch (e) {
      _logError('Email sign-up failed', e);
      rethrow;
    } catch (e) {
      _logError('Unexpected error during email sign-up', e);
      rethrow;
    }
  }

  /// Get the Supabase OAuth URL for web popup flow
  String _getSupabaseOAuthUrl(String redirectTo) {
    // Get the Supabase base URL
    final baseUrl = SupabaseConfig.supabaseUrl;

    // Construct the OAuth URL manually
    // Format: https://[project-ref].supabase.co/auth/v1/authorize?provider=google&redirect_to=[redirect_url]
    final uri = Uri.parse('$baseUrl/auth/v1/authorize');
    final oauthUrl = uri
        .replace(
          queryParameters: {'provider': 'google', 'redirect_to': redirectTo},
        )
        .toString();

    return oauthUrl;
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } on AuthException catch (e) {
      _logError('Sign out failed', e);
      rethrow;
    } catch (e) {
      _logError('Unexpected error during sign out', e);
      rethrow;
    }
  }

  /// Validate if the current session is still valid (user exists)
  Future<bool> isSessionValid() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) return false;

      // Try to get user profile to verify user still exists
      final userProfile = await getUserProfile();
      return userProfile != null;
    } catch (e) {
      _logError('Session validation failed', e);
      return false;
    }
  }

  /// Restore session on app start
  ///
  /// Supabase automatically restores the session from secure storage.
  /// This method explicitly checks and returns the current session.
  Future<Session?> restoreSession() async {
    try {
      _log('Attempting to restore session...');

      // On web, check if URL contains OAuth callback parameters
      if (kIsWeb) {
        final uri = Uri.base;
        if (uri.fragment.contains('access_token')) {
          _log('⚡ Detected OAuth callback with access_token in URL fragment');
          _log('Fragment: ${uri.fragment}');

          // The Supabase client should automatically process this
          // Wait a bit for the client to process
          await Future.delayed(const Duration(milliseconds: 500));
        } else if (uri.fragment.contains('error')) {
          _log('❌ Detected OAuth error in URL fragment');
          _log('Fragment: ${uri.fragment}');
        }
      }

      // 1. Try standard Supabase restoration (SharedPreferences)
      final session = _supabase.auth.currentSession;

      if (session != null) {
        _log(
          '✅ Session restored from SharedPreferences for user: ${session.user.email}',
        );

        // Backup to SQLite immediately to ensure we have a crash-safe copy
        if (!kIsWeb) {
          try {
            final persistenceService = SessionPersistenceService();
            await persistenceService.saveSession(session);
          } catch (e) {
            _logError('Failed to backup restored session', e);
          }
        }

        await _updateUserProfile(session.user);
        return session;
      }

      // 2. If SharedPreferences failed, try SQLite backup (Desktop only)
      if (!kIsWeb) {
        _log('⚠️ SharedPreferences session missing, checking SQLite backup...');
        try {
          final persistenceService = SessionPersistenceService();
          final backupSession = await persistenceService.restoreSession();

          if (backupSession != null) {
            _log('✅ Found valid backup session in SQLite');

            // Restore the session to Supabase client
            if (backupSession.refreshToken != null) {
              _log('🔄 Recovering session via refresh token...');
              final response = await _supabase.auth.setSession(
                backupSession.refreshToken!,
              );

              if (response.session != null) {
                _log('✅ Session successfully recovered from backup!');
                await _updateUserProfile(response.session!.user);
                return response.session;
              } else {
                _log(
                  '❌ Failed to recover session from backup (invalid refresh token)',
                );
                await persistenceService.clearSession();
              }
            } else {
              _log('❌ Backup session missing refresh token');
            }
          } else {
            _log('ℹ️ No backup session found');
          }
        } catch (e) {
          _logError('Error checking backup session', e);
        }
      }

      _log('ℹ️ No accessible session found');
      return null;
    } on AuthException catch (e) {
      _logError('Auth exception during session restore', e);

      // CRITICAL CHANGE: Do NOT auto-logout immediately on error.
      // The backup might still be valid even if the initial check fails.
      // Only sign out if we receive a definitive "invalid refresh token" error
      // from the server AND we have no other fallback.

      if (e.message.contains('Invalid Refresh Token') ||
          e.message.contains('refresh_token_not_found')) {
        _log('Refresh token invalid, clearing local session...');
        // We only clear local state, but don't force a full sign out api call
        // if it might throw another error.
        await _supabase.auth.signOut();

        if (!kIsWeb) {
          await SessionPersistenceService().clearSession();
        }
      }

      return null;
    } catch (e) {
      _logError('Failed to restore session - unexpected error', e);
      // Do not sign out on unexpected errors (network, etc)
      return null;
    }
  }

  /// Handle OAuth callback with code
  ///
  /// Called when the app receives a deep link or localhost redirect
  /// with the OAuth code from Google/Supabase
  Future<AuthSessionUrlResponse> handleOAuthCallback(Uri uri) async {
    try {
      // Extract the code from the callback URL
      // Supabase will exchange it for a session
      final response = await _supabase.auth.getSessionFromUrl(uri);

      _log(
        'OAuth callback successful for user: ${response.session.user.email}',
      );

      // Update user profile in database
      await _updateUserProfile(response.session.user);

      return response;
    } on AuthException catch (e) {
      _logError('OAuth callback failed', e);
      rethrow;
    } catch (e) {
      _logError('Unexpected error handling OAuth callback', e);
      rethrow;
    }
  }

  /// Get platform-specific redirect URL
  String _getRedirectUrl() {
    if (kIsWeb) {
      // Web: Use current origin
      return Uri.base.origin;
    } else if (PlatformConfig.isMobile) {
      // Android / iOS: deep link handled by DeepLinkService
      return mobileRedirectUrl;
    } else {
      // Desktop (macOS/Windows/Linux): Use localhost for OAuth callback
      // The localhost server will handle the callback from Supabase
      // Note: This must match the redirect URL configured in Supabase Dashboard
      return 'http://localhost:${AppEnv.oauthCallbackPort}';
    }
  }

  /// Make sure the profile row exists and record the login.
  ///
  /// The `on_auth_user_created` trigger normally creates the row at sign-up;
  /// the insert here is only a fallback. Role and company are managed by the
  /// database and never sent from the client.
  Future<void> _updateUserProfile(User user) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final existing = await _supabase
          .from('users')
          .select('id, name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      final avatar =
          user.userMetadata?['avatar_url'] as String? ??
          user.userMetadata?['picture'] as String?;

      if (existing == null) {
        _log('Profile missing, creating it for ${user.email}');
        await _supabase.from('users').upsert({
          'id': user.id,
          'email': user.email?.toLowerCase(),
          'name': extractUserName(user),
          'avatar_url': avatar,
          'last_login_at': now,
        });
      } else {
        await _supabase
            .from('users')
            .update({
              'last_login_at': now,
              // Keep a name the user edited; fill it in only if missing
              if ((existing['name'] as String?)?.trim().isEmpty ?? true)
                'name': extractUserName(user),
              if (existing['avatar_url'] == null && avatar != null)
                'avatar_url': avatar,
            })
            .eq('id', user.id);
      }
    } catch (e) {
      // Never block sign-in on this; the app works without last_login_at
      _logError('Failed to update user profile', e);
    }
  }

  /// Get user profile from public.users table
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final userId = currentUserId;
      if (userId == null) return null;

      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      _logError('Failed to get user profile', e);
      rethrow;
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({String? name}) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      await _supabase
          .from('users')
          .update({
            'name': ?name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      _logError('Failed to update user profile', e);
      rethrow;
    }
  }

  /// Permanently delete the signed-in account and its tracked data.
  /// Company admins must hand over the admin role first (enforced server-side).
  Future<void> deleteAccount() async {
    if (currentUserId == null) throw Exception('User not logged in');
    await _supabase.rpc('delete_my_account');
    await _supabase.auth.signOut();
    if (!kIsWeb) await SessionPersistenceService().clearSession();
  }

  /// Refresh the current session
  Future<AuthResponse?> refreshSession() async {
    try {
      final response = await _supabase.auth.refreshSession();
      return response;
    } on AuthException catch (e) {
      _logError('Session refresh failed', e);
      rethrow;
    }
  }

  /// Check if session is expired
  bool isSessionExpired() {
    final session = currentSession;
    if (session == null) return true;

    final expiresAtSeconds = session.expiresAt;
    if (expiresAtSeconds == null) return true;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtSeconds * 1000,
    );

    return DateTime.now().isAfter(expiresAt);
  }

  // Logging helpers
  void _log(String message) {
    debugPrint('[AuthService] $message');
  }

  void _logError(String message, dynamic error) {
    debugPrint('[AuthService] ERROR: $message - $error');
  }
}
