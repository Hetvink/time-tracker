import 'timeline_segment.dart';

/// Complete timeline data for a single day
/// Shows work periods, breaks, and not-working periods throughout the day
class DayTimelineData {
  final DateTime date;
  final List<TimelineBlock> workBlocks;
  final List<TimelineBlock> breakBlocks;
  final List<TimelineBlock> notWorkingBlocks;

  DayTimelineData({
    required this.date,
    required this.workBlocks,
    required this.breakBlocks,
    required this.notWorkingBlocks,
  });

  /// Get all blocks sorted by start time
  List<TimelineBlock> get allBlocks {
    final all = <TimelineBlock>[
      ...workBlocks,
      ...breakBlocks,
      ...notWorkingBlocks,
    ];
    all.sort((a, b) => a.startTime.compareTo(b.startTime));
    return all;
  }

  /// Total work time for the day
  Duration get totalWorkTime {
    return workBlocks.fold(
      Duration.zero,
      (sum, block) => sum + Duration(seconds: block.durationSeconds),
    );
  }

  /// Total break time for the day
  Duration get totalBreakTime {
    return breakBlocks.fold(
      Duration.zero,
      (sum, block) => sum + Duration(seconds: block.durationSeconds),
    );
  }

  /// Total not-working time for the day
  Duration get totalNotWorkingTime {
    return notWorkingBlocks.fold(
      Duration.zero,
      (sum, block) => sum + Duration(seconds: block.durationSeconds),
    );
  }

  /// Check if there's any activity on this day
  bool get hasActivity => workBlocks.isNotEmpty || breakBlocks.isNotEmpty;

  /// Get the first activity time of the day
  DateTime? get firstActivityTime {
    if (!hasActivity) return null;
    final blocks = [...workBlocks, ...breakBlocks];
    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks.first.startTime;
  }

  /// Get the last activity time of the day
  DateTime? get lastActivityTime {
    if (!hasActivity) return null;
    final blocks = [...workBlocks, ...breakBlocks];
    blocks.sort((a, b) => b.endTime.compareTo(a.endTime));
    return blocks.first.endTime;
  }

  /// Generate not-working blocks to fill gaps in the timeline
  static List<TimelineBlock> generateNotWorkingBlocks({
    required DateTime dayStart,
    required DateTime dayEnd,
    required List<TimelineBlock> workBlocks,
    required List<TimelineBlock> breakBlocks,
  }) {
    final notWorkingBlocks = <TimelineBlock>[];

    // Combine and sort all active blocks
    final activeBlocks = <TimelineBlock>[...workBlocks, ...breakBlocks];
    if (activeBlocks.isEmpty) {
      // Entire day is not-working
      notWorkingBlocks.add(
        TimelineBlock(
          startTime: dayStart,
          endTime: dayEnd,
          blockType: 'not_working',
        ),
      );
      return notWorkingBlocks;
    }

    activeBlocks.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Gap before first activity
    if (activeBlocks.first.startTime.isAfter(dayStart)) {
      notWorkingBlocks.add(
        TimelineBlock(
          startTime: dayStart,
          endTime: activeBlocks.first.startTime,
          blockType: 'not_working',
        ),
      );
    }

    // Gaps between activities
    for (int i = 0; i < activeBlocks.length - 1; i++) {
      final currentEnd = activeBlocks[i].endTime;
      final nextStart = activeBlocks[i + 1].startTime;

      if (nextStart.isAfter(currentEnd)) {
        notWorkingBlocks.add(
          TimelineBlock(
            startTime: currentEnd,
            endTime: nextStart,
            blockType: 'not_working',
          ),
        );
      }
    }

    // Gap after last activity
    if (activeBlocks.last.endTime.isBefore(dayEnd)) {
      notWorkingBlocks.add(
        TimelineBlock(
          startTime: activeBlocks.last.endTime,
          endTime: dayEnd,
          blockType: 'not_working',
        ),
      );
    }

    return notWorkingBlocks;
  }
}
