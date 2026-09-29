import 'package:time_trak/features/insights/data/insights.dart'
    show prettySource;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';

import 'date_badge.dart';
import 'goal_bar.dart';

class DaysTable extends StatelessWidget {
  final List<DailyTimeSheet> days;
  final Duration goal;
  const DaysTable({super.key, required this.days, required this.goal});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = context.screenWidth < 760;
    final head = context.text.labelMedium?.copyWith(color: colors.textMuted);
    final num = context.text.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final today = DateUtils.dateOnly(DateTime.now());

    return AppCard(
      title: 'Daily breakdown',
      subtitle: 'Tap a day to see its sessions',
      icon: Icons.table_rows_rounded,
      bodyPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('Date', style: head)),
                  Expanded(flex: 5, child: Text('Sessions', style: head)),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Breaks',
                      style: head,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Worked',
                      style: head,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('Progress', style: head),
                    ),
                  ),
                ],
              ),
            ),
          for (final d in days)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _showDay(context, d),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: DateUtils.isSameDay(d.date, today)
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                  border: Border(
                    top: BorderSide(
                      color: colors.border.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: compact
                    ? Row(
                        children: [
                          DateBadge(date: d.date),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatHm(d.totalWorkTime),
                                  style: num?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '${d.sessions.length} sessions · ${formatHm(d.totalBreakTime)} breaks',
                                  style: context.text.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                GoalBar(worked: d.totalWorkTime, goal: goal),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colors.textSubtle,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                DateBadge(date: d.date),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    DateFormat('EEEE').format(d.date),
                                    style: context.text.bodyMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final s in d.sessions.take(4))
                                  StatusPill(
                                    label:
                                        '${formatTime(s.checkInTime)}–${s.checkOutTime == null ? 'now' : formatTime(s.checkOutTime)}',
                                    color: s.isClosed
                                        ? AppColors.primary
                                        : AppColors.success,
                                  ),
                                if (d.sessions.length > 4)
                                  StatusPill(
                                    label: '+${d.sessions.length - 4}',
                                    color: colors.textMuted,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHm(d.totalBreakTime),
                              style: num,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHm(d.totalWorkTime),
                              style: num?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: GoalBar(
                                worked: d.totalWorkTime,
                                goal: goal,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDay(BuildContext context, DailyTimeSheet d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              DateFormat('EEEE, d MMMM y').format(d.date),
              style: ctx.text.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatHm(d.totalWorkTime)} worked · ${formatHm(d.totalBreakTime)} breaks',
              style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.textMuted),
            ),
            const SizedBox(height: 16),
            for (final (n, s) in d.sessions.indexed) ...[
              SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Session ${n + 1}', style: ctx.text.titleMedium),
                        const Spacer(),
                        StatusPill(
                          label: s.isClosed ? 'Closed' : 'Running',
                          color: s.isClosed
                              ? AppColors.primary
                              : AppColors.success,
                          dot: !s.isClosed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InfoRow(
                      icon: Icons.login_rounded,
                      label: 'Check in',
                      value:
                          '${formatTime(s.checkInTime)} · ${prettySource(s.checkInSource.name)}',
                    ),
                    InfoRow(
                      icon: Icons.logout_rounded,
                      label: 'Check out',
                      value: s.checkOutTime == null
                          ? '—'
                          : '${formatTime(s.checkOutTime)} · ${prettySource(s.checkOutSource?.name)}',
                    ),
                    InfoRow(
                      icon: Icons.timer_rounded,
                      label: 'Worked',
                      value: formatHm(s.workDuration),
                      valueColor: AppColors.primary,
                    ),
                    for (final b in s.breaks)
                      InfoRow(
                        icon: Icons.coffee_rounded,
                        label:
                            'Break ${formatTime(b.startTime)} – ${b.endTime == null ? 'now' : formatTime(b.endTime)}',
                        value: formatHm(b.duration),
                        valueColor: AppColors.warning,
                      ),
                    if (s.continuationReason != null)
                      InfoRow(
                        icon: Icons.link_rounded,
                        label: 'Continued',
                        value: s.continuationReason!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
