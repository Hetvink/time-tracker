import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/timeline_segment.dart';
import '../../../tracking/presentation/providers/activity_tracking_provider.dart';
import '../../../tracking/data/repository/attendance_repository.dart';
import '../../../../theme/macos_theme.dart';
import 'activity_detail_dialog.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Custom ScrollBehavior for web to enable drag scrolling
class WebScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

/// Google Timesheet-style Activity View
/// - Hours (0-23) on the left side
/// - Days across the top
/// - Bi-directional scrolling
class ActivityTimesheetView extends StatefulWidget {
  final DateTime month;
  final Map<String, dynamic> monthStats;
  final VoidCallback? onMonthChanged;

  const ActivityTimesheetView({
    super.key,
    required this.month,
    required this.monthStats,
    this.onMonthChanged,
  });

  @override
  State<ActivityTimesheetView> createState() => _ActivityTimesheetViewState();
}

class _ActivityTimesheetViewState extends State<ActivityTimesheetView> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _timeVerticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _setupScrollSync();
  }

  // Guards to prevent recursive scroll sync (each jumpTo fires the other listener)
  bool _isSyncingHorizontal = false;
  bool _isSyncingVertical = false;

  void _setupScrollSync() {
    // Sync horizontal scrolling between day headers and grid.
    // IMPORTANT: jumpTo() must be deferred via addPostFrameCallback.
    // Calling it directly inside a scroll listener can fire during Flutter's
    // layout phase (inside RenderSliverList.performLayout), causing the
    // "setState() called during build" crash.
    _horizontalController.addListener(() {
      if (_isSyncingHorizontal) return;
      if (_headerHorizontalController.hasClients &&
          _headerHorizontalController.offset != _horizontalController.offset) {
        _isSyncingHorizontal = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_headerHorizontalController.hasClients) {
            _headerHorizontalController.jumpTo(_horizontalController.offset);
          }
          _isSyncingHorizontal = false;
        });
      }
    });

    _headerHorizontalController.addListener(() {
      if (_isSyncingHorizontal) return;
      if (_horizontalController.hasClients &&
          _horizontalController.offset != _headerHorizontalController.offset) {
        _isSyncingHorizontal = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_horizontalController.hasClients) {
            _horizontalController.jumpTo(_headerHorizontalController.offset);
          }
          _isSyncingHorizontal = false;
        });
      }
    });

    // Sync vertical scrolling between time labels and grid
    _verticalController.addListener(() {
      if (_isSyncingVertical) return;
      if (_timeVerticalController.hasClients &&
          _timeVerticalController.offset != _verticalController.offset) {
        _isSyncingVertical = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_timeVerticalController.hasClients) {
            _timeVerticalController.jumpTo(_verticalController.offset);
          }
          _isSyncingVertical = false;
        });
      }
    });

    _timeVerticalController.addListener(() {
      if (_isSyncingVertical) return;
      if (_verticalController.hasClients &&
          _verticalController.offset != _timeVerticalController.offset) {
        _isSyncingVertical = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_verticalController.hasClients) {
            _verticalController.jumpTo(_timeVerticalController.offset);
          }
          _isSyncingVertical = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _headerHorizontalController.dispose();
    _timeVerticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final daysInMonth = _getDaysInMonth(widget.month);
    final dayWidth = 120.0;
    final hourHeight = TimelineConstants.defaultHourHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month header with navigation
        _buildMonthHeader(theme, isDark),

        // Main content area
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed time column (left side)
              Column(
                children: [
                  // Empty corner space above time labels
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.3),
                        ),
                        right: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Time',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Time labels (scrollable)
                  Expanded(
                    child: _TimeColumn(
                      controller: _timeVerticalController,
                      hourHeight: hourHeight,
                      theme: theme,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),

              // Right side: Day headers + activity grid
              Expanded(
                child: Column(
                  children: [
                    // Day headers (scrollable horizontally)
                    SizedBox(
                      height: 60,
                      child: _DayHeaders(
                        controller: _headerHorizontalController,
                        month: widget.month,
                        daysInMonth: daysInMonth,
                        dayWidth: dayWidth,
                        theme: theme,
                        isDark: isDark,
                      ),
                    ),

                    // Activity grid (scrollable both directions)
                    Expanded(
                      child: _ActivityGrid(
                        horizontalController: _horizontalController,
                        verticalController: _verticalController,
                        month: widget.month,
                        daysInMonth: daysInMonth,
                        dayWidth: dayWidth,
                        hourHeight: hourHeight,
                        theme: theme,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month,
            size: 20,
            color: MacOSTheme.systemBlue,
          ),
          const SizedBox(width: 8),
          Text(
            _formatMonthYear(widget.month),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Navigation buttons
          IconButton(
            onPressed: () {
              final newMonth = DateTime(
                widget.month.year,
                widget.month.month - 1,
              );
              context.read<ActivityTrackingProvider>().setMonth(newMonth);
              widget.onMonthChanged?.call();
            },
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: AppStrings.previousMonth,
          ),
          IconButton(
            onPressed: () {
              final newMonth = DateTime(
                widget.month.year,
                widget.month.month + 1,
              );
              context.read<ActivityTrackingProvider>().setMonth(newMonth);
              widget.onMonthChanged?.call();
            },
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: AppStrings.nextMonth,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              context.read<ActivityTrackingProvider>().setMonth(DateTime.now());
              widget.onMonthChanged?.call();
            },
            icon: const Icon(Icons.today, size: 16),
            label: const Text(AppStrings.today),
            style: ElevatedButton.styleFrom(
              backgroundColor: MacOSTheme.systemBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  int _getDaysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  String _formatMonthYear(DateTime date) {
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
    return '${months[date.month - 1]} ${date.year}';
  }
}

/// Fixed time column showing hours 0-23
class _TimeColumn extends StatelessWidget {
  final ScrollController controller;
  final double hourHeight;
  final ThemeData theme;
  final bool isDark;

  const _TimeColumn({
    required this.controller,
    required this.hourHeight,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: ListView.builder(
        controller: controller,
        itemCount: 24,
        itemExtent: hourHeight,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return Container(
            height: hourHeight,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _formatHour(index),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatHour(int hour) {
    // 24-hour format: 00, 01, ..., 23
    return hour.toString().padLeft(2, '0');
  }
}

/// Scrollable day headers
class _DayHeaders extends StatelessWidget {
  final ScrollController controller;
  final DateTime month;
  final int daysInMonth;
  final double dayWidth;
  final ThemeData theme;
  final bool isDark;

  const _DayHeaders({
    required this.controller,
    required this.month,
    required this.daysInMonth,
    required this.dayWidth,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: ScrollConfiguration(
        behavior: kIsWeb
            ? WebScrollBehavior()
            : ScrollConfiguration.of(context).copyWith(),
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemCount: daysInMonth,
          itemExtent: dayWidth,
          itemBuilder: (context, index) {
            final date = DateTime(month.year, month.month, index + 1);
            final isToday =
                date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;

            return Container(
              width: dayWidth,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Day number
                  Container(
                    width: 32,
                    height: 32,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: MacOSTheme.systemBlue,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isToday ? Colors.white : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Weekday
                  Text(
                    _formatWeekday(date.weekday),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: isToday
                          ? MacOSTheme.systemBlue
                          : theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatWeekday(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }
}

/// Main activity grid with bi-directional scrolling
class _ActivityGrid extends StatelessWidget {
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final DateTime month;
  final int daysInMonth;
  final double dayWidth;
  final double hourHeight;
  final ThemeData theme;
  final bool isDark;

  const _ActivityGrid({
    required this.horizontalController,
    required this.verticalController,
    required this.month,
    required this.daysInMonth,
    required this.dayWidth,
    required this.hourHeight,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: kIsWeb
          ? WebScrollBehavior()
          : ScrollConfiguration.of(context).copyWith(),
      child: SingleChildScrollView(
        controller: verticalController,
        child: SingleChildScrollView(
          controller: horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: daysInMonth * dayWidth,
            height: 24 * hourHeight,
            child: Stack(
              children: [
                // Grid background
                _buildGridBackground(),
                // Activity columns for each day
                ...List.generate(daysInMonth, (index) {
                  final date = DateTime(month.year, month.month, index + 1);
                  return Positioned(
                    left: index * dayWidth,
                    top: 0,
                    width: dayWidth,
                    height: 24 * hourHeight,
                    child: _DayActivityColumn(
                      date: date,
                      dayWidth: dayWidth,
                      hourHeight: hourHeight,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridBackground() {
    return Column(
      children: List.generate(24, (hourIndex) {
        return Row(
          children: List.generate(daysInMonth, (dayIndex) {
            return Container(
              width: dayWidth,
              height: hourHeight,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                  right: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );
  }
}

/// Activity column for a single day
class _DayActivityColumn extends StatefulWidget {
  final DateTime date;
  final double dayWidth;
  final double hourHeight;

  const _DayActivityColumn({
    required this.date,
    required this.dayWidth,
    required this.hourHeight,
  });

  @override
  State<_DayActivityColumn> createState() => _DayActivityColumnState();
}

class _DayActivityColumnState extends State<_DayActivityColumn> {
  /// Loaded blocks (null until the first load finishes) or the load error.
  final _blocks = ValueNotifier<({List<TimelineBlock>? blocks, Object? error})>(
    (blocks: null, error: null),
  );
  int _load = 0;
  Object? _lastActivityId;
  int _lastRefreshCounter = -1;
  Timer? _autoRefreshTimer;
  // Store provider reference so dispose() can safely remove the listener
  // without accessing context (which is unsafe after widget removal).
  ActivityTrackingProvider? _provider;

  @override
  void initState() {
    super.initState();

    // CRITICAL: Initialize refresh counter and attach listener AFTER the
    // first frame so the widget tree is fully built.
    // Guard against the race where the widget is disposed before the
    // callback fires — if not mounted, skip adding the listener entirely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<ActivityTrackingProvider>();
      _lastRefreshCounter = _provider!.refreshCounter;
      _provider!.addListener(_onProviderChange);
    });

    // Load data after setting up listener
    _loadData();
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(_DayActivityColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _loadData();
      _startAutoRefresh(); // Restart timer for new date
    }
  }

  /// Called when provider notifies listeners
  /// ENHANCED: Forces data reload on every refresh counter change
  /// FIXED: Silent updates after first load to prevent loading spinner flicker
  void _onProviderChange() {
    if (!mounted) return;

    // Use the stored _provider reference — avoids calling context.read()
    // from within a listener callback which can be unsafe during teardown.
    final provider = _provider;
    if (provider == null) return;

    // Reload silently when the data or the current activity changed.
    final activityId = provider.currentActivity?.id;
    if (_lastRefreshCounter != provider.refreshCounter ||
        _lastActivityId != activityId) {
      _lastRefreshCounter = provider.refreshCounter;
      _lastActivityId = activityId;
      _loadData(silent: true);
    }
  }

  /// Start auto-refresh timer for active sessions
  /// Only refresh for today's date to avoid unnecessary updates
  /// ENHANCED: Refresh every 10 seconds for more responsive time display
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();

    // Only auto-refresh if this column is for today
    final today = DateTime.now();
    final isToday =
        widget.date.year == today.year &&
        widget.date.month == today.month &&
        widget.date.day == today.day;

    if (isToday) {
      // CRITICAL FIX: Refresh every 10 seconds (was 30) for more responsive time updates
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          _loadData(silent: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _provider?.removeListener(_onProviderChange);
    _blocks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: _blocks,
      builder: (context, state, _) {
        if (state.blocks == null && state.error == null) {
          return const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  MacOSTheme.systemBlue,
                ),
              ),
            ),
          );
        }
        if (state.blocks == null) {
          return Center(
            child: Tooltip(
              message: 'Error loading data: ${state.error}',
              child: Icon(
                Icons.error_outline,
                size: 20,
                color: MacOSTheme.systemRed.withValues(alpha: 0.5),
              ),
            ),
          );
        }
        return _buildContent(context, theme, state.blocks!);
      },
    );
  }

  Future<List<TimelineBlock>> _fetchBlocks(
    ActivityTrackingProvider provider,
    AttendanceRepository attendanceRepo,
  ) async {
    final allSessions = await attendanceRepo.getSessionsForDate(widget.date);
    final blocks = <TimelineBlock>[];

    for (var sessionMap in allSessions) {
      try {
        final sessionId = sessionMap['id'] as String;
        final checkOutStr = sessionMap['check_out_time'] as String?;
        final checkOutUtcStr = sessionMap['check_out_time_utc'] as String?;
        final isClosed = (sessionMap['is_closed'] as int? ?? 0) == 1;

        DateTime checkOut;
        if (isClosed && checkOutStr != null) {
          checkOut = checkOutUtcStr != null
              ? DateTime.parse(checkOutUtcStr).toLocal()
              : DateTime.parse(checkOutStr);
        } else {
          checkOut = DateTime.now();
        }

        final activities = await provider.getActivitiesForSession(sessionId);
        for (var act in activities) {
          final actStart = act.startTime.toLocal();
          final actEnd =
              act.endTime?.toLocal() ?? (isClosed ? checkOut : DateTime.now());
          final duration = actEnd.difference(actStart);

          if (duration.inSeconds > 0) {
            blocks.add(
              TimelineBlock(
                startTime: actStart,
                endTime: actEnd,
                blockType: 'app_activity',
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error processing session: $e');
      }
    }

    return TimelineBlock.removeOverlaps(blocks);
  }

  /// Fetches the blocks for [widget.date]. A [silent] reload keeps the
  /// current blocks on screen instead of showing the spinner.
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    final request = ++_load;
    if (!silent) _blocks.value = (blocks: null, error: null);
    try {
      final blocks = await _fetchBlocks(
        context.read<ActivityTrackingProvider>(),
        context.read<AttendanceRepository>(),
      );
      if (mounted && request == _load) {
        _blocks.value = (blocks: blocks, error: null);
      }
    } catch (e) {
      if (mounted && request == _load) {
        _blocks.value = (blocks: _blocks.value.blocks, error: e);
      }
    }
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    List<TimelineBlock> blocks,
  ) {
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: blocks.map((block) => _buildBlock(block, theme)).toList(),
    );
  }

  Widget _buildBlock(TimelineBlock block, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final isBreak = block.blockType == 'break';
    final isWorkDuringSleep = block.blockType == 'work_during_sleep';

    Color color;
    if (isBreak) {
      color = MacOSTheme.systemOrange;
    } else {
      // Both regular work and work-during-sleep show as Green
      color = MacOSTheme.systemGreen;
    }

    final top = block.topPosition;
    final height = block.height.clamp(
      TimelineConstants.minVisibleHeight,
      double.infinity,
    );

    // Build main work block
    final mainBlock = Positioned(
      top: top,
      left: 4,
      right: 4,
      height: height,
      child: GestureDetector(
        onTap: () {
          // Only show dialog for work blocks (not breaks)
          if (!isBreak && !isWorkDuringSleep) {
            showDialog(
              context: context,
              builder: (context) => ActivityDetailDialog(
                startTime: block.startTime,
                endTime: block.endTime,
                activities: block.activities,
                blockType: block.blockType,
                note: block.note,
                relatedSleepPeriods: block.relatedSleepPeriods,
              ),
            );
          }
        },
        child: MouseRegion(
          cursor: (!isBreak && !isWorkDuringSleep)
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            decoration: BoxDecoration(
              // Enhanced visibility with distinct colors for different block types
              color: (isBreak || isWorkDuringSleep)
                  ? (isDark
                        ? color.withValues(alpha: 0.25)
                        : color.withValues(alpha: 0.2))
                  : (isDark
                        ? color.withValues(alpha: 0.15)
                        : color.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: (isBreak || isWorkDuringSleep)
                    ? color.withValues(alpha: 0.6)
                    : color.withValues(alpha: 0.4),
                width: (isBreak || isWorkDuringSleep) ? 1.0 : 0.5,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: height >= TimelineConstants.minContentHeight
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon for break or work-during-sleep (needs at least 35px for icon + text)
                      if (isBreak && height >= 35)
                        Icon(Icons.coffee_rounded, size: 12, color: color),
                      if (isBreak && height >= 35) const SizedBox(height: 2),
                      Text(
                        isBreak
                            ? 'BREAK'
                            : isWorkDuringSleep
                            ? (block.note != null && block.note!.isNotEmpty
                                  ? block.note!
                                  : 'WORK')
                            : '${_formatTime(block.startTime)}-${_formatTime(block.endTime)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: height < 30 ? 8 : 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                      // Show duration for breaks and work-during-sleep (needs at least 50px for icon + text + duration)
                      if ((isBreak || isWorkDuringSleep) && height >= 50)
                        const SizedBox(height: 2),
                      if ((isBreak || isWorkDuringSleep) && height >= 50)
                        Text(
                          '${block.durationMinutes}m',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: color.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    // Build red sleep period boxes overlayed on work blocks
    final sleepBoxes = <Widget>[];
    if (!isBreak &&
        !isWorkDuringSleep &&
        block.relatedSleepPeriods.isNotEmpty) {
      for (var sleepPeriod in block.relatedSleepPeriods) {
        // Calculate absolute position on timeline for sleep period
        final sleepAbsoluteTop = sleepPeriod.topPosition;
        final sleepAbsoluteHeight = sleepPeriod.height.clamp(
          TimelineConstants.minVisibleHeight,
          double.infinity,
        );

        debugPrint('[TIMELINE] Work block: top=$top, height=$height');
        debugPrint(
          '[TIMELINE] Sleep period: absoluteTop=$sleepAbsoluteTop, height=$sleepAbsoluteHeight',
        );

        sleepBoxes.add(
          Positioned(
            top: sleepAbsoluteTop,
            left: 8,
            right: 8,
            height: sleepAbsoluteHeight,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: isDark ? 0.4 : 0.35),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Return main block and sleep boxes as separate widgets
    return Stack(children: [mainBlock, ...sleepBoxes]);
  }

  String _formatTime(DateTime time) {
    // Always use local time in 24-hour format
    final localTime = time.toLocal();
    final hours = localTime.hour.toString().padLeft(2, '0');
    final minutes = localTime.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}
