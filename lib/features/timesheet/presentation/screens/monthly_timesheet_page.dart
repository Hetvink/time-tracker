import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/daily_timesheet.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../providers/timesheet_page_provider.dart';
import '../../../../theme/macos_theme.dart';
import '../widgets/monthly_timesheet_summary.dart';
import '../widgets/daily_timesheet_table.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class MonthlyTimeSheetPage extends StatelessWidget {
  const MonthlyTimeSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TimeSheetPageProvider(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Consumer<TimeSheetPageProvider>(
          builder: (context, pageProvider, child) {
            final selectedYear = pageProvider.selectedYear;
            final selectedMonth = pageProvider.selectedMonth;

            return Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_view_month_rounded,
                            size: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Monthly Timesheet',
                            style: Theme.of(context).textTheme.displayLarge,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: pageProvider.refresh,
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: AppStrings.refresh,
                          ),
                          const SizedBox(width: 8),
                          // Month/Year Picker Button
                          TextButton.icon(
                            onPressed: () =>
                                _selectMonthYear(context, pageProvider),

                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_month_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _formatMonthYear(selectedYear, selectedMonth),
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
                  Expanded(child: _buildContent(context, pageProvider)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    TimeSheetPageProvider pageProvider,
  ) {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    final selectedYear = pageProvider.selectedYear;
    final selectedMonth = pageProvider.selectedMonth;
    final refreshKey = pageProvider.refreshKey;

    return FutureBuilder<List<DailyTimeSheet>>(
      key: ValueKey('$selectedYear-$selectedMonth-$refreshKey'),
      future: provider.getMonthlyDailyTimeSheets(
        selectedYear,
        selectedMonth,
        refresh: refreshKey > 0,
      ),

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
                  Icons.error_outline_rounded,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading data',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: MacOSTheme.systemGray,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: pageProvider.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(AppStrings.retry),
                ),
              ],
            ),
          );
        }

        final timesheets = snapshot.data ?? [];

        if (timesheets.isEmpty) {
          return SizedBox(
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
                    'No records for this month',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: MacOSTheme.systemGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check the logs for more details',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: MacOSTheme.systemGray,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            pageProvider.refresh();
            // Wait a bit for the refresh to complete
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // Monthly Summary
              MonthlyTimesheetSummary(
                timesheets: timesheets,
                year: selectedYear,
                month: selectedMonth,
              ),

              const SizedBox(height: 24),

              Text(
                'Daily Breakdown',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              // Daily Timesheet Table
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [DailyTimesheetTable(timesheets: timesheets)],
                ),
              ),

              // Add bottom padding for better scrolling
              const SizedBox(height: 48),
            ],
          ),
        );
      },
    );
  }

  String _formatMonthYear(int year, int month) {
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
    return '${months[month - 1]} $year';
  }

  Future<void> _selectMonthYear(
    BuildContext context,
    TimeSheetPageProvider pageProvider,
  ) async {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);

    // Get available months
    final availableMonths = await provider.getAvailableMonths();

    // Show dialog to select month/year
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.selectMonth),
        content: SizedBox(
          width: 300,
          height: 400,
          child: availableMonths.isEmpty
              ? const Center(child: Text(AppStrings.noDataAvailable))
              : ListView.builder(
                  itemCount: availableMonths.length,
                  itemBuilder: (context, index) {
                    final monthData = availableMonths[index];
                    final year = monthData['year'] as int;
                    final month = monthData['month'] as int;
                    final isSelected =
                        year == pageProvider.selectedYear &&
                        month == pageProvider.selectedMonth;

                    return ListTile(
                      selected: isSelected,
                      title: Text(_formatMonthYear(year, month)),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      onTap: () {
                        pageProvider.setSelectedYearMonth(year, month);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.cancel),
          ),
        ],
      ),
    );
  }
}
