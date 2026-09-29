import 'package:flutter/material.dart' show DateUtils;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'insights.dart';

/// Loads [Insights] for any user the signed-in account may see (itself, a
/// company member for company admins, anyone for platform admins — RLS
/// decides). Results are cached briefly so switching tabs is instant.
class InsightsRepository {
  final SupabaseClient _db;
  InsightsRepository(this._db);

  static const _ttl = Duration(seconds: 45);
  static const _page = 1000;
  static const _maxRows = 25000;

  final _cache = <String, (DateTime, Future<Insights>)>{};

  /// [from] and [to] are local dates; [to] is exclusive.
  Future<Insights> load({
    required String userId,
    required DateTime from,
    required DateTime to,
    bool activities = true,
    bool force = false,
  }) {
    final f = DateUtils.dateOnly(from);
    final t = DateUtils.dateOnly(to);
    final key = '$userId|$f|$t|$activities';
    final hit = _cache[key];
    if (!force && hit != null && DateTime.now().difference(hit.$1) < _ttl) {
      return hit.$2;
    }
    final future = _fetch(userId, f, t, activities);
    _cache[key] = (DateTime.now(), future);
    // Don't keep failures around.
    future.then<void>((_) {}, onError: (Object _) => _cache.remove(key));
    return future;
  }

  Future<Insights> day(String userId, DateTime day, {bool force = false}) =>
      load(
        userId: userId,
        from: day,
        to: DateTime(day.year, day.month, day.day + 1),
        force: force,
      );

  Future<Insights> month(
    String userId,
    int year,
    int month, {
    bool force = false,
  }) => load(
    userId: userId,
    from: DateTime(year, month),
    to: DateTime(year, month + 1),
    force: force,
  );

  /// The last [days] days including today.
  Future<Insights> recent(String userId, int days, {bool force = false}) {
    final today = DateUtils.dateOnly(DateTime.now());
    return load(
      userId: userId,
      from: today.subtract(Duration(days: days - 1)),
      to: today.add(const Duration(days: 1)),
      force: force,
    );
  }

  void invalidate() => _cache.clear();

  Future<Insights> _fetch(
    String userId,
    DateTime from,
    DateTime to,
    bool withActivities,
  ) async {
    // Sessions that started up to a day earlier may run into the range.
    final queryFrom = from
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final queryTo = to.toUtc().toIso8601String();

    final sessionsFuture = _all(
      (a, b) => _db
          .from('attendance_sessions')
          .select('*, break_periods(*), work_during_sleep_periods(*)')
          .eq('user_id', userId)
          .eq('is_deleted', false)
          .gte('check_in_time_utc', queryFrom)
          .lt('check_in_time_utc', queryTo)
          .order('check_in_time_utc')
          .range(a, b),
    );
    final activitiesFuture = withActivities
        ? _all(
            (a, b) => _db
                .from('app_activities')
                .select(
                  'app_name, window_title, start_time_utc, end_time_utc, duration_seconds',
                )
                .eq('user_id', userId)
                .eq('is_deleted', false)
                .gte('start_time_utc', from.toUtc().toIso8601String())
                .lt('start_time_utc', queryTo)
                .order('start_time_utc')
                .range(a, b),
          )
        : Future.value(const <Map<String, dynamic>>[]);

    final rows = await Future.wait([sessionsFuture, activitiesFuture]);
    final now = DateTime.now();
    return Insights(
      from: from,
      to: to,
      sessions: [for (final r in rows[0]) ?SessionInfo.fromRow(r, now)],
      activities: [for (final r in rows[1]) ?ActivityEntry.fromRow(r)],
      computedAt: now,
    );
  }

  /// Pages through PostgREST's row limit.
  Future<List<Map<String, dynamic>>> _all(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(
      int from,
      int to,
    )
    query,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (var offset = 0; offset < _maxRows; offset += _page) {
      final batch = await query(offset, offset + _page - 1);
      out.addAll(batch);
      if (batch.length < _page) break;
    }
    return out;
  }
}
