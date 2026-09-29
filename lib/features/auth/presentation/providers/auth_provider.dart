import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/user_role.dart';
import '../../data/datasource/auth_service.dart';
import '../../data/repository/user_repository.dart';
import '../../../../core/constants/app_env.dart';
import '../../../../core/utils/logger.dart';

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final UserRepository? _userRepository;
  AuthStatus _status = AuthStatus.loading;
  User? _user;
  Map<String, dynamic>? _userProfile;
  String? _errorMessage;
  String? _oauthError;
  String? _oauthErrorDescription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _initialized = false;
  Timer? _startupTimeout;

  AuthProvider(this._authService, {UserRepository? userRepository})
    : _userRepository = userRepository {
    _initialize();
  }

  // Getters
  AuthStatus get status => _status;
  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  String? get errorMessage => _errorMessage;
  String? get oauthError => _oauthError;
  String? get oauthErrorDescription => _oauthErrorDescription;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get hasOAuthError => _oauthError != null;

  /// True once the saved session has been restored (or found missing).
  /// Later "loading" states — signing in, signing out — keep it true, so the
  /// UI shows the splash only on start-up.
  bool get isInitialized => _initialized;

  String? get userId => _user?.id;

  UserRole get role => UserRole.fromString(_userProfile?['role']);
  bool get isAdmin => role.isAdmin;

  void _initialize() {
    // Always start in loading state so the UI shows a spinner
    // while we wait for Supabase to restore the session.
    _status = AuthStatus.loading;

    // Check if Supabase already has a user in memory (fast path — happens
    // when SharedPreferences restore has already completed synchronously).
    _user = _authService.currentUser;

    Logger.info('AuthProvider initializing', {
      'currentUser': _user?.email,
      'haveUserImmediately': (_user != null).toString(),
    });

    if (_user != null) {
      // We already know the user — transition immediately.
      _status = AuthStatus.authenticated;
      _loadUserProfile();
    }

    // Track whether the very first auth event has been received.
    // We need this to know when it's safe to transition to unauthenticated
    // (we never want to jump to unauthenticated before Supabase has had a
    // chance to fire its initialSession event).
    bool receivedFirstEvent = _user != null; // already resolved if user found

    // Safety timeout: if Supabase hasn't fired any auth event within 6 seconds
    // (e.g. offline / cold start), default to unauthenticated so the user
    // isn't stuck on the loading spinner forever.
    if (!receivedFirstEvent) {
      _startupTimeout = Timer(const Duration(seconds: 6), () {
        if (!receivedFirstEvent) {
          Logger.info(
            'AuthProvider: timeout waiting for first auth event — defaulting to unauthenticated',
          );
          receivedFirstEvent = true;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
        }
      });
    }

    // Listen to auth state changes
    _authSubscription = _authService.authStateChanges.listen((authState) {
      Logger.info('Auth state changed', {
        'event': authState.event.toString(),
        'previousUser': _user?.email,
        'newUser': authState.session?.user.email,
      });

      _startupTimeout?.cancel();
      receivedFirstEvent = true;

      _user = authState.session?.user;
      _status = _user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;

      if (_user != null) {
        Logger.info('User authenticated', {
          'email': _user!.email,
          'id': _user!.id,
        });
        _loadUserProfile();
      } else {
        Logger.info('User signed out or no session');
        _userProfile = null;
      }

      notifyListeners();
    });

    // Only notify immediately if we already resolved the user state.
    // If we're still waiting, the listener above will call notifyListeners()
    // when Supabase fires the first event.
    if (_user != null) {
      notifyListeners();
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      debugPrint('[AuthProvider] 🔄 Loading user profile...');
      _userProfile = await _authService.getUserProfile();
      debugPrint('[AuthProvider] ✅ User profile loaded: $_userProfile');
      debugPrint('[AuthProvider] Raw Role from DB: ${_userProfile?['role']}');
      debugPrint('[AuthProvider] Parsed Role: $role');
      debugPrint('[AuthProvider] Is Admin?: $isAdmin');
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] ❌ Error loading user profile: $e');

      // Check if user account was deleted
      if (e.toString().contains('User account has been deleted') ||
          e.toString().contains(
            'Cannot coerce the result to a single JSON object',
          )) {
        debugPrint('[AuthProvider] 👤 User account deleted, signing out...');
        await signOut();
        _errorMessage = 'Your account has been deleted. Please sign in again.';
        notifyListeners();
      }
    }
  }

  /// Sign in with Google using browser-based OAuth
  Future<bool> signInWithGoogle() async {
    try {
      Logger.info('Starting Google sign-in process');
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final result = await _authService.signInWithGoogle();
      Logger.info('Google sign-in initiated successfully', {
        'result': result.toString(),
        'note': 'Auth state listener will handle user state updates',
      });

      // Note: Auth state listener will handle updating user state
      // For desktop, browser will open and callback will be handled
      // For web, page will redirect (this code won't continue)
      return true;
    } catch (e, stackTrace) {
      Logger.error('Google sign-in failed', e, stackTrace);
      _status = AuthStatus.unauthenticated;
      _errorMessage = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Sign in with Email and Password
  Future<bool> signInWithEmailPassword(String email, String password) async {
    try {
      Logger.info('Starting Email/Password sign-in process');
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final success = await _authService.signInWithEmailPassword(
        email,
        password,
      );
      if (!success) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
      return success;
    } catch (e, stackTrace) {
      Logger.error('Email sign-in failed', e, stackTrace);
      _status = AuthStatus.unauthenticated;
      _errorMessage = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Sign up with Email and Password
  Future<bool> signUpWithEmailPassword(
    String email,
    String password, {
    String? name,
  }) async {
    try {
      Logger.info('Starting Email/Password sign-up process');
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      final success = await _authService.signUpWithEmailPassword(
        email,
        password,
        name: name,
      );
      if (!success) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
      return success;
    } catch (e, stackTrace) {
      Logger.error('Email sign-up failed', e, stackTrace);
      _status = AuthStatus.unauthenticated;
      _errorMessage = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      _status = AuthStatus.loading;
      notifyListeners();

      debugPrint('[AuthProvider] 🔄 Starting sign out process...');

      // Clear all local data before signing out
      if (_userRepository != null) {
        debugPrint('[AuthProvider] 🗑️  Clearing local data...');
        await _userRepository.clearAllLocalData();
        debugPrint('[AuthProvider] ✅ Local data cleared');
      }

      // Sign out from Supabase
      await _authService.signOut();

      _user = null;
      _userProfile = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;

      debugPrint('[AuthProvider] ✅ Sign out complete');
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] ❌ Error during sign out: $e');
      _errorMessage = _getErrorMessage(e);
      notifyListeners();
    }
  }

  // Update profile
  Future<bool> updateProfile({String? name}) async {
    try {
      _errorMessage = null;
      notifyListeners();

      await _authService.updateUserProfile(name: name);
      await _loadUserProfile();
      return true;
    } catch (e) {
      _errorMessage = _getErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// E-mails a password-reset link. Returns an error message or null.
  Future<String?> sendPasswordReset(String email) async {
    try {
      final base = AppEnv.webAppUrl;
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: base.isEmpty ? null : base,
      );
      return null;
    } catch (e) {
      return _getErrorMessage(e);
    }
  }

  /// Sets a new password for the signed-in (e-mail) account.
  Future<String?> changePassword(String newPassword) async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return null;
    } catch (e) {
      return _getErrorMessage(e);
    }
  }

  /// True when the account signs in with e-mail + password (not Google).
  bool get usesPassword =>
      (_user?.appMetadata['providers'] as List?)?.contains('email') ??
      _user?.appMetadata['provider'] == 'email';

  // Clear error message
  void clearError() {
    _errorMessage = null;
    _oauthError = null;
    _oauthErrorDescription = null;
    notifyListeners();
  }

  // Set OAuth error from URL fragment
  void setOAuthError(String error, String? description) {
    _oauthError = error;
    _oauthErrorDescription = description;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // Extract user-friendly error message
  String _getErrorMessage(dynamic error) {
    if (error is AuthException) {
      switch (error.statusCode) {
        case '400':
          return 'Invalid request. Please try again.';
        case '401':
          return 'Authentication failed. Please check your credentials.';
        case '422':
          return 'Invalid email or password format.';
        case '500':
          return 'Server error. Please try again later.';
        default:
          return error.message;
      }
    }
    return error.toString();
  }

  @override
  void notifyListeners() {
    if (_status != AuthStatus.loading) _initialized = true;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _startupTimeout?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
