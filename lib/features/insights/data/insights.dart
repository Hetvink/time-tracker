import 'dart:math' as math;

import 'package:flutter/material.dart' show DateUtils, TimeOfDay;

/// Analytics models computed from raw Supabase tracking rows. Pure Dart so
/// they can be reused by the personal and the admin views.

/// Human label for a check-in / check-out source ("autoSystemStart" → …).
String prettySource(String? source) {
  if (source == null || source.isEmpty) return '—';
  const known = {
    'autoSystemStart': 'Auto · startup',
    'auto_system_start': 'Auto · startup',
    'autoSystemShutdown': 'Auto · shutdown',
    'auto_system_shutdown': 'Auto · shutdown',
    'manualUser': 'Manual',
    'manual_user': 'Manual',
    'manual': 'Manual',
    'systemRecovery': 'Recovered',
    'system_recovery': 'Recovered',
    'autoMidnightTransition': 'Midnight split',
    'auto_midnight_transition': 'Midnight split',
  };
  return known[source] ??
      source
          .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
          .replaceAll('_', ' ')
          .toLowerCase();
}

DateTime? _parse(Object? v) =>
    v == null ? null : DateTime.tryParse(v as String)?.toLocal();

class TimeSpan {
  final DateTime start;
  final DateTime end;
  const TimeSpan(this.start, this.end);

  Duration get duration =>
      end.isAfter(start) ? end.difference(start) : Duration.zero;
}

class BreakInfo {
  final DateTime start;
  final DateTime end;
  final bool open;
  final String? note;

  const BreakInfo(this.start, this.end, {this.open = false, this.note});

  Duration get duration => end.difference(start);
}

class SessionInfo {
  final String id;
  final DateTime start;
  final DateTime end;
  final bool isOpen;
  final String? checkInSource;
  final String? checkOutSource;
  final List<BreakInfo> breaks;
  final List<TimeSpan> sleep;
  final List<TimeSpan> workIntervals;

  const SessionInfo({
    required this.id,
    required this.start,
    required this.end,
    required this.isOpen,
    this.checkInSource,
    this.checkOutSource,
    required this.breaks,
    required this.sleep,
    required this.workIntervals,
  });

  Duration get span => end.difference(start);
  Duration get work =>
      workIntervals.fold(Duration.zero, (a, i) => a + i.duration);
  Duration get breakTime =>
      breaks.fold(Duration.zero, (a, b) => a + b.duration);
  Duration get sleepTime => sleep.fold(Duration.zero, (a, s) => a + s.duration);
  bool get onBreak => isOpen && breaks.any((b) => b.open);

  /// Parses an `attendance_sessions` row with nested `break_periods` and
  /// `work_during_sleep_periods`.
  static SessionInfo? fromRow(Map<String, dynamic> row, DateTime now) {
    final start = _parse(row['check_in_time_utc'] ?? row['check_in_time']);
    if (start == null) return null;
    final closed = row['is_closed'] == true;
    var end = _parse(row['check_out_time_utc'] ?? row['check_out_time']);
    if (!closed || end == null) {
      // Live session: count up to now, unless the tracker has gone quiet.
      final lastSeen = _parse(row['last_seen_time']);
      end = lastSeen != null && now.difference(lastSeen).inMinutes > 15
          ? lastSeen
          : now;
    }
    if (end.isBefore(start)) end = start;

    final breaks = <BreakInfo>[];
    for (final b in (row['break_periods'] as List?) ?? const []) {
      final m = (b as Map).cast<String, dynamic>();
      if (m['is_deleted'] == true) continue;
      final bs = _parse(m['break_start_time_utc'] ?? m['break_start_time']);
      if (bs == null) continue;
      final be = _parse(m['break_end_time_utc'] ?? m['break_end_time']);
      final open = be == null;
      final s = bs.isBefore(start) ? start : bs;
      var e = be ?? end;
      if (e.isAfter(end)) e = end;
      if (!e.isAfter(s)) continue;
      breaks.add(
        BreakInfo(s, e, open: open && !closed, note: m['note'] as String?),
      );
    }
    breaks.sort((a, b) => a.start.compareTo(b.start));

    final sleep = <TimeSpan>[];
    for (final p in (row['work_during_sleep_periods'] as List?) ?? const []) {
      final m = (p as Map).cast<String, dynamic>();
      if (m['is_deleted'] == true) continue;
      final ss = _parse(m['sleep_start_time_utc'] ?? m['sleep_start_time']);
      final we = _parse(m['wake_time_utc'] ?? m['wake_time']);
      if (ss == null || we == null || !we.isAfter(ss)) continue;
      sleep.add(TimeSpan(ss, we));
    }

    // Work = session span minus breaks
    var work = [TimeSpan(start, end)];
    for (final b in breaks) {
      final next = <TimeSpan>[];
      for (final w in work) {
        if (!b.end.isAfter(w.start) || !b.start.isBefore(w.end)) {
          next.add(w);
          continue;
        }
        if (b.start.isAfter(w.start)) next.add(TimeSpan(w.start, b.start));
        if (b.end.isBefore(w.end)) next.add(TimeSpan(b.end, w.end));
      }
      work = next;
    }

    return SessionInfo(
      id: row['id']?.toString() ?? '',
      start: start,
      end: end,
      isOpen: !closed,
      checkInSource: row['check_in_source'] as String?,
      checkOutSource: row['check_out_source'] as String?,
      breaks: breaks,
      sleep: sleep,
      workIntervals: work,
    );
  }
}

