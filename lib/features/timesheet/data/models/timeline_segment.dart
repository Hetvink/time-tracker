import '../../../tracking/data/models/work_session.dart';
import '../../../tracking/data/models/app_activity.dart';
import '../../../tracking/data/models/attendance_state.dart';

/// SIMPLIFIED: Timeline rendering - UI display only
/// - Shows blocks for work sessions, breaks, and work-during-sleep periods
/// - Work blocks = app usage during check-in periods
/// - Break blocks = official breaks from timesheet
/// - Work-during-sleep blocks = work performed during system sleep with notes
/// - Timesheet is the source of truth for all time tracking

/// Constants for timeline rendering (simplified)
class TimelineConstants {
  // Core dimensions - hour-based rendering (now dynamic with zoom)
  static const double defaultHourHeight = 60.0; // Default height for 1 hour
  static const double minHourHeight = 30.0; // Minimum zoom out (0.5x)
  static const double maxHourHeight = 180.0; // Maximum zoom in (3.0x)
  static const double minuteHeight = 1.0; // Each minute = 1px

  // Zoom level thresholds for showing minute markers
  static const double show15MinMarkersZoom =
      1.5; // Show 15-min markers at 1.5x+
  static const double show5MinMarkersZoom = 2.0; // Show 5-min markers at 2.0x+

  // Visual constraints
  static const double minVisibleHeight = 4.0; // Minimum px for visibility
  static const double minContentHeight = 20.0; // Minimum px to show text
  static const double minDetailHeight = 30.0; // Minimum px for detailed content
}

/// SIMPLIFIED: Renderable timeline block for UI display
/// - 'work' block = shows app usage during timesheet check-in period
/// - 'break' block = shows official break from timesheet
/// - 'work_during_sleep' block = shows work performed during system sleep with note
/// - 'not_working' block = shows periods when checked out or idle
/// - Work blocks contain activities from native tracking
/// - Break blocks come from attendance break records with optional notes
/// - Work-during-sleep blocks come from work confirmation after sleep with required notes
class TimelineBlock {
  final DateTime startTime;
  final DateTime endTime;
  final String
  blockType; // 'work', 'break', 'work_during_sleep', or 'not_working'
  final List<String> appNames; // Apps used (only for work blocks)
  final List<AppActivity> activities; // Detailed activities with window titles
  final String?
  note; // Note/description (for break blocks and work_during_sleep blocks)
  final List<TimelineBlock>
  relatedSleepPeriods; // Sleep periods occurring during this session

  TimelineBlock({
    required this.startTime,
    required this.endTime,
    required this.blockType,
    this.appNames = const [],
    this.activities = const [],
    this.note,
    this.relatedSleepPeriods = const [],
  });

  /// Get robust duration handling inverted/cross-day times
  Duration get duration {
    final diff = endTime.difference(startTime);
    if (!diff.isNegative) return diff;

    // Handle inverted/cross-day times (Start > End)
    // Assume it wraps around midnight
    final crossDay = endTime.add(const Duration(days: 1)).difference(startTime);
    if (!crossDay.isNegative && crossDay.inHours < 24) {
      return crossDay;
    }
    return Duration.zero;
  }

  /// Calculate height in pixels based on duration (simplified)
  double get height {
    return duration.inMinutes * TimelineConstants.minuteHeight;
  }

  /// Calculate Y position from midnight (simplified)
  double get topPosition {
    final minutesFromMidnight = startTime.hour * 60 + startTime.minute;
    return minutesFromMidnight * TimelineConstants.minuteHeight;
  }

  /// Get duration in minutes
  int get durationMinutes {
    return duration.inMinutes;
  }

  /// Get duration in seconds
  int get durationSeconds {
    return duration.inSeconds;
  }

  /// Generate timeline block from a work session (simplified)
  static List<TimelineBlock> fromWorkSession(WorkSession session) {
    // Get all activities in this session
    final allActivities = <AppActivity>[];
    for (var segment in session.segments) {
      allActivities.addAll(segment.activities);
    }

    // Get unique app names
    final allApps = allActivities.map((a) => a.appName).toSet().toList();

    // Create ONE block using timesheet session times
    return [
      TimelineBlock(
        startTime: session.startTime,
        endTime: session.endTime,
        blockType: 'work',
        appNames: allApps,
        activities: allActivities,
      ),
    ];
  }

