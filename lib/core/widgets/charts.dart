import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'ui_kit.dart';

// =============================================================================
// Bar chart
// =============================================================================

class BarDatum {
  final String label;
  final double value;
  final String? tooltip;
  final bool highlight;

  const BarDatum(
    this.label,
    this.value, {
    this.tooltip,
    this.highlight = false,
  });
}

/// Vertical gradient bars (hours per day, per hour, per weekday…).
class HoursBarChart extends StatelessWidget {
  final List<BarDatum> data;
  final double height;
  final double? goal;
  final Color color;
  final ValueChanged<int>? onTap;
  final String Function(double v) axisLabel;

  /// Show every n-th bottom label (auto when null).
  final int? labelEvery;

  const HoursBarChart({
    super.key,
    required this.data,
    this.height = 220,
    this.goal,
    this.color = AppColors.primary,
    this.onTap,
    this.axisLabel = _hoursAxis,
    this.labelEvery,
  });

  static String _hoursAxis(double v) => '${v.toStringAsFixed(v < 2 ? 1 : 0)}h';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (data.isEmpty) return SizedBox(height: height);
    final maxV = data.map((d) => d.value).fold<double>(goal ?? 0, math.max);
    final top = maxV <= 0 ? 1.0 : maxV * 1.18;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / data.length;
          final barWidth = (slot * 0.62).clamp(3.0, 28.0);
          final every =
              labelEvery ?? math.max(1, (46 / slot).ceil()); // avoid overlap
          return BarChart(
            BarChartData(
              maxY: top,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: top / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colors.border,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: constraints.maxWidth > 320,
                    reservedSize: 38,
                    interval: top / 4,
                    getTitlesWidget: (v, meta) => v == 0 || v >= top * 0.99
                        ? const SizedBox.shrink()
                        : SideTitleWidget(
                            meta: meta,
                            child: Text(
                              axisLabel(v),
                              style: context.text.bodySmall?.copyWith(
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length || i % every != 0) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          data[i].label,
                          style: context.text.bodySmall?.copyWith(
                            fontSize: 10.5,
                            fontWeight: data[i].highlight
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: data[i].highlight ? colors.text : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: goal == null || goal! <= 0
                  ? null
                  : ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: goal!,
                          color: AppColors.success.withValues(alpha: 0.8),
                          strokeWidth: 1.4,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: context.text.labelSmall?.copyWith(
                              color: AppColors.success,
                            ),
                            labelResolver: (_) => 'Goal',
                          ),
                        ),
                      ],
                    ),
              barTouchData: BarTouchData(
                touchCallback: onTap == null
                    ? null
                    : (event, response) {
                        if (event is FlTapUpEvent && response?.spot != null) {
                          onTap!(response!.spot!.touchedBarGroupIndex);
                        }
                      },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => context.isDark
                      ? const Color(0xFF2A2F4D)
                      : const Color(0xFF1E2238),
                  tooltipBorderRadius: BorderRadius.circular(AppRadius.sm),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, _, rod, _) {
                    final d = data[group.x];
                    return BarTooltipItem(
                      '${d.label}\n',
                      const TextStyle(color: Colors.white70, fontSize: 11),
                      children: [
                        TextSpan(
                          text: d.tooltip ?? axisLabel(d.value),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < data.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].value,
                        width: barWidth,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(math.min(6, barWidth / 2)),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: data[i].highlight
                              ? [AppColors.violet, AppColors.cyan]
                              : [color.withValues(alpha: 0.55), color],
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: top,
                          color: colors.surfaceAlt.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: reduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        },
      ),
    );
  }
}

// =============================================================================
// Donut
// =============================================================================

class DonutSlice {
  final String label;
  final double value;
  final Color color;
  const DonutSlice(this.label, this.value, this.color);
}

class DonutChart extends StatefulWidget {
  final List<DonutSlice> slices;
  final String centerValue;
  final String centerLabel;
  final double size;

