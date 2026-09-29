import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/activity_tracking_provider.dart';
import '../providers/attendance_provider.dart';
import '../../../timesheet/presentation/widgets/activity_timesheet_view.dart';
import '../../../timesheet/presentation/widgets/day_timeline_view.dart';
import '../../../../theme/macos_theme.dart';

/// SIMPLIFIED: Activity Tracking Page
/// Shows monthly calendar with activity timeline
class ActivityTrackingPage extends StatefulWidget {
  const ActivityTrackingPage({super.key});

  @override
  State<ActivityTrackingPage> createState() => _ActivityTrackingPageState();
}

class _ActivityTrackingPageState extends State<ActivityTrackingPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();

    // Listen to attendance changes to refresh activity timeline
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AttendanceProvider>().addListener(_onAttendanceChange);
      }
    });
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    try {
      context.read<AttendanceProvider>().removeListener(_onAttendanceChange);
    } catch (e) {
      // Provider might be disposed
    }
    super.dispose();
  }

  void _onAttendanceChange() {
    if (mounted) {
      debugPrint('[ACTIVITY UI] Attendance changed, refreshing timeline');
      context.read<ActivityTrackingProvider>().refreshMonth();
    }
  }

  /// Start periodic refresh timer for real-time stat updates
  /// Only runs when viewing the current month
  void _startRefreshTimer() {
    _stopRefreshTimer();

    // Check if we're viewing the current month
    final provider = context.read<ActivityTrackingProvider>();
    final now = DateTime.now();
    final isCurrentMonth =
        provider.currentMonth.year == now.year &&
        provider.currentMonth.month == now.month;

    if (isCurrentMonth) {
      // Refresh stats every 30 seconds for real-time updates
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) {
          debugPrint('[ACTIVITY UI] Auto-refreshing month stats');
          context.read<ActivityTrackingProvider>().refreshMonth();
        }
      });
    }
  }

  /// Stop the refresh timer
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<ActivityTrackingProvider>();

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFF5F5F5),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with stats
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Activity Timeline',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showDayTimeline(context),
                          icon: const Icon(Icons.view_timeline, size: 18),
                          label: const Text('Day View'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MacOSTheme.systemBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            provider.refreshMonth();
                            // Restart timer to ensure continuous updates
                            _startRefreshTimer();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Stats cards - Always show values, no loading text on refresh
                Row(
                  children: [
                    _buildStatCard(
                      theme,
                      'Total Work Time',
                      _formatDuration(
                        provider.monthStats['total_work_seconds'] ?? 0,
                      ),
                      MacOSTheme.systemGreen,
                      Icons.work_outline,
                      isDark,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      theme,
                      'Total Break Time',
                      _formatDuration(
                        provider.monthStats['total_break_seconds'] ?? 0,
                      ),
                      MacOSTheme.systemOrange,
                      Icons.coffee,
                      isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Calendar view
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF3D3D3D)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ActivityTimesheetView(
                  month: provider.currentMonth,
                  monthStats: provider.monthStats,
                  onMonthChanged: _startRefreshTimer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    ThemeData theme,
    String label,
    String value,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDayTimeline(BuildContext context) async {
    // Pick a date
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: MacOSTheme.systemBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDate != null && context.mounted) {
      // Show timeline in a full-screen dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF2D2D2D)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // Dialog header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Day Timeline View',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                // Timeline content
                Expanded(child: DayTimelineView(date: selectedDate)),
              ],
            ),
          ),
        ),
      );
    }
  }

  String _formatDuration(int seconds) {
    // Handle zero or negative values
    if (seconds <= 0) {
      return '0h 0m';
    }

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