class AppUsage {
  final String name;
  final Duration total;
  final int switches;
  final Map<String, Duration> windows;

  const AppUsage(this.name, this.total, this.switches, this.windows);

  List<MapEntry<String, Duration>> get topWindows =>
      windows.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

class ActivityEntry {
  final String app;
  final String? title;
  final DateTime start;
  final DateTime end;

  const ActivityEntry(this.app, this.title, this.start, this.end);

  Duration get duration => end.difference(start);

  static ActivityEntry? fromRow(Map<String, dynamic> m) {
    final start = _parse(m['start_time_utc'] ?? m['start_time']);
    if (start == null) return null;
    final secs = (m['duration_seconds'] as num?)?.toInt() ?? 0;
    final end =
        _parse(m['end_time_utc'] ?? m['end_time']) ??
        start.add(Duration(seconds: secs));
    final title = (m['window_title'] as String?)?.trim();
    return ActivityEntry(
      (m['app_name'] as String?)?.trim().isNotEmpty == true
          ? (m['app_name'] as String).trim()
          : 'Unknown',
      title == null || title.isEmpty ? null : title,
      start,
      end.isBefore(start) ? start : end,
    );
  }
}

/// Everything the insight screens show for one user and one date range.
class Insights {
  final DateTime from; // inclusive, local midnight
  final DateTime to; // exclusive, local midnight
  final List<SessionInfo> sessions;
  final List<ActivityEntry> activities;
  final DateTime computedAt;

  late final Map<DateTime, Duration> daily = _daily();
  late final List<Duration> hourly = _hourly();
  late final List<Duration> weekday = _weekday();
  late final List<AppUsage> apps = _apps();

  Insights({
    required this.from,
    required this.to,
    required this.sessions,
    required this.activities,
    required this.computedAt,
  });

  // ---- merged work intervals, clipped to the range --------------------------

  late final List<TimeSpan> _work = _merge([
    for (final s in sessions)
      for (final w in s.workIntervals)
        if (w.end.isAfter(from) && w.start.isBefore(to))
          TimeSpan(
            w.start.isBefore(from) ? from : w.start,
            w.end.isAfter(to) ? to : w.end,
          ),
  ]);

  static List<TimeSpan> _merge(List<TimeSpan> list) {
    if (list.isEmpty) return const [];
    final sorted = [...list]..sort((a, b) => a.start.compareTo(b.start));
    final out = <TimeSpan>[sorted.first];
    for (final i in sorted.skip(1)) {
      final last = out.last;
      if (!i.start.isAfter(last.end)) {
        if (i.end.isAfter(last.end)) {
          out[out.length - 1] = TimeSpan(last.start, i.end);
        }
      } else {
        out.add(i);
      }
    }
    return out;
  }

  Duration get total => _work.fold(Duration.zero, (a, i) => a + i.duration);

  Duration get breakTotal => sessions.fold(
    Duration.zero,
    (a, s) =>
        a +
        s.breaks
            .where((b) => b.end.isAfter(from) && b.start.isBefore(to))
            .fold(Duration.zero, (x, b) => x + b.duration),
  );

  Duration get sleepTotal =>
      sessions.fold(Duration.zero, (a, s) => a + s.sleepTime);