  /// Generate timeline block from a break period (simplified)
  static List<TimelineBlock> fromBreakPeriod(BreakPeriod breakPeriod) {
    final endTime = breakPeriod.endTime ?? DateTime.now();

    return [
      TimelineBlock(
        startTime: breakPeriod.startTime,
        endTime: endTime,
        blockType: 'break',
        appNames: [],
        note: breakPeriod.note,
      ),
    ];
  }

  /// Remove overlapping blocks with priority and splitting logic
  /// - High priority blocks (Breaks, Work During Sleep) "cut" holes in lower priority blocks (Work)
  /// - This ensures small high-priority blocks are visible even if covered by a large work block
  static List<TimelineBlock> removeOverlaps(List<TimelineBlock> blocks) {
    if (blocks.isEmpty) return [];

    // 1. Sort by Priority (High to Low) so high priority blocks are processed first
    // Break(0) > WorkDuringSleep(1) > Work(2)
    int getPriority(String blockType) {
      switch (blockType) {
        case 'break':
          return 0;
        case 'work_during_sleep':
          return 1;
        case 'work':
          return 2;
        default:
          return 3;
      }
    }

    // Sort inputs by priority (Lowest number = Highest priority)
    final sortedInputs = List<TimelineBlock>.from(blocks)
      ..sort(
        (a, b) => getPriority(a.blockType).compareTo(getPriority(b.blockType)),
      );

    final List<TimelineBlock> accepted = [];

    for (var candidate in sortedInputs) {
      // Start with the full candidate block as a single piece
      List<TimelineBlock> pieces = [candidate];

      // Check against all already accepted blocks (which have higher or equal priority)
      for (var existing in accepted) {
        final List<TimelineBlock> nextPieces = [];
        for (var piece in pieces) {
          // If no overlap, keep piece as is
          if (piece.endTime.isBefore(existing.startTime) ||
              piece.endTime.isAtSameMomentAs(existing.startTime) ||
              piece.startTime.isAfter(existing.endTime) ||
              piece.startTime.isAtSameMomentAs(existing.endTime)) {
            nextPieces.add(piece);
            continue;
          }

          // Overlap exists. Subtract 'existing' from 'piece'.

          // 1. Pre-overlap segment: piece.start -> existing.start
          if (piece.startTime.isBefore(existing.startTime)) {
            nextPieces.add(
              TimelineBlock(
                startTime: piece.startTime,
                endTime: existing.startTime,
                blockType: piece.blockType,
                appNames: piece.appNames,
                activities: piece.activities,
                note: piece.note,
                relatedSleepPeriods: piece.relatedSleepPeriods,
              ),
            );
          }

          // 2. Post-overlap segment: existing.end -> piece.end
          if (piece.endTime.isAfter(existing.endTime)) {
            nextPieces.add(
              TimelineBlock(
                startTime: existing.endTime,
                endTime: piece.endTime,
                blockType: piece.blockType,
                appNames: piece.appNames,
                activities: piece.activities,
                note: piece.note,
                relatedSleepPeriods: piece.relatedSleepPeriods,
              ),
            );
          }
        }
        pieces = nextPieces;
        if (pieces.isEmpty) break; // Entire candidate was consumed
      }
      accepted.addAll(pieces);
    }

    // Final sort by start time for proper timeline ordering
    accepted.sort((a, b) => a.startTime.compareTo(b.startTime));
    return accepted;
  }

  @override
  String toString() {
    return 'TimelineBlock($blockType: ${_formatTime(startTime)} - ${_formatTime(endTime)})';
  }

  String _formatTime(DateTime time) {
    // 24-hour format for debug output
    final hours = time.toLocal().hour.toString().padLeft(2, '0');
    final minutes = time.toLocal().minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}
