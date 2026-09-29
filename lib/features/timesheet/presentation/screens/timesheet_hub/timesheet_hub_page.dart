import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/tracking/presentation/providers/attendance_provider.dart';
import 'package:time_trak/features/timesheet/presentation/providers/monthly_timesheet_controller.dart';

import 'widgets/calendar_grid.dart';
import 'widgets/monthly_timesheet.dart';

/// Official monthly timesheet (stored session totals) plus the hour-by-hour
/// calendar grid.
class TimesheetHubPage extends StatelessWidget {
  const TimesheetHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    return ChangeNotifierProvider(
      create: (context) =>
          MonthlyTimesheetController(context.read<AttendanceProvider>()),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 8),
                child: const PageHeader(
                  eyebrow: 'Records',
                  title: 'Timesheet',
                  subtitle:
                      'Your official monthly hours, day by day, ready to export.',
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Monthly timesheet'),
                    Tab(text: 'Calendar grid'),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(
                child: TabBarView(
                  // The grid scrolls sideways, so no swiping between tabs.
                  physics: NeverScrollableScrollPhysics(),
                  children: [
                    KeepAlivePage(child: MonthlyTimesheet()),
                    CalendarGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Monthly timesheet
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Calendar grid (hour × day matrix)
// -----------------------------------------------------------------------------
