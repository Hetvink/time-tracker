import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/daily_timesheet.dart';
import '../../../tracking/data/models/attendance_state.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../../../../theme/macos_theme.dart';

class LiveTimesheetSummary extends StatelessWidget {
  final DailyTimeSheet timesheet;
  final AttendanceProvider? attendanceProvider;

  const LiveTimesheetSummary({
    super.key,
    required this.timesheet,
    this.attendanceProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, activeAttendanceProvider, child) {
        final provider = attendanceProvider ?? activeAttendanceProvider;
        final state = provider.state;

        Duration workTotal = Duration.zero;
        Duration breakTotal = Duration.zero;
        Duration sleepWorkTotal = Duration.zero;

        for (var session in timesheet.sessions) {
          if ((state.status == AttendanceStatus.checkedIn ||
                  state.status == AttendanceStatus.onBreak) &&
              session.id == state.currentSessionId) {
            final nowUtc = DateTime.now().toUtc();
            final checkInUtc =
                session.checkInTimeUtc ?? session.checkInTime.toUtc();

            final breakPeriods = <({DateTime start, DateTime end})>[];

            for (var breakPeriod in session.breaks) {
              if (breakPeriod.endTime != null) {
                breakPeriods.add((
                  start: breakPeriod.startTime.toUtc(),
                  end: breakPeriod.endTime!.toUtc(),
                ));
              }
            }

            if (state.status == AttendanceStatus.onBreak &&
                state.breakStartTime != null) {
              breakPeriods.add((
                start: state.breakStartTime!.toUtc(),
                end: nowUtc,
              ));
            }

            breakPeriods.sort((a, b) => a.start.compareTo(b.start));

            Duration sessionWorkTime = Duration.zero;
            DateTime currentPosition = checkInUtc;

            for (var breakPeriod in breakPeriods) {
              if (breakPeriod.start.isAfter(currentPosition)) {
                sessionWorkTime += breakPeriod.start.difference(
                  currentPosition,
                );
              }
              if (breakPeriod.end.isAfter(currentPosition)) {
                currentPosition = breakPeriod.end;
              }
            }

            if (nowUtc.isAfter(currentPosition)) {
              sessionWorkTime += nowUtc.difference(currentPosition);
            }

            workTotal += sessionWorkTime;

            Duration sessionBreakTime = session.totalBreakDuration;
            if (state.status == AttendanceStatus.onBreak) {
              sessionBreakTime += state.currentBreakDuration;
            }
            breakTotal += sessionBreakTime;

            for (var sleepPeriod in session.workDuringSleepPeriods) {
              sleepWorkTotal += sleepPeriod.duration;
            }
          } else {
            workTotal += session.netWorkDuration;
            breakTotal += session.totalBreakDuration;

            for (var sleepPeriod in session.workDuringSleepPeriods) {
              sleepWorkTotal += sleepPeriod.duration;
            }
          }
        }

        final netWorkDuration = (workTotal - sleepWorkTotal).isNegative
            ? Duration.zero
            : workTotal - sleepWorkTotal;

        final totalGrossDuration = workTotal + breakTotal;

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
              Text(
                'Daily Summary',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem(
                    context,
                    'Total Duration',
                    _formatDuration(totalGrossDuration),
                    isBold: true,
                  ),
                  _buildSummaryItem(
                    context,
                    'Sleep Work',
                    _formatDuration(sleepWorkTotal),
                  ),
                  _buildSummaryItem(
                    context,
                    'Break Time',
                    _formatDuration(breakTotal),
                  ),
                  _buildSummaryItem(
                    context,
                    'Net Work',
                    _formatDuration(netWorkDuration),
                    subtitle: 'Without Sleep',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
}
