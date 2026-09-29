abstract class IUserRepository {
  Future<String> upsertUser({
    required String uuid,
    required String email,
    String? name,
    String role = 'member',
  });
  Future<void> deactivateAllExcept(String activeUuid);
  Future<Map<String, dynamic>?> getUserByUuid(String uuid);
}
