enum AttendanceStatus { checkedOut, checkedIn, onBreak }

enum EventSource {
  autoSystemStart,
  autoSystemShutdown,
  manualUser,
  systemRecovery,
  autoMidnightTransition,
}

class AttendanceState {
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final DateTime? breakStartTime;
  final List<BreakPeriod> breaks;
  final EventSource lastEventSource;
  final dynamic
  currentSessionId; // dynamic to support int (SQLite) or String (Supabase UUID)

  AttendanceState({
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.breakStartTime,
    this.breaks = const [],
    required this.lastEventSource,
    this.currentSessionId,
  });

  Duration get totalWorkTime {
    if (checkInTime == null) return Duration.zero;

    // Calculate work time by tracking work segments, not by subtracting breaks
    // This prevents negative work time when breaks exceed work duration

    final nowUtc = DateTime.now().toUtc();
    final endTimeUtc = (checkOutTime?.toUtc()) ?? nowUtc;

    // Build a timeline of work/break periods
    final List<({DateTime start, DateTime end, bool isBreak})> timeline = [];

    // Add all completed breaks
    for (var breakPeriod in breaks) {
      if (breakPeriod.endTime != null) {
        timeline.add((
          start: breakPeriod.startTime.toUtc(),
          end: breakPeriod.endTime!.toUtc(),
          isBreak: true,
        ));
      }
    }

    // Add current active break if any
    if (breakStartTime != null) {
      timeline.add((
        start: breakStartTime!.toUtc(),
        end: nowUtc,
        isBreak: true,
      ));
    }

    // Sort timeline by start time
    timeline.sort((a, b) => a.start.compareTo(b.start));

    // Calculate work time as segments between check-in and breaks
    Duration workTime = Duration.zero;
    DateTime currentPosition = checkInTime!.toUtc();

    for (var period in timeline) {
      // Add work time from current position to break start
      if (period.start.isAfter(currentPosition)) {
        workTime += period.start.difference(currentPosition);
      }
      // Move position to break end
      if (period.end.isAfter(currentPosition)) {
        currentPosition = period.end;
      }
    }

    // Add remaining work time from last break end to current time/checkout
    if (endTimeUtc.isAfter(currentPosition)) {
      workTime += endTimeUtc.difference(currentPosition);
    }

    return workTime;
  }

  Duration get currentBreakDuration {
    return breakStartTime != null
        ? DateTime.now().toUtc().difference(breakStartTime!.toUtc())
        : Duration.zero;
  }

  Duration get totalBreakDuration {
    final closedBreaks = breaks.fold<Duration>(
      Duration.zero,
      (sum, breakPeriod) => sum + breakPeriod.duration,
    );
    return closedBreaks + currentBreakDuration;
  }

  bool get canCheckIn => status == AttendanceStatus.checkedOut;
  bool get canCheckOut => status == AttendanceStatus.checkedIn;
  bool get canBreakIn => status == AttendanceStatus.checkedIn;
  bool get canBreakOut => status == AttendanceStatus.onBreak;

  // Status change validation
  bool canTransitionTo(AttendanceStatus targetStatus) {
    if (status == targetStatus) return false; // No self-transitions

    switch (targetStatus) {
      case AttendanceStatus.checkedIn:
        // Can transition to checkedIn from checkedOut or onBreak
        return status == AttendanceStatus.checkedOut ||
            status == AttendanceStatus.onBreak;
      case AttendanceStatus.onBreak:
        // Can only start break when checked in
        return status == AttendanceStatus.checkedIn;
      case AttendanceStatus.checkedOut:
        // Can check out from checkedIn or onBreak
        return status == AttendanceStatus.checkedIn ||
            status == AttendanceStatus.onBreak;
    }
  }

  String? getTransitionError(AttendanceStatus targetStatus) {
    if (!canTransitionTo(targetStatus)) {
      if (status == targetStatus) {
        return 'Already ${_statusToString(targetStatus)}';
      }

      return 'Cannot transition from ${_statusToString(status)} to ${_statusToString(targetStatus)}';
    }
    return null;
  }

  String _statusToString(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.checkedOut:
        return 'Checked Out';
      case AttendanceStatus.checkedIn:
        return 'Working';
      case AttendanceStatus.onBreak:
        return 'On Break';
    }
  }

  AttendanceState copyWith({
    AttendanceStatus? status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    DateTime? breakStartTime,
    List<BreakPeriod>? breaks,
    EventSource? lastEventSource,
    dynamic currentSessionId,
    bool clearBreakStartTime = false,
    bool clearCheckOutTime = false,
    bool clearCurrentSessionId = false,
    bool clearCheckInTime = false,
  }) {
    return AttendanceState(
      status: status ?? this.status,
      checkInTime: clearCheckInTime ? null : (checkInTime ?? this.checkInTime),
      checkOutTime: clearCheckOutTime
          ? null
          : (checkOutTime ?? this.checkOutTime),
      breakStartTime: clearBreakStartTime
          ? null
          : (breakStartTime ?? this.breakStartTime),
      breaks: breaks ?? this.breaks,
      lastEventSource: lastEventSource ?? this.lastEventSource,
      currentSessionId: clearCurrentSessionId
          ? null
          : (currentSessionId ?? this.currentSessionId),
    );
  }
}

class BreakPeriod {
  final DateTime startTime;
  final DateTime? endTime;
  final String? note;

  BreakPeriod({required this.startTime, this.endTime, this.note});

  Duration get duration {
    if (endTime == null) return Duration.zero;
    return endTime!.difference(startTime);
  }

  BreakPeriod copyWith({DateTime? startTime, DateTime? endTime, String? note}) {
    return BreakPeriod(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      note: note ?? this.note,
    );
  }
}