  List<SessionInfo> get sessionsInRange =>
      sessions
          .where((s) => s.end.isAfter(from) && s.start.isBefore(to))
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start));

  int get sessionCount => sessionsInRange.length;

  SessionInfo? get liveSession => sessions
      .where((s) => s.isOpen)
      .fold<SessionInfo?>(
        null,
        (best, s) => best == null || s.start.isAfter(best.start) ? s : best,
      );

  bool get isWorkingNow => liveSession != null;

  int get dayCount => DateUtils.dateOnly(to).difference(from).inDays;

  int get activeDays => daily.values.where((d) => d.inMinutes >= 1).length;

  Duration get averagePerActiveDay =>
      activeDays == 0 ? Duration.zero : total ~/ activeDays;

  Duration get longestSession =>
      sessionsInRange.fold(Duration.zero, (a, s) => s.work > a ? s.work : a);

  MapEntry<DateTime, Duration>? get bestDay {
    MapEntry<DateTime, Duration>? best;
    for (final e in daily.entries) {
      if (best == null || e.value > best.value) best = e;
    }
    return best == null || best.value == Duration.zero ? null : best;
  }

  /// Consecutive days with tracked time, ending today or yesterday.
  int get streak {
    final today = DateUtils.dateOnly(computedAt);
    var day = (daily[today] ?? Duration.zero) > Duration.zero
        ? today
        : today.subtract(const Duration(days: 1));
    var n = 0;
    while ((daily[day] ?? Duration.zero) > Duration.zero) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  /// Average first check-in / last check-out time of day over active days.
  (TimeOfDay?, TimeOfDay?) get averageStartEnd {
    final firsts = <DateTime, DateTime>{};
    final lasts = <DateTime, DateTime>{};
    for (final w in _work) {
      final d = DateUtils.dateOnly(w.start);
      if (!firsts.containsKey(d) || w.start.isBefore(firsts[d]!)) {
        firsts[d] = w.start;
      }
      final de = DateUtils.dateOnly(w.end);
      if (!lasts.containsKey(de) || w.end.isAfter(lasts[de]!)) {
        lasts[de] = w.end;
      }
    }
    TimeOfDay? avg(Iterable<DateTime> times) {
      if (times.isEmpty) return null;
      final mins =
          times.map((t) => t.hour * 60 + t.minute).reduce((a, b) => a + b) ~/
          times.length;
      return TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
    }

    return (avg(firsts.values), avg(lasts.values));
  }

  Duration get appTotal => apps.fold(Duration.zero, (a, u) => a + u.total);

  // ---- breakdowns ------------------------------------------------------------

  Map<DateTime, Duration> _daily() {
    final map = <DateTime, Duration>{};
    for (
      var d = from;
      d.isBefore(to);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      map[d] = Duration.zero;
    }
    for (final w in _work) {
      var s = w.start;
      while (s.isBefore(w.end)) {
        final day = DateUtils.dateOnly(s);
        final next = DateTime(day.year, day.month, day.day + 1);
        final e = w.end.isBefore(next) ? w.end : next;
        map[day] = (map[day] ?? Duration.zero) + e.difference(s);
        s = e;
      }
    }
    return map;
  }

  List<Duration> _hourly() {
    final out = List.filled(24, Duration.zero);
    for (final w in _work) {
      var s = w.start;
      while (s.isBefore(w.end)) {
        final next = DateTime(s.year, s.month, s.day, s.hour + 1);
        final e = w.end.isBefore(next) ? w.end : next;
        out[s.hour] += e.difference(s);
        s = e;
      }
    }
    return out;
  }

  List<Duration> _weekday() {
    final out = List.filled(7, Duration.zero);
    daily.forEach((day, d) => out[day.weekday - 1] += d);
    return out;
  }

  List<AppUsage> _apps() {
    final totals = <String, Duration>{};
    final counts = <String, int>{};
    final windows = <String, Map<String, Duration>>{};
    for (final a in activities) {
      if (!a.end.isAfter(from) || !a.start.isBefore(to)) continue;
      totals[a.app] = (totals[a.app] ?? Duration.zero) + a.duration;
      counts[a.app] = (counts[a.app] ?? 0) + 1;
      final w = windows.putIfAbsent(a.app, () => {});
      final key = a.title ?? '(no window title)';
      w[key] = (w[key] ?? Duration.zero) + a.duration;
    }
    return [
      for (final e in totals.entries)
        AppUsage(
          e.key,
          e.value,
          counts[e.key] ?? 0,
          windows[e.key] ?? const {},
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Daily values as hours, oldest first (for sparklines).
  List<double> get dailyHours =>
      (daily.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => e.value.inMinutes / 60)
          .toList();

  double get focusScore {
    // Share of tracked time spent in the top 3 apps: a rough focus signal.
    final total = appTotal.inSeconds;
    if (total == 0) return 0;
    final top = apps.take(3).fold(0, (a, u) => a + u.total.inSeconds);
    return math.min(1, top / total);
  }
}
