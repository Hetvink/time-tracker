import 'package:flutter/foundation.dart';

/// Provider to manage user impersonation state for admin users
/// Allows admins to view the application as another user in read-only mode
class ImpersonationProvider extends ChangeNotifier {
  String? _impersonatedUserId;
  Map<String, dynamic>? _impersonatedUserProfile;
  bool _isImpersonating = false;

  // ============================================================================
  // GETTERS
  // ============================================================================

  /// Whether the admin is currently impersonating a user
  bool get isImpersonating => _isImpersonating;

  /// The ID of the user being impersonated (null if not impersonating)
  String? get impersonatedUserId => _impersonatedUserId;

  /// The profile data of the user being impersonated
  Map<String, dynamic>? get impersonatedUserProfile => _impersonatedUserProfile;

  /// The effective user ID to use for data queries
  /// Returns impersonated user ID if impersonating, otherwise null
  /// Repositories should use this to determine which user's data to fetch
  String? get effectiveUserId => _impersonatedUserId;

  /// Get the display name of the impersonated user
  String? get impersonatedUserName =>
      _impersonatedUserProfile?['name'] as String?;

  /// Get the email of the impersonated user
  String? get impersonatedUserEmail =>
      _impersonatedUserProfile?['email'] as String?;

  // ============================================================================
  // IMPERSONATION CONTROL
  // ============================================================================

  /// Start impersonating a user
  ///
  /// [userId] - The ID of the user to impersonate
  /// [userProfile] - The profile data of the user (name, email, role, etc.)
  ///
  /// This puts the app into read-only mode where the admin can see
  /// what the user sees, but cannot perform any destructive actions.
  Future<void> startImpersonation(
    String userId,
    Map<String, dynamic> userProfile,
  ) async {
    debugPrint(
      '[ImpersonationProvider] Starting impersonation for user: $userId',
    );

    _impersonatedUserId = userId;
    _impersonatedUserProfile = userProfile;
    _isImpersonating = true;

    notifyListeners();

    debugPrint(
      '[ImpersonationProvider] ✅ Impersonation started for: ${userProfile['name']}',
    );
  }

  /// End impersonation and return to admin view
  void endImpersonation() {
    debugPrint('[ImpersonationProvider] Ending impersonation');

    _impersonatedUserId = null;
    _impersonatedUserProfile = null;
    _isImpersonating = false;

    notifyListeners();

    debugPrint(
      '[ImpersonationProvider] ✅ Impersonation ended, returned to admin view',
    );
  }

  /// Check if a specific user is currently being impersonated
  bool isImpersonatingUser(String userId) {
    return _isImpersonating && _impersonatedUserId == userId;
  }
}
