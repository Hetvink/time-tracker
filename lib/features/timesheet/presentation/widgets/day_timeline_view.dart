import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../tracking/data/models/app_activity.dart';
import '../../data/models/day_timeline_data.dart';
import '../../data/models/timeline_segment.dart';
import '../../../tracking/presentation/providers/activity_tracking_provider.dart';
import '../../../tracking/data/repository/app_activity_repository.dart';
import '../../../tracking/data/repository/attendance_repository.dart';
import '../../../tracking/data/datasource/database_service.dart';
import '../../../tracking/data/repository/web_app_activity_repository.dart';
import '../../../tracking/data/repository/web_attendance_repository.dart';
import '../../../../theme/macos_theme.dart';
import 'activity_detail_dialog.dart';

/// Timeline view showing a complete day with work, break, and not-working periods
class DayTimelineView extends StatefulWidget {
  final DateTime date;

  const DayTimelineView({super.key, required this.date});

  @override
  State<DayTimelineView> createState() => _DayTimelineViewState();
}

class _DayTimelineViewState extends State<DayTimelineView> {
  late AttendanceRepository _attendanceRepo;
  late AppActivityRepository _activityRepo;

  /// Loaded timeline and whether a (non-silent) load is running.
  final _state = ValueNotifier<({DayTimelineData? data, bool loading})>((
    data: null,
    loading: true,
  ));
  DayTimelineData? get _timelineData => _state.value.data;
  bool get _isLoading => _state.value.loading;

  Timer? _refreshTimer;
  int _lastRefreshCounter = -1;