  const DonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 190,
  });

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  /// Index of the hovered/touched slice, -1 for none.
  final _touched = ValueNotifier(-1);

  @override
  void dispose() {
    _touched.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: _touched,
    builder: (context, touchedIndex, _) => _build(context, touchedIndex),
  );

  Widget _build(BuildContext context, int touchedIndex) {
    final colors = context.colors;
    final total = widget.slices.fold<double>(0, (a, s) => a + s.value);
    final touched = touchedIndex >= 0 && touchedIndex < widget.slices.length
        ? widget.slices[touchedIndex]
        : null;
    final ring = widget.size * 0.16;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2.5,
              centerSpaceRadius: widget.size / 2 - ring - 8,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final i = response?.touchedSection?.touchedSectionIndex ?? -1;
                  if (!event.isInterestedForInteractions) {
                    _touched.value = -1;
                    return;
                  }
                  _touched.value = i;
                },
              ),
              sections: total <= 0
                  ? [
                      PieChartSectionData(
                        value: 1,
                        color: colors.surfaceHover,
                        radius: ring,
                        showTitle: false,
                      ),
                    ]
                  : [
                      for (var i = 0; i < widget.slices.length; i++)
                        PieChartSectionData(
                          value: widget.slices[i].value,
                          color: widget.slices[i].color,
                          radius: i == touchedIndex ? ring + 7 : ring,
                          showTitle: false,
                          cornerRadius: 4,
                        ),
                    ],
            ),
            duration: const Duration(milliseconds: 250),
          ),
          Padding(
            padding: EdgeInsets.all(ring + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  child: Text(
                    touched == null
                        ? widget.centerValue
                        : '${(touched.value / (total == 0 ? 1 : total) * 100).round()}%',
                    style: context.text.headlineMedium,
                  ),
                ),
                Text(
                  touched?.label ?? widget.centerLabel,
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Calendar heatmap
// =============================================================================

/// Month grid (Mon–Sun) with each day shaded by tracked hours.
class CalendarHeatmap extends StatelessWidget {
  final int year;
  final int month;
  final Map<int, Duration> values; // day of month → worked
  final Duration goal;
  final int? selectedDay;
  final ValueChanged<DateTime>? onTap;

  const CalendarHeatmap({
    super.key,
    required this.year,
    required this.month,
    required this.values,
    this.goal = const Duration(hours: 8),
    this.selectedDay,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final first = DateTime(year, month);
    final days = DateUtils.getDaysInMonth(year, month);
    final lead = first.weekday - 1;
    final today = DateUtils.dateOnly(DateTime.now());
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cell = ((constraints.maxWidth - gap * 6) / 7).clamp(22.0, 64.0);
        final showText = cell >= 34;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 7; i++)
                  Container(
                    width: cell,
                    margin: EdgeInsets.only(right: i < 6 ? gap : 0),
                    alignment: Alignment.center,
                    child: Text(names[i], style: context.text.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var r = 0; r < rows; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r < rows - 1 ? gap : 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var c = 0; c < 7; c++)
                      Padding(
                        padding: EdgeInsets.only(right: c < 6 ? gap : 0),
                        child: _cell(
                          context,
                          r * 7 + c - lead + 1,
                          days,
                          cell,
                          showText,
                          today,
                          colors,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(
    BuildContext context,
    int day,
    int days,
    double size,
    bool showText,
    DateTime today,
    AppColors colors,
  ) {
    if (day < 1 || day > days) return SizedBox(width: size, height: size);
    final date = DateTime(year, month, day);
    final worked = values[day] ?? Duration.zero;
    final ratio = goal.inSeconds == 0
        ? 0.0
        : (worked.inSeconds / goal.inSeconds).clamp(0.0, 1.2);
    final isFuture = date.isAfter(today);
    final isToday = date == today;
    final selected = selectedDay == day;
    final bg = worked == Duration.zero
        ? colors.surfaceAlt
        : Color.lerp(
            AppColors.primary.withValues(alpha: 0.18),
            ratio >= 1 ? AppColors.success : AppColors.violet,
            (ratio.clamp(0.0, 1.0) * 0.85).toDouble(),
          )!;

    return Tooltip(
      message:
          '${DateFormat('EEE d MMM').format(date)}\n${worked == Duration.zero ? 'No time tracked' : formatHm(worked)}',
      child: InkWell(
        onTap: onTap == null || isFuture ? null : () => onTap!(date),
        borderRadius: BorderRadius.circular(size * 0.22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isFuture ? Colors.transparent : bg,
            borderRadius: BorderRadius.circular(size * 0.22),
            border: Border.all(
              color: selected
                  ? AppColors.cyan
                  : isToday
                  ? AppColors.primary
                  : isFuture
                  ? colors.border
                  : Colors.transparent,
              width: selected || isToday ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: showText
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: context.text.labelMedium?.copyWith(
                        color: worked > Duration.zero && ratio > 0.5
                            ? Colors.white
                            : isFuture
                            ? colors.textSubtle
                            : colors.text,
                      ),
                    ),
                    if (worked > Duration.zero && size >= 46)
                      Text(
                        formatHoursShort(worked),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: ratio > 0.5
                              ? Colors.white.withValues(alpha: 0.85)
                              : colors.textMuted,
                        ),
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

/// Legend swatch row: "Less ▢▢▢▢ More".
class HeatLegend extends StatelessWidget {
  const HeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget sw(Color c) => Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Less', style: context.text.bodySmall),
        const SizedBox(width: 6),
        sw(colors.surfaceAlt),
        sw(AppColors.primary.withValues(alpha: 0.35)),
        sw(Color.lerp(AppColors.primary, AppColors.violet, 0.5)!),
        sw(AppColors.violet),
        sw(AppColors.success),
        const SizedBox(width: 6),
        Text('Goal', style: context.text.bodySmall),
      ],
    );
  }
}

// =============================================================================
// Day timeline
// =============================================================================

enum SegmentKind { work, breakTime, sleep, app }

class TimelineSegment {
  final DateTime start;
  final DateTime end;
  final SegmentKind kind;
  final String? label;
  final Color? color;

  const TimelineSegment(
    this.start,
    this.end,
    this.kind, {
    this.label,
    this.color,
  });

  Duration get duration => end.difference(start);
}

/// Horizontal time axis with work / break lanes and an optional app lane.
/// Zooms to the part of the day that has data.
class DayTimelineBar extends StatelessWidget {
  final DateTime day;
  final List<TimelineSegment> segments;
  final List<TimelineSegment> apps;

  const DayTimelineBar({
    super.key,
    required this.day,
    required this.segments,
    this.apps = const [],
  });

  Color _color(TimelineSegment s) =>
      s.color ??
      switch (s.kind) {
        SegmentKind.work => AppColors.primary,
        SegmentKind.breakTime => AppColors.warning,
        SegmentKind.sleep => AppColors.pink,
        SegmentKind.app => AppColors.cyan,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final all = [...segments, ...apps];

    // Zoom to the busy part of the day (whole hours, at least 6h wide).
    var from = dayStart;
    var to = dayEnd;
    if (all.isNotEmpty) {
      final first = all
          .map((s) => s.start)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final last = all.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);
      var h0 = (first.isBefore(dayStart) ? 0 : first.hour) - 1;
      var h1 = (last.isAfter(dayEnd) ? 24 : last.hour + 1) + 1;
      h0 = h0.clamp(0, 24);
      h1 = h1.clamp(0, 24);
      if (h1 - h0 < 6) {
        final pad = ((6 - (h1 - h0)) / 2).ceil();
        h0 = (h0 - pad).clamp(0, 18);
        h1 = (h0 + 6).clamp(6, 24);
      }
      from = dayStart.add(Duration(hours: h0));
      to = dayStart.add(Duration(hours: h1));
    }
    final span = to.difference(from).inSeconds.toDouble();
    final hours = to.difference(from).inHours;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        double x(DateTime t) {
          final clamped = t.isBefore(from) ? from : (t.isAfter(to) ? to : t);
          return clamped.difference(from).inSeconds / span * w;
        }

        Widget lane(List<TimelineSegment> items, double height) => SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              for (final s in items)
                if (s.end.isAfter(from) && s.start.isBefore(to))
                  Positioned(
                    left: x(s.start),
                    width: math.max(2, x(s.end) - x(s.start)),
                    top: 0,
                    bottom: 0,
                    child: Tooltip(
                      message:
                          '${s.label ?? _kindLabel(s.kind)}\n${formatTime(s.start)} – ${formatTime(s.end)} · ${formatHm(s.duration)}',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _color(s),
                              _color(s).withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );

        final step = hours <= 8 ? 1 : (hours <= 14 ? 2 : 3);
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    lane(segments, 34),
                    if (apps.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      lane(apps, 18),
                    ],
                  ],
                ),
                if (now.isAfter(from) && now.isBefore(to))
                  Positioned(
                    left: x(now) - 1,
                    top: -4,
                    bottom: -4,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: Stack(
                children: [
                  for (var h = 0; h <= hours; h += step)
                    Positioned(
                      left: (h / hours * w - 14).clamp(0, w - 28),
                      width: 28,
                      child: Text(
                        '${(from.hour + h) % 24}'.padLeft(2, '0'),
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _kindLabel(SegmentKind k) => switch (k) {
    SegmentKind.work => 'Working',
    SegmentKind.breakTime => 'Break',
    SegmentKind.sleep => 'Worked while asleep',
    SegmentKind.app => 'App',
  };
}

/// Small coloured legend entry.
class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const LegendDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.text.bodySmall),
      ],
    );
  }
}
