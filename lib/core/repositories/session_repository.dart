import '../models/session_model.dart';
import 'package:time_trak/features/tracking/data/models/attendance_state.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';

/// Abstract repository for Session operations
/// Implementations:
/// - Desktop: LocalSessionRepository (SQLite + sync to Supabase)
/// - Web: SupabaseSessionRepository (read-only from Supabase)
abstract class SessionRepository {
  /// Get sessions within a date range
  Future<List<SessionModel>> getSessionsInRange({
    required DateTime startDate,
    required DateTime endDate,
    String? userId, // For admin viewing other users
  });

  /// Get a single session by ID
  Future<SessionModel?> getSessionById(String id);

  /// Get active session for current user
  Future<SessionModel?> getActiveSession();

  /// Get today's sessions
  Future<List<SessionModel>> getTodaySessions();

  /// Get this month's sessions
  Future<List<SessionModel>> getThisMonthSessions();

  /// Create a new session (desktop only)
  Future<SessionModel> createSession(SessionModel session);

  /// Update an existing session (desktop only)
  Future<void> updateSession(SessionModel session);

  /// Close a session (desktop only)
  Future<void> closeSession(
    String sessionId, {
    required DateTime checkOutTime,
    required SessionSource checkOutSource,
  });

  /// Get total work duration for a date range
  Future<Duration> getTotalWorkDuration({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  });

  /// Stream of session updates (for real-time dashboard)
  Stream<List<SessionModel>>? watchSessions({
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Get breaks for a session
  Future<List<BreakPeriod>> getBreaksForSession(String sessionId);

  /// Get work during sleep periods for a session
  Future<List<WorkDuringSleepPeriod>> getWorkDuringSleepForSession(
    String sessionId,
  );

  /// Update last seen time (heartbeat)
  Future<void> updateSessionLastSeen(String sessionId, DateTime lastSeenTime);
}
