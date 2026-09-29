import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../timesheet/data/models/daily_timesheet.dart';
import '../../data/models/attendance_state.dart';
import '../../../../theme/macos_theme.dart';
import '../providers/attendance_provider.dart';

class SessionCard extends StatefulWidget {
  final AttendanceSession session;
  final bool isActiveOverride;
  final bool isOnBreak;
  final Duration currentBreakDuration;
  final DateTime? breakStartTime;

  const SessionCard({
    super.key,
    required this.session,
    this.isActiveOverride = false,
    this.isOnBreak = false,
    this.currentBreakDuration = Duration.zero,
    this.breakStartTime,
  });

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActiveOverride || !widget.session.isClosed;
    if (isActive) {
      return Consumer<AttendanceProvider>(
        builder: (context, _, child) => _buildCard(context),
      );
    }
    return _buildCard(context);
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActiveOverride || !widget.session.isClosed;

    final statusColor = isActive
        ? (widget.isOnBreak ? MacOSTheme.systemOrange : MacOSTheme.systemGreen)
        : MacOSTheme.systemGray;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.session.isContinuation
              ? MacOSTheme.systemOrange.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.1),
          width: widget.session.isContinuation ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Session Indicator & Check-in Source
          if (widget.session.isContinuation)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MacOSTheme.systemOrange.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(9),
                  topRight: Radius.circular(9),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link,
                    size: 14,
                    color: MacOSTheme.systemOrange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Continued from previous day',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: MacOSTheme.systemOrange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ExpansionTile(
            shape: const Border(), // Remove default border
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isActive
                    ? (widget.isOnBreak
                          ? Icons.coffee_rounded
                          : Icons.timelapse_rounded)
                    : Icons.check_circle_outline,
                color: statusColor,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Text(
                  widget.session.checkInTimeFormatted,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: MacOSTheme.systemGray,
                ),
                const SizedBox(width: 8),
                Text(
                  isActive
                      ? (widget.isOnBreak ? 'On Break' : 'Active')
                      : widget.session.checkOutTimeFormatted,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isActive ? statusColor : null,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Duration: ${_formatDuration(_getNetWorkDuration())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: MacOSTheme.systemGray,
                ),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getSourceColor(
                  widget.session.checkInSource,
                ).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.session.sourceLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _getSourceColor(widget.session.checkInSource),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            children: [
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Time Details
              _buildDetailRow(
                context,
                'Check In',
                _formatFullTime(
                  widget.session.checkInTimeUtc?.toLocal() ??
                      widget.session.checkInTime,
                ),
              ),
              // Only show Check Out if session is closed
              if (!isActive && widget.session.checkOutTime != null)
                _buildDetailRow(
                  context,
                  'Check Out',
                  _formatFullTime(
                    widget.session.checkOutTimeUtc?.toLocal() ??
                        widget.session.checkOutTime!,
                  ),
                ),

              const SizedBox(height: 12),
              _buildDetailRow(
                context,
                'Total Duration',
                _formatDuration(_getGrossDuration()),
              ),
              _buildDetailRow(
                context,
                'Break Time',
                _formatDuration(_getCurrentBreakTime()),
              ),
              _buildDetailRow(
                context,
                'Net Work Time',
                _formatDuration(_getNetWorkDuration()),
                isBold: true,
              ),

              if (widget.session.breaks.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Breaks',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.session.breaks.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.coffee,
                          size: 14,
                          color: MacOSTheme.systemGray,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatFullTime(b.startTime),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          size: 12,
                          color: MacOSTheme.systemGray2,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          b.endTime != null
                              ? _formatFullTime(b.endTime!)
                              : 'Active',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(b.duration),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (widget.session.workDuringSleepPeriods.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Work During Sleep',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.session.workDuringSleepPeriods.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.bedtime,
                              size: 14,
                              color: MacOSTheme.systemBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatFullTime(w.sleepStartTime),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward,
                              size: 12,
                              color: MacOSTheme.systemGray2,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatFullTime(w.wakeTime),
                              style: theme.textTheme.bodySmall,
                            ),
                            const Spacer(),
                            Text(
                              _formatDuration(w.duration),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        if (w.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 22),
                            child: Text(
                              w.note,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: MacOSTheme.systemGray,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: MacOSTheme.systemGray,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSourceColor(EventSource source) {
    switch (source) {
      case EventSource.autoSystemStart:
        return MacOSTheme.systemBlue;
      case EventSource.manualUser:
        return MacOSTheme.systemGray; // More neutral for manual
      case EventSource.systemRecovery:
        return MacOSTheme.systemRed;
      case EventSource.autoMidnightTransition:
        return MacOSTheme.systemOrange;
      default:
        return MacOSTheme.systemGray;
    }
  }

  String _formatFullTime(DateTime time) {
    // CRITICAL: Always display in local timezone
    final localTime = time.toLocal();
    final hours = localTime.hour;
    final minutes = localTime.minute;
    final seconds = localTime.second;
    final period = hours >= 12 ? 'PM' : 'AM';
    final displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours);
    return '$displayHour:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} $period';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Duration _getGrossDuration() {
    final checkInUtc =
        widget.session.checkInTimeUtc ?? widget.session.checkInTime.toUtc();
    final nowUtc = DateTime.now().toUtc();

    if (widget.isActiveOverride || !widget.session.isClosed) {
      return nowUtc.difference(checkInUtc);
    }

    final checkOutUtc =
        widget.session.checkOutTimeUtc ??
        widget.session.checkOutTime?.toUtc() ??
        nowUtc;
    return checkOutUtc.difference(checkInUtc);
  }

  Duration _getCurrentBreakTime() {
    if (widget.isOnBreak && widget.breakStartTime != null) {
      final nowUtc = DateTime.now().toUtc();
      final currentBreak = nowUtc.difference(widget.breakStartTime!.toUtc());
      return widget.session.totalBreakDuration + currentBreak;
    }
    return widget.session.totalBreakDuration + widget.currentBreakDuration;
  }

  Duration _getNetWorkDuration() {
    if (widget.isActiveOverride || !widget.session.isClosed) {
      return _getGrossDuration() - _getCurrentBreakTime();
    }
    return widget.session.workDuration;
  }
}
