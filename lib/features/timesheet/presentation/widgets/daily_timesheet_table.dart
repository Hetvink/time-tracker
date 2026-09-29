import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../data/models/daily_timesheet.dart';
import '../../../settings/presentation/providers/preferences_service.dart';

class DailyTimesheetTable extends StatelessWidget {
  final List<DailyTimeSheet> timesheets;

  const DailyTimesheetTable({super.key, required this.timesheets});

  @override
  Widget build(BuildContext context) {
    if (timesheets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'No sessions found.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive design based on available width
        final isWide = constraints.maxWidth >= 1200;
        final isMedium =
            constraints.maxWidth >= 900 && constraints.maxWidth < 1200;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                0: const FixedColumnWidth(140), // Date
                1: const FixedColumnWidth(100), // Clock In
                2: const FixedColumnWidth(100), // Clock Out
                3: const FixedColumnWidth(90), // Break Time
                4: const FixedColumnWidth(110), // Net Work Time
                if (isWide || isMedium)
                  5: const FixedColumnWidth(110), // Work During Sleep
                if (isWide || isMedium)
                  6: const FixedColumnWidth(120), // Total Work (with sleep)
                if (isWide || isMedium)
                  7: const FixedColumnWidth(120)
                else
                  5: const FixedColumnWidth(120), // Status
              },
              children: [
                // Header Row
                TableRow(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    border: const Border(
                      bottom: BorderSide(color: Colors.white10),
                    ),
                  ),
                  children: [
                    _buildHeaderCell('DATE'),
                    _buildHeaderCell('CLOCK IN'),
                    _buildHeaderCell('CLOCK OUT'),
                    _buildHeaderCell('BREAK'),
                    _buildHeaderCell('NET WORK'),
                    if (isWide || isMedium) _buildHeaderCell('SLEEP WORK'),
                    if (isWide || isMedium) _buildHeaderCell('TOTAL WORK'),
                    _buildHeaderCell('STATUS'),
                  ],
                ),
                // Data Rows
                ...timesheets
                    .where((timesheet) => timesheet.sessions.isNotEmpty)
                    .map((timesheet) {
                      return TableRow(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white10),
                          ),
                        ),
                        children: [
                          _buildDataCell(
                            context,
                            DateFormat('MMM dd, yyyy').format(timesheet.date),
                          ),
                          _buildDataCell(
                            context,
                            _formatTime(
                              _getLocalCheckInTime(timesheet.sessions.first),
                            ),
                          ),
                          _buildDataCell(
                            context,
                            _getLocalCheckOutTime(timesheet.sessions.last) !=
                                    null
                                ? _formatTime(
                                    _getLocalCheckOutTime(
                                      timesheet.sessions.last,
                                    )!,
                                  )
                                : 'Active',
                          ),
                          _buildDataCell(
                            context,
                            _formatDurationShort(timesheet.totalBreakTime),
                          ),
                          _buildDataCell(
                            context,
                            _formatDurationShort(timesheet.netWorkTime),
                          ),
                          if (isWide || isMedium)
                            _buildDataCell(
                              context,
                              _formatDurationShort(
                                timesheet.totalWorkDuringSleepTime,
                              ),
                            ),
                          if (isWide || isMedium)
                            _buildDataCell(
                              context,
                              _formatDurationShort(
                                timesheet.totalGrossWorkTime,
                              ),
                              isBold: true,
                            ),
                          _buildStatusCell(context, timesheet),
                        ],
                      );
                    }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDataCell(
    BuildContext context,
    String text, {
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStatusCell(BuildContext context, DailyTimeSheet timesheet) {
    final prefs = Provider.of<PreferencesService>(context, listen: false);
    final goalMinutes = prefs.dailyGoalMinutes;
    final isCompleted = timesheet.totalWorkTime.inMinutes >= goalMinutes;

    String statusText = isCompleted ? 'Completed' : 'Partial';
    Color statusColor = isCompleted
        ? const Color(0xFF34C759)
        : const Color(0xFFFFA726); // Green : Orange
    Color bgColor = statusColor.withValues(alpha: 0.2);

    if (timesheet.hasActiveSessions) {
      statusText = 'In Progress';
      statusColor = const Color(0xFF0A84FF); // Blue
      bgColor = statusColor.withValues(alpha: 0.2);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get the local check-in time, preferring UTC converted to local
  DateTime _getLocalCheckInTime(AttendanceSession session) {
    // Prefer UTC time converted to local to avoid timezone issues
    if (session.checkInTimeUtc != null) {
      return session.checkInTimeUtc!.toLocal();
    }
    // Fallback to checkInTime (may have timezone issues with old data)
    return session.checkInTime;
  }

  /// Get the local check-out time, preferring UTC converted to local
  DateTime? _getLocalCheckOutTime(AttendanceSession session) {
    // Prefer UTC time converted to local to avoid timezone issues
    if (session.checkOutTimeUtc != null) {
      return session.checkOutTimeUtc!.toLocal();
    }
    // Fallback to checkOutTime (may have timezone issues with old data)
    return session.checkOutTime;
  }

  String _formatTime(DateTime time) {
    return DateFormat('hh:mm a').format(time);
  }

  String _formatDurationShort(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}
