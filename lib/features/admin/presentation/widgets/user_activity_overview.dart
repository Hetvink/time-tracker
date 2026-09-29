import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../data/repository/admin_repository.dart';
import '../providers/admin_dashboard_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class UserActivityOverview extends StatelessWidget {
  final String userId;

  const UserActivityOverview({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final adminRepo = context.read<AdminRepository>();

    return Consumer<AdminDashboardProvider>(
      builder: (context, adminProvider, child) {
        final now = DateTime.now();
        final last30Days = now.subtract(const Duration(days: 30));
        final last7Days = now.subtract(const Duration(days: 7));

        return FutureBuilder<List<dynamic>>(
          key: ValueKey('$userId-overview-${adminProvider.refreshKey}'),
          future: Future.wait([
            adminRepo.getUserSessions(
              userId: userId,
              startDate: last30Days,
              endDate: now,
            ),
            adminRepo.getUserStatistics(
              userId: userId,
              startDate: last30Days,
              endDate: now,
            ),
            adminRepo.getUserAppActivityBreakdown(
              userId: userId,
              startDate: last7Days,
              endDate: now,
            ),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => adminProvider.refreshData(),
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                ),
              );
            }

            final results = snapshot.data ?? [[], {}, []];
            final recentSessions = (results[0] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .take(10)
                .toList();
            final statistics = results[1] as Map<String, dynamic>;
            final appBreakdown = (results[2] as List<dynamic>)
                .cast<Map<String, dynamic>>();

            return _buildOverview(
              context,
              recentSessions,
              statistics,
              appBreakdown,
            );
          },
        );
      },
    );
  }

  Widget _buildOverview(
    BuildContext context,
    List<Map<String, dynamic>> recentSessions,
    Map<String, dynamic> statistics,
    List<Map<String, dynamic>> appBreakdown,
  ) {
    final totalWork = statistics['total_work_seconds'] as int? ?? 0;
    final totalBreak = statistics['total_break_seconds'] as int? ?? 0;
    final totalSessionsCount = statistics['total_sessions'] as int? ?? 0;
    final avgWorkPerSession =
        statistics['avg_work_per_session_seconds'] as int? ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stat cards row ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      context,
                      'Total Work (30d)',
                      _formatDuration(Duration(seconds: totalWork)),
                      Icons.timer_outlined,
                      const Color(0xFF007AFF),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _statCard(
                      context,
                      'Total Break (30d)',
                      _formatDuration(Duration(seconds: totalBreak)),
                      Icons.free_breakfast_outlined,
                      const Color(0xFFFF9500),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _statCard(
                      context,
                      'Total Sessions',
                      '$totalSessionsCount',
                      Icons.check_circle_outline,
                      const Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _statCard(
                      context,
                      'Avg Work / Session',
                      _formatDuration(Duration(seconds: avgWorkPerSession)),
                      Icons.analytics_outlined,
                      const Color(0xFF5856D6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Two-column layout: sessions + app breakdown ────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildSessionsTable(recentSessions),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          child: _buildAppBreakdownTable(appBreakdown),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildSessionsTable(recentSessions),
                      const SizedBox(height: 24),
                      _buildAppBreakdownTable(appBreakdown),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return _buildStatCard(_StatData(title, value, icon, color, 'Last 30 days'));
  }

  Widget _buildStatCard(_StatData s) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: s.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.sub,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sessions Table ─────────────────────────────────────────────────────────

  Widget _buildSessionsTable([
    List<Map<String, dynamic>> recentSessions = const [],
  ]) {
    return _buildCard(
      title: AppStrings.recentSessions2,
      subtitle: AppStrings.last10Sessions30Days,
      child: recentSessions.isEmpty
          ? _buildEmpty('No recent sessions')
          : Column(
              children: [
                // Header row
                _buildTableHeaderRow(const [
                  ('Date', 2),
                  ('Check-in', 2),
                  ('Check-out', 2),
                  ('Work Time', 2),
                  ('Status', 1),
                ]),
                const Divider(height: 1, color: Color(0xFF2A2A40)),
                ...recentSessions.map((s) => _buildSessionRow(s)),
              ],
            ),
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> session) {
    final checkIn = session['check_in_time_utc'] != null
        ? DateTime.parse(session['check_in_time_utc']).toLocal()
        : DateTime.parse(session['check_in_time']);
    final checkOut = session['check_out_time_utc'] != null
        ? DateTime.parse(session['check_out_time_utc']).toLocal()
        : (session['check_out_time'] != null
              ? DateTime.parse(session['check_out_time'])
              : null);
    final totalWork = session['total_work_seconds'] as int? ?? 0;
    final isClosed = session['is_closed'] as bool? ?? false;

    final dateFmt = DateFormat('MMM dd, yyyy');
    final timeFmt = DateFormat('hh:mm a');
    final statusColor = isClosed
        ? const Color(0xFF34C759)
        : const Color(0xFFFF9500);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF252540))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              dateFmt.format(checkIn),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              timeFmt.format(checkIn),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              checkOut != null ? timeFmt.format(checkOut) : '—',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDuration(Duration(seconds: totalWork)),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isClosed ? 'Done' : 'Active',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Breakdown Table ────────────────────────────────────────────────────

  Widget _buildAppBreakdownTable([
    List<Map<String, dynamic>> appBreakdown = const [],
  ]) {
    final maxDuration = appBreakdown.isNotEmpty
        ? (appBreakdown.first['total_duration_seconds'] as int? ??
              appBreakdown.first['duration_seconds'] as int? ??
              1)
        : 1;

    return _buildCard(
      title: AppStrings.appUsage,
      subtitle: AppStrings.top10AppsLast7Days,
      child: appBreakdown.isEmpty
          ? _buildEmpty('No app activity data')
          : Column(
              children: [
                _buildTableHeaderRow(const [
                  ('#', 1),
                  ('App Name', 4),
                  ('Time', 2),
                ]),
                const Divider(height: 1, color: Color(0xFF2A2A40)),
                ...appBreakdown.asMap().entries.map((e) {
                  final idx = e.key;
                  final app = e.value;
                  final appName = app['app_name'] as String;
                  final dur =
                      (app['total_duration_seconds'] as int?) ??
                      (app['duration_seconds'] as int? ?? 0);
                  final pct = (dur / maxDuration).clamp(0.0, 1.0);
                  final color = _getAppColor(idx);

                  return Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF252540)),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.06,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    color.withValues(alpha: 0.7),
                                  ),
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 72,
                          child: Text(
                            _formatDuration(Duration(seconds: dur)),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _buildCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF252540)),
          child,
        ],
      ),
    );
  }

  Widget _buildTableHeaderRow(List<(String label, int flex)> columns) {
    return Container(
      color: Colors.white.withValues(alpha: 0.03),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: columns.map((col) {
          final label = col.$1;
          final flex = col.$2;
          if (label == '#') {
            return SizedBox(
              width: 28,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            );
          }
          return Expanded(
            flex: flex,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmpty(String msg) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text(
          msg,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Color _getAppColor(int index) {
    const colors = [
      Color(0xFF007AFF),
      Color(0xFF34C759),
      Color(0xFFFF9500),
      Color(0xFF5856D6),
      Color(0xFFFF2D55),
      Color(0xFF5AC8FA),
      Color(0xFFFFCC00),
      Color(0xFFFF3B30),
      Color(0xFF30B0C7),
      Color(0xFFAF52DE),
    ];
    return colors[index % colors.length];
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatData {
  final String title, value, sub;
  final IconData icon;
  final Color color;
  const _StatData(this.title, this.value, this.icon, this.color, this.sub);
}
