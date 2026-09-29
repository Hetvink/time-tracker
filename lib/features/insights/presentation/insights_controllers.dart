import 'package:flutter/material.dart';

import '../data/insights.dart';
import '../data/insights_repository.dart';

/// Loads [Insights] for one user and a selectable period [P], exposing
/// data / loading / error as listenable state.
abstract class InsightsController<P> extends ChangeNotifier {
  final InsightsRepository repository;
  final String userId;

  InsightsController({
    required this.repository,
    required this.userId,
    required P period,
  }) : _period = period {
    _load();
  }

  P _period;
  Insights? _data;
  Object? _error;
  bool _loading = false;
  int _request = 0;
  bool _disposed = false;

  P get period => _period;
  Insights? get data => _data;
  Object? get error => _error;
  bool get isLoading => _loading;

  /// First load (nothing to show yet).
  bool get isInitialLoading => _loading && _data == null;

  Future<Insights> fetch(P period, {required bool force});

  void setPeriod(P period) {
    if (period == _period) return;
    _period = period;
    _data = null; // different period: show skeleton, not stale numbers
    _load();
  }

  Future<void> refresh() => _load(force: true);

  Future<void> _load({bool force = false}) async {
    final request = ++_request;
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await fetch(_period, force: force);
      if (request != _request) return; // a newer request superseded this one
      _data = result;
    } catch (e) {
      if (request != _request) return;
      _error = e;
    } finally {
      if (request == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Last N days including today.
class RangeInsightsController extends InsightsController<int> {
  RangeInsightsController({
    required super.repository,
    required super.userId,
    super.period = 14,
  });

  @override
  Future<Insights> fetch(int days, {required bool force}) =>
      repository.recent(userId, days, force: force);
}

/// A single calendar day.
class DayInsightsController extends InsightsController<DateTime> {
  DayInsightsController({
    required super.repository,
    required super.userId,
    DateTime? day,
  }) : super(period: DateUtils.dateOnly(day ?? DateTime.now()));

  bool get isToday => period == DateUtils.dateOnly(DateTime.now());

  void setDay(DateTime day) => setPeriod(DateUtils.dateOnly(day));
  void shift(int days) =>
      setDay(DateTime(period.year, period.month, period.day + days));
  void today() => setDay(DateTime.now());

  @override
  Future<Insights> fetch(DateTime day, {required bool force}) =>
      repository.day(userId, day, force: force);
}

/// A calendar month (the day of the DateTime is ignored).
class MonthInsightsController extends InsightsController<DateTime> {
  MonthInsightsController({required super.repository, required super.userId})
    : super(period: DateTime(DateTime.now().year, DateTime.now().month));

  bool get isCurrent {
    final now = DateTime.now();
    return period.year == now.year && period.month == now.month;
  }

  void setMonth(DateTime month) => setPeriod(DateTime(month.year, month.month));
  void shift(int months) =>
      setMonth(DateTime(period.year, period.month + months));
  void current() => setMonth(DateTime.now());

  @override
  Future<Insights> fetch(DateTime month, {required bool force}) =>
      repository.month(userId, month.year, month.month, force: force);
}

/// App usage over the last N days, with a search filter.
class AppsInsightsController extends InsightsController<int> {
  AppsInsightsController({
    required super.repository,
    required super.userId,
    super.period = 7,
  });

  String _query = '';
  String get query => _query;

  void setQuery(String value) {
    _query = value;
    _notify();
  }

  @override
  Future<Insights> fetch(int days, {required bool force}) =>
      repository.recent(userId, days, force: force);
}
