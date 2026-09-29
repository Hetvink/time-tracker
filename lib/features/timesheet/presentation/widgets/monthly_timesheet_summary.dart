import 'package:flutter/material.dart';
import '../../data/models/daily_timesheet.dart';
import '../../../../theme/macos_theme.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class MonthlyTimesheetSummary extends StatelessWidget {
  final List<DailyTimeSheet> timesheets;
  final int year;
  final int month;

  const MonthlyTimesheetSummary({
    super.key,
    required this.timesheets,
    required this.year,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final summary = _calculateMonthlySummary();
    final netWorkDuration = summary['netWork'];
    final totalWorkWithSleep = summary['totalWorkWithSleep'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monthly Summary',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MacOSTheme.systemBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_getMonthName(month)} $year',
                  style: const TextStyle(
                    color: MacOSTheme.systemBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                context,
                'Total Work',
                _formatDuration(totalWorkWithSleep),
                subtitle: AppStrings.withSleep,
                isBold: true,
              ),
              _buildSummaryItem(
                context,
                'Sleep Work',
                _formatDuration(summary['sleepWork']!),
              ),
              _buildSummaryItem(
                context,
                'Break Time',
                _formatDuration(summary['breakTime']!),
              ),
              _buildSummaryItem(
                context,
                'Net Work',
                _formatDuration(netWorkDuration),
                subtitle: AppStrings.withoutSleep,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _calculateMonthlySummary() {
    Duration totalWork = Duration.zero;
    Duration totalBreak = Duration.zero;
    Duration totalSleepWork = Duration.zero;
    int totalSessions = 0;

    for (var timesheet in timesheets) {
      // totalWorkTime is the TOTAL effective work (sessions - breaks)
      // It INCLUDES work during sleep periods
      totalWork += timesheet.totalWorkTime;
      totalBreak += timesheet.totalBreakTime;
      totalSleepWork += timesheet.totalWorkDuringSleepTime;
      totalSessions += timesheet.totalSessions;
    }

    // CRITICAL: totalWork already includes sleep work, so we DON'T add it again
    // This matches the behavior of DailyTimeSheet.totalWorkTimeWithSleep
    final totalWorkWithSleep = totalWork;

    // Net work is total work minus sleep work (normal working hours)
    final netWork = totalWork - totalSleepWork;

    return {
      'netWork': netWork.isNegative ? Duration.zero : netWork,
      'breakTime': totalBreak,
      'sleepWork': totalSleepWork,
      'totalWorkWithSleep': totalWorkWithSleep,
      'totalSessions': totalSessions,
    };
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    String value, {
    String? subtitle,
    bool isBold = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: MacOSTheme.systemGray),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: MacOSTheme.systemGray3,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    var seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    seconds = seconds % 3600;
    final minutes = seconds ~/ 60;
    seconds = seconds % 60;

    final hourStr = hours.toString().padLeft(2, '0');
    final minuteStr = minutes.toString().padLeft(2, '0');
    final secondStr = seconds.toString().padLeft(2, '0');

    return '$hourStr:$minuteStr:$secondStr';
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}
