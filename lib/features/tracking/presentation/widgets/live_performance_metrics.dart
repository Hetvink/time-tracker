import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../../data/models/attendance_state.dart';

class LivePerformanceMetrics extends StatelessWidget {
  final AttendanceProvider? provider;

  const LivePerformanceMetrics({super.key, this.provider});

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, attendanceProvider, child) {
        final activeProvider = provider ?? attendanceProvider;
        final state = activeProvider.state;

        // Calculate live durations
        final liveWorkDuration =
            state.status == AttendanceStatus.checkedIn ||
                state.status == AttendanceStatus.onBreak
            ? state.totalWorkTime
            : Duration.zero;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Metrics',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 600 ? 2 : 4;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildMetricCard(
                      context,
                      icon: Icons.coffee_outlined,
                      iconColor: const Color(0xFFFF9F0A),
                      iconBgColor: const Color(0xFF3E2D12),
                      label: 'Break Time (Today)',
                      value: _formatDurationShort(
                        activeProvider.todayClosedBreakDuration,
                      ),
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.verified_user_outlined,
                      iconColor: const Color(0xFF0A84FF),
                      iconBgColor: const Color(0xFF002B5C),
                      label: 'Total Hours (All-time)',
                      value: _formatDurationShort(
                        activeProvider.allTimeClosedDuration + liveWorkDuration,
                      ),
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.access_time_outlined,
                      iconColor: const Color(0xFFBF5AF2), // System Purple
                      iconBgColor: const Color(0xFF3F1D52),
                      label: 'Total Sessions',
                      value: '${activeProvider.totalSessionsCount}',
                    ),
                    _buildMetricCard(
                      context,
                      icon: Icons.calendar_month_outlined,
                      iconColor: const Color(0xFF34C759), // System Green
                      iconBgColor: const Color(0xFF0F3D17),
                      label: 'Total Hours (This Month)',
                      value: _formatDurationShort(
                        activeProvider.monthClosedDuration + liveWorkDuration,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    required String value,
    String? trend,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D), // Dark card
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F3D17),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trend,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF32D74B),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDurationShort(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m';
  }
}
