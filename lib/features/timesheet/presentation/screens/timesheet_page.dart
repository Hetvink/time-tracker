import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/daily_timesheet.dart';
import '../providers/timesheet_provider.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../providers/timesheet_page_provider.dart';
import '../../../../theme/macos_theme.dart';
import '../../../tracking/presentation/widgets/session_card.dart';
import '../../../tracking/data/models/attendance_state.dart';
import '../widgets/live_timesheet_summary.dart';

class TimeSheetPage extends StatelessWidget {
  const TimeSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TimeSheetPageProvider>(
      builder: (context, pageProvider, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Consumer<AttendanceProvider>(
            builder: (context, attendanceProvider, _) {
              return Consumer<TimeSheetProvider>(
                builder: (context, timeSheetProvider, child) {
                  return FutureBuilder<DailyTimeSheet>(
                    key: ValueKey(
                      '${pageProvider.selectedDate.toIso8601String()}_${attendanceProvider.state.status}',
                    ),
                    future: timeSheetProvider.getTimesheetForDate(
                      pageProvider.selectedDate,
                    ),
                    builder: (context, snapshot) {
                      return Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Timesheet',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.displayLarge,
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        pageProvider.setSelectedDate(
                                          pageProvider.selectedDate,
                                        );
                                      },
                                      icon: const Icon(Icons.refresh_rounded),
                                      tooltip: 'Refresh',
                                    ),
                                    const SizedBox(width: 8),
                                    // Date Picker Button
                                    TextButton.icon(
                                      onPressed: () =>
                                          _selectDate(context, pageProvider),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _formatFullDate(
                                          pageProvider.selectedDate,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),

                            // Content
                            // Content
                            Expanded(
                              child: _buildContent(
                                context,
                                snapshot,
                                attendanceProvider,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<DailyTimeSheet> snapshot,
    AttendanceProvider attendanceProvider,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      log(snapshot.error.toString());
      return Center(child: Text('Error: ${snapshot.error}'));
    }

    final timesheet = snapshot.data;

    return RefreshIndicator(
      onRefresh: () async {
        final pageProvider = Provider.of<TimeSheetPageProvider>(
          context,
          listen: false,
        );
        pageProvider.setSelectedDate(pageProvider.selectedDate);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (timesheet == null || timesheet.sessions.isEmpty)
            // ... (existing code for empty state)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 64,
                      color: MacOSTheme.systemGray3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No records for this day',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: MacOSTheme.systemGray,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Summary Section
            LiveTimesheetSummary(
              timesheet: timesheet,
              attendanceProvider: attendanceProvider,
            ),

            const SizedBox(height: 24),

            Text(
              'Detailed Sessions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            // List of sessions
            ...timesheet.sessions.map((session) {
              final isCurrentSession =
                  session.id == attendanceProvider.state.currentSessionId;
              final isCheckedIn =
                  attendanceProvider.state.status == AttendanceStatus.checkedIn;
              final isOnBreak =
                  attendanceProvider.state.status == AttendanceStatus.onBreak;

              final isGlobalActive =
                  isCurrentSession && (isCheckedIn || isOnBreak);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SessionCard(
                  session: session,
                  isActiveOverride: isGlobalActive,
                  isOnBreak: isCurrentSession && isOnBreak,
                  currentBreakDuration: isCurrentSession && isOnBreak
                      ? attendanceProvider.state.currentBreakDuration
                      : Duration.zero,
                  breakStartTime: isCurrentSession && isOnBreak
                      ? attendanceProvider.state.breakStartTime
                      : null,
                ),
              );
            }),
            // Add bottom padding for better scrolling
            const SizedBox(height: 48),
          ],
        ],
      ),
    );
  }

  String _formatFullDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _selectDate(
    BuildContext context,
    TimeSheetPageProvider pageProvider,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: pageProvider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != pageProvider.selectedDate) {
      pageProvider.setSelectedDate(picked);
    }
  }
}
