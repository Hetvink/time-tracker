import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../providers/history_page_provider.dart';
import '../widgets/daily_timesheet_table.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class FullHistoryPage extends StatelessWidget {
  const FullHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HistoryPageProvider(),
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: const Text(AppStrings.attendanceHistory),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Consumer<AttendanceProvider>(
          builder: (context, provider, child) {
            return FutureBuilder<List<Map<String, int>>>(
              future: provider.getAvailableMonths(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final months = snapshot.data ?? [];

                if (months.isEmpty) {
                  return const Center(
                    child: Text(
                      'No history available.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: months.length,
                  itemBuilder: (context, index) {
                    final monthData = months[index];
                    final year = monthData['year']!;
                    final month = monthData['month']!;
                    final isInitiallyExpanded = index == 0;

                    return _MonthExpansionTile(
                      year: year,
                      month: month,
                      initiallyExpanded: isInitiallyExpanded,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MonthExpansionTile extends StatelessWidget {
  final int year;
  final int month;
  final bool initiallyExpanded;

  const _MonthExpansionTile({
    required this.year,
    required this.month,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime(year, month);
    final monthName = DateFormat('MMMM yyyy').format(date);
    final attendanceProvider = Provider.of<AttendanceProvider>(
      context,
      listen: false,
    );

    return Consumer<HistoryPageProvider>(
      builder: (context, historyProvider, child) {
        final isLoading = historyProvider.isMonthLoading(year, month);
        final timesheets = historyProvider.getMonthTimesheets(year, month);

        if (initiallyExpanded && timesheets == null && !isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            historyProvider.fetchMonthData(year, month, attendanceProvider);
          });
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: initiallyExpanded,
              iconColor: Colors.white,
              collapsedIconColor: Colors.white54,
              textColor: Colors.white,
              collapsedTextColor: Colors.white,
              title: Text(
                monthName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              onExpansionChanged: (expanded) {
                historyProvider.setMonthExpanded(year, month, expanded);
                if (expanded) {
                  historyProvider.fetchMonthData(
                    year,
                    month,
                    attendanceProvider,
                  );
                }
              },
              children: [
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (timesheets != null)
                  DailyTimesheetTable(timesheets: timesheets)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
    );
  }
}