  @override
  void initState() {
    super.initState();
    // Post-frame callback to safely access provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<ActivityTrackingProvider>();
        _lastRefreshCounter = provider.refreshCounter;
        provider.addListener(_onProviderChange);
      }
    });

    _initializeRepositories();
    _setupAutoRefresh();
  }

  @override
  void didUpdateWidget(DayTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _loadTimelineData();
      _setupAutoRefresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _state.dispose();
    try {
      context.read<ActivityTrackingProvider>().removeListener(
        _onProviderChange,
      );
    } catch (_) {}
    super.dispose();
  }

  void _onProviderChange() {
    if (!mounted) return;
    final provider = context.read<ActivityTrackingProvider>();
    if (_lastRefreshCounter != provider.refreshCounter) {
      _lastRefreshCounter = provider.refreshCounter;
      _loadTimelineData(silent: true);
    }
  }

  void _setupAutoRefresh() {
    _refreshTimer?.cancel();

    // Only refresh if viewing today
    final now = DateTime.now();
    final isToday =
        widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;

    if (isToday) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          _loadTimelineData(silent: true);
        }
      });
    }
  }

  Future<void> _initializeRepositories() async {
    if (kIsWeb) {
      // On web, use the provided web repositories
      _attendanceRepo = context.read<WebAttendanceRepository>();
      _activityRepo = context.read<WebAppActivityRepository>();
    } else {
      // On desktop, initialize from database
      final db = await DatabaseService.database;
      _attendanceRepo = AttendanceRepository(db);
      _activityRepo = AppActivityRepository();
    }
    await _loadTimelineData();
  }

  Future<void> _loadTimelineData({bool silent = false}) async {
    if (!silent) {
      _state.value = (data: _timelineData, loading: true);
    }

    try {
      // Get timeline data from repository
      final data = await _attendanceRepo.getDayTimelineData(widget.date);

      // Convert to TimelineBlock objects
      final workBlocks = <TimelineBlock>[];
      final breakBlocks = <TimelineBlock>[];

      // Process work blocks and fetch activities
      for (var workData in data['work_blocks']) {
        final sessionId = workData['session_id']; // Can be int or String (UUID)
        final blockType = workData['block_type'] as String? ?? 'work';
        final note = workData['note'] as String?;

        // CRITICAL: Convert to local time immediately after parsing to ensure consistent display
        final rawStartTime = workData['start_time'] as DateTime;
        final rawEndTime = workData['end_time'] as DateTime;
        final startTime = rawStartTime.toLocal();
        final endTime = rawEndTime.toLocal();

        // For work_during_sleep blocks, no activities to fetch
        List<AppActivity> activities = [];
        List<String> appNames = [];
        final relatedSleepPeriods = <TimelineBlock>[];

        // Fetch activities for work blocks
        if (blockType == 'work') {
          try {
            // 1. First try to fetch activities using ActivityTrackingProvider
            if (mounted) {
              final provider = context.read<ActivityTrackingProvider>();
              activities = await provider.getActivitiesForSession(sessionId);
              debugPrint(
                '[DAY_TIMELINE] Provider returned ${activities.length} activities for session $sessionId',
              );
            }

            // 2. If provider returns empty, try direct repository access
            if (activities.isEmpty) {
              debugPrint(
                '[DAY_TIMELINE] Provider returned empty, trying direct repository access for session $sessionId',
              );
              activities = await _activityRepo.getActivitiesBySession(
                sessionId,
              );
              debugPrint(
                '[DAY_TIMELINE] Repository returned ${activities.length} activities',
              );
            }

            // 4. Extract unique app names if we have activities
            if (activities.isNotEmpty) {
              appNames = activities.map((a) => a.appName).toSet().toList();
              debugPrint(
                '[DAY_TIMELINE] Found ${activities.length} activities, ${appNames.length} apps for session $sessionId',
              );
            } else {
              debugPrint(
                '[DAY_TIMELINE] No activities found for session $sessionId',
              );
            }
          } catch (e) {
            debugPrint(
              '[DAY_TIMELINE] Error fetching activities for session: $e',
            );
            // Fallback to local repo if provider fails
            try {
              activities = await _activityRepo.getActivitiesBySession(
                sessionId,
              );
              if (activities.isNotEmpty) {
                appNames = activities.map((a) => a.appName).toSet().toList();
                debugPrint(
                  '[DAY_TIMELINE] Repository fallback succeeded for session $sessionId',
                );
              }
            } catch (repoError) {
              debugPrint(
                '[DAY_TIMELINE] Repository fallback failed: $repoError',
              );
            }
          }

          // 2. Fetch related Sleep Work periods (Critical for dialog display)
          try {
            final workDuringSleepData = await _attendanceRepo
                .getWorkDuringSleepForSession(sessionId);

            for (var sleepData in workDuringSleepData) {
              if (sleepData['sleep_start_time'] != null &&
                  sleepData['wake_time'] != null) {
                DateTime startTime, endTime;

                // Use UTC times if available, otherwise fall back to local times
                if (sleepData['sleep_start_time_utc'] != null) {
                  startTime = DateTime.parse(
                    sleepData['sleep_start_time_utc'],
                  ).toLocal();
                } else {
                  startTime = DateTime.parse(sleepData['sleep_start_time']);
                }

                if (sleepData['wake_time_utc'] != null) {
                  endTime = DateTime.parse(
                    sleepData['wake_time_utc'],
                  ).toLocal();
                } else {
                  endTime = DateTime.parse(sleepData['wake_time']);
                }

                relatedSleepPeriods.add(
                  TimelineBlock(
                    startTime: startTime,
                    endTime: endTime,
                    blockType: 'work_during_sleep',
                    note: sleepData['note'] as String?,
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('[DAY_TIMELINE] ERROR fetching sleep periods: $e');
          }
        }

        workBlocks.add(
          TimelineBlock(
            startTime: startTime,
            endTime: endTime,
            blockType: blockType,
            appNames: appNames,
            activities: activities,
            note: note,
            relatedSleepPeriods: relatedSleepPeriods,
          ),
        );
      }

      // Process break blocks
      for (var breakData in (data['break_blocks'] as List? ?? [])) {
        final rawStartTime = breakData['start_time'] as DateTime;
        final rawEndTime = breakData['end_time'] as DateTime;
        final startTime = rawStartTime.toLocal();
        final endTime = rawEndTime.toLocal();

        breakBlocks.add(
          TimelineBlock(
            startTime: startTime,
            endTime: endTime,
            blockType: 'break',
          ),
        );
      }

      final timelineData = DayTimelineData(
        date: widget.date,
        workBlocks: workBlocks,
        breakBlocks: breakBlocks,
        notWorkingBlocks: [],
      );

      if (mounted) _state.value = (data: timelineData, loading: false);
    } catch (e) {
      debugPrint('[DAY_TIMELINE] ERROR loading timeline data: $e');
      if (mounted) _state.value = (data: _timelineData, loading: false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _state,
    builder: (context, _, _) => _buildTimeline(context),
  );

  Widget _buildTimeline(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_timelineData == null || !_timelineData!.hasActivity) {
      return _buildEmptyState();
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _buildHeader(),
          TabBar(
            labelColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Sessions'),
              Tab(text: 'Mixed Activities'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_buildSectionedView(), _buildMixedActivitiesView()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? MacOSTheme.darkSidebar
            : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: theme.brightness == Brightness.dark
                ? MacOSTheme.darkDivider
                : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today,
            color: MacOSTheme.systemBlue,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(widget.date),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(_timelineData!.totalWorkTime)} work • ${_formatDuration(_timelineData!.totalBreakTime)} break',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionedView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Separate blocks by type
    final workBlocks = _timelineData!.workBlocks
        .where((b) => b.blockType == 'work')
        .toList();

    // Sort break blocks by start time to show them chronologically
    final breakBlocks = _timelineData!.breakBlocks.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Work Sessions Section
          if (workBlocks.isNotEmpty) ...[
            _buildSectionHeader(
              theme: theme,
              isDark: isDark,
              icon: Icons.work_outline,
              title: 'Work Sessions',
              color: MacOSTheme.systemGreen,
              totalDuration: _calculateTotalDuration(workBlocks),
              count: workBlocks.length,
            ),
            const SizedBox(height: 12),
            ...workBlocks.map((block) => _buildBlockCard(block, theme, isDark)),
            const SizedBox(height: 24),
          ],

          // Breaks Section
          if (breakBlocks.isNotEmpty) ...[
            _buildSectionHeader(
              theme: theme,
              isDark: isDark,
              icon: Icons.coffee,
              title: 'Breaks',
              color: MacOSTheme.systemOrange,
              totalDuration: _calculateTotalDuration(breakBlocks),
              count: breakBlocks.length,
            ),
            const SizedBox(height: 12),
            ...breakBlocks.map(
              (block) => _buildBlockCard(block, theme, isDark),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required String title,
    required Color color,
    required Duration totalDuration,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? 'session' : 'sessions'} • ${_formatDuration(totalDuration)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockCard(TimelineBlock block, ThemeData theme, bool isDark) {
    Color color;
    IconData icon;

    switch (block.blockType) {
      case 'work':
        color = MacOSTheme.systemGreen;
        icon = Icons.work;
        break;
      case 'work_during_sleep':
        color = MacOSTheme.systemBlue;
        icon = Icons.bedtime;
        break;
      case 'break':
        color = MacOSTheme.systemOrange;
        icon = Icons.coffee;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
    }

    final duration = block.duration;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () => _showBlockDetails(block),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.2 : 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatTime(block.startTime)} - ${_formatTime(block.endTime)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (block.blockType == 'work' &&
                            block.appNames.isNotEmpty)
                          Text(
                            block.appNames.take(3).join(', ') +
                                (block.appNames.length > 3 ? '...' : ''),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (block.note != null)
                          Row(
                            children: [
                              Icon(
                                Icons.note,
                                size: 12,
                                color: color.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  block.note!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.7),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.2 : 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _formatDuration(duration),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              // Show sleep periods as nested red boxes for work blocks
              if (block.blockType == 'work' &&
                  block.relatedSleepPeriods.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...block.relatedSleepPeriods.map((sleepPeriod) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bedtime, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Working while sleep: ${_formatTime(sleepPeriod.startTime)} - ${_formatTime(sleepPeriod.endTime)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (sleepPeriod.note != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  sleepPeriod.note!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.7),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(
                              alpha: isDark ? 0.3 : 0.2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatDuration(sleepPeriod.duration),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Duration _calculateTotalDuration(List<TimelineBlock> blocks) {
    return blocks.fold(Duration.zero, (total, block) => total + block.duration);
  }

  void _showBlockDetails(TimelineBlock block) {
    DateTime dialogStartTime = block.startTime;
    DateTime dialogEndTime = block.endTime;

    showDialog(
      context: context,
      builder: (context) => ActivityDetailDialog(
        startTime: dialogStartTime,
        endTime: dialogEndTime,
        activities: block.activities,
        blockType: block.blockType,
        note: block.note,
        relatedSleepPeriods: block.relatedSleepPeriods,
      ),
    );
  }

  String _formatTime(DateTime time) {
    // Always use local time in 24-hour format
    final localTime = time.toLocal();
    final hours = localTime.hour.toString().padLeft(2, '0');
    final minutes = localTime.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 64,
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No activity tracked for this day',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatDurationDetailed(Duration duration) {
    if (duration.inSeconds <= 0) return '0s';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];

    if (hours > 0) {
      parts.add('${hours}h');
    }
    if (minutes > 0 || hours > 0) {
      parts.add('${minutes}m');
    }
    if (seconds > 0 || (hours == 0 && minutes == 0)) {
      parts.add('${seconds}s');
    }

    return parts.join(' ');
  }

  List<Map<String, dynamic>> _groupAppActivities(List<AppActivity> activities) {
    // Use normalized key (trim+lowercase) to avoid duplicate groups for the
    // same app recorded with different casing or trailing whitespace.
    final Map<String, Map<String, dynamic>> appMap = {};
    // Maps normalized key -> first-seen original display name
    final Map<String, String> displayNames = {};

    for (var activity in activities) {
      final rawAppName = activity.appName.trim();
      final appKey = rawAppName.toLowerCase();
      final windowTitle = (activity.windowTitle ?? '').trim();

      // Use the model's validated duration getter — it prefers stored durationSeconds,
      // falls back to endTime-startTime, and returns Duration.zero for open/active
      // activities (instead of inflating with DateTime.now()).
      final duration = activity.duration.inSeconds;

      if (duration <= 0) continue;

      if (!appMap.containsKey(appKey)) {
        appMap[appKey] = {'total_duration': 0, 'windows': <String, int>{}};
        displayNames[appKey] = rawAppName; // preserve original for display
      }

      final appData = appMap[appKey]!;
      appData['total_duration'] = (appData['total_duration'] as int) + duration;

      final windows = appData['windows'] as Map<String, int>;
      windows[windowTitle] = (windows[windowTitle] ?? 0) + duration;
    }

    final groupedList = appMap.entries.map((entry) {
      final appKey = entry.key;
      final data = entry.value;
      final totalDuration = data['total_duration'] as int;
      final windowsMap = data['windows'] as Map<String, int>;

      final windowsList = windowsMap.entries.map((wEntry) {
        return {'title': wEntry.key, 'duration_seconds': wEntry.value};
      }).toList();

      windowsList.sort(
        (a, b) => (b['duration_seconds'] as int).compareTo(
          a['duration_seconds'] as int,
        ),
      );

      return {
        'app_name': displayNames[appKey] ?? appKey,
        'duration_seconds': totalDuration,
        'windows': windowsList,
      };
    }).toList();

    groupedList.sort(
      (a, b) => (b['duration_seconds'] as int).compareTo(
        a['duration_seconds'] as int,
      ),
    );

    return groupedList;
  }

  Widget _buildMixedActivitiesView() {
    if (_timelineData == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Flatten all activities from all work blocks
    final allActivities = <AppActivity>[];
    for (final block in _timelineData!.workBlocks) {
      if (block.blockType.startsWith('work')) {
        allActivities.addAll(block.activities);
      }
    }

    if (allActivities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.apps,
              size: 64,
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No app activities recorded for this day',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    final groupedActivities = _groupAppActivities(allActivities);

    int maxActivityDuration = 0;
    for (var act in groupedActivities) {
      final actDuration = act['duration_seconds'] as int;
      if (actDuration > maxActivityDuration) {
        maxActivityDuration = actDuration;
      }
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: groupedActivities.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final activity = groupedActivities[index];
          final appName = activity['app_name'] as String;
          final durationSeconds = activity['duration_seconds'] as int;
          final windows =
              activity['windows'] as List<Map<String, dynamic>>? ?? [];
          final percentage = maxActivityDuration > 0
              ? (durationSeconds / maxActivityDuration).clamp(0.0, 1.0)
              : 0.0;

          final tileColor = isDark ? const Color(0xFF2D2D2D) : Colors.white;
          final borderColor = isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05);

          return Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                backgroundColor: tileColor,
                collapsedBackgroundColor: tileColor,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                childrenPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: MacOSTheme.systemBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.apps,
                        color: MacOSTheme.systemBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        appName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MacOSTheme.systemBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _formatDurationDetailed(
                          Duration(seconds: durationSeconds),
                        ),
                        style: const TextStyle(
                          color: MacOSTheme.systemBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 12, left: 52),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage,
                          backgroundColor: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            MacOSTheme.systemBlue.withValues(alpha: 0.7),
                          ),
                          minHeight: 6,
                        ),
                      ),
                      if (windows.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${windows.length} window title${windows.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                children: [
                  if (windows.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF252525)
                            : Colors.grey.shade50,
                        border: Border(top: BorderSide(color: borderColor)),
                      ),
                      child: Column(
                        children: windows.asMap().entries.map((entry) {
                          final index = entry.key;
                          final window = entry.value;
                          final title =
                              window['title'] as String? ?? 'General Usage';
                          final winDuration = window['duration_seconds'] as int;

                          return Container(
                            decoration: BoxDecoration(
                              border: index != windows.length - 1
                                  ? Border(
                                      bottom: BorderSide(color: borderColor),
                                    )
                                  : null,
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 2,
                                    left: 52,
                                  ),
                                  child: Icon(
                                    Icons.window,
                                    size: 14,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'General Usage' : title,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(height: 1.4),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDurationDetailed(
                                          Duration(seconds: winDuration),
                                        ),
                                        style: TextStyle(
                                          color: theme
                                              .textTheme
                                              .bodySmall
                                              ?.color
                                              ?.withValues(alpha: 0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
