abstract class IAdminRepository {
  Future<List<Map<String, dynamic>>> getAllUsers({
    String? searchQuery,
    String? roleFilter,
  });
  Future<Map<String, dynamic>> getUserById(String userId);
  Future<List<Map<String, dynamic>>> getUserSessions({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  });
  Future<Map<String, dynamic>> getUserStatistics({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  });
}
