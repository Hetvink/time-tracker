import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';
import '../../../timesheet/presentation/screens/full_history_page.dart';
import '../../../timesheet/presentation/widgets/daily_timesheet_table.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class DailySummaryList extends StatelessWidget {
  /// When this key changes, the list will re-fetch data from the provider.
  final int refreshKey;

  const DailySummaryList({super.key, this.refreshKey = 0});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        return FutureBuilder<List<DailyTimeSheet>>(
          key: ValueKey('daily_summary_$refreshKey'),
          future: provider.getMonthlyDailyTimeSheets(
            now.year,
            now.month,
            refresh: refreshKey > 0,
          ),
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;

            if (snapshot.hasError) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading sessions: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final timesheets = snapshot.data ?? [];

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Recent Sessions',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                            ),
                            if (isLoading) ...[
                              const SizedBox(width: 12),
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ],
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const FullHistoryPage(),
                              ),
                            );
                          },
                          child: const Text(AppStrings.viewAll),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  if (isLoading && timesheets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white54),
                      ),
                    )
                  else if (timesheets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: Text(
                          'No sessions found for this month.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    DailyTimesheetTable(timesheets: timesheets),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
