import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/tracking/presentation/providers/activity_tracking_provider.dart';
import 'package:time_trak/features/timesheet/presentation/widgets/activity_timesheet_view.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class CalendarGrid extends StatefulWidget {
  const CalendarGrid({super.key});

  @override
  State<CalendarGrid> createState() => CalendarGridState();
}

class CalendarGridState extends State<CalendarGrid> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ActivityTrackingProvider>().refreshMonth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ActivityTrackingProvider>();
    final stats = provider.monthStats;
    final gutter = context.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label:
                    'Worked ${formatSeconds((stats['total_work_seconds'] as num?)?.toInt() ?? 0)}',
                color: AppColors.primary,
                icon: Icons.work_outline_rounded,
              ),
              StatusPill(
                label:
                    'Breaks ${formatSeconds((stats['total_break_seconds'] as num?)?.toInt() ?? 0)}',
                color: AppColors.warning,
                icon: Icons.coffee_rounded,
              ),
              TextButton.icon(
                onPressed: provider.refreshMonth,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(AppStrings.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: ActivityTimesheetView(
                  month: provider.currentMonth,
                  monthStats: stats,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
