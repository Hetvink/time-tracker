import '../models/user_model.dart';

/// Abstract repository for User operations
/// Shared by both desktop and web
abstract class UserRepositoryInterface {
  /// Get current authenticated user
  Future<UserModel?> getCurrentUser();

  /// Get user by ID
  Future<UserModel?> getUserById(String id);

  /// Get user by email
  Future<UserModel?> getUserByEmail(String email);

  /// Update user profile
  Future<void> updateUser(UserModel user);

  /// Get all users (admin only)
  Future<List<UserModel>> getAllUsers();

  /// Check if current user is admin
  Future<bool> isCurrentUserAdmin();
}
