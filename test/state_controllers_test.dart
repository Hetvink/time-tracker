import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_trak/core/state/submit_controller.dart';
import 'package:time_trak/features/insights/data/insights.dart';
import 'package:time_trak/features/insights/data/insights_repository.dart';
import 'package:time_trak/features/insights/presentation/insights_controllers.dart';
import 'package:time_trak/routes/navigation_provider.dart';

/// Answers each request only when the test completes it.
class _ManualRepo implements InsightsRepository {
  final requests = <(DateTime, Completer<Insights>)>[];

  @override
  Future<Insights> day(String userId, DateTime day, {bool force = false}) {
    final c = Completer<Insights>();
    requests.add((day, c));
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Insights _empty(DateTime day) => Insights(
  from: day,
  to: day.add(const Duration(days: 1)),
  sessions: const [],
  activities: const [],
  computedAt: DateTime.now(),
);

void main() {
  group('SubmitController', () {
    test('tracks busy, error and info', () async {
      final c = SubmitController();
      final states = <bool>[];
      c.addListener(() => states.add(c.isBusy));

      expect(await c.run(() async => null, successInfo: 'Saved'), isTrue);
      expect(c.info, 'Saved');
      expect(c.error, isNull);

      expect(await c.run(() async => 'Nope'), isFalse);
      expect(c.error, 'Nope');
      expect(c.info, isNull);

      expect(await c.run(() async => throw Exception('Boom')), isFalse);
      expect(c.error, 'Boom');
      expect(states, [true, false, true, false, true, false]);
      c.dispose();
    });

    test('ignores a second run while busy', () async {
      final c = SubmitController();
      final gate = Completer<String?>();
      final first = c.run(() => gate.future);
      expect(await c.run(() async => null), isFalse);
      gate.complete(null);
      expect(await first, isTrue);
      c.dispose();
    });
  });

  group('DayInsightsController', () {
    test('loads today, shifts days and exposes data', () async {
      final repo = _ManualRepo();
      final c = DayInsightsController(repository: repo, userId: 'u');
      final today = DateUtils.dateOnly(DateTime.now());

      expect(c.isToday, isTrue);
      expect(c.isInitialLoading, isTrue);
      repo.requests.single.$2.complete(_empty(today));
      await pumpEventQueue();
      expect(c.data, isNotNull);
      expect(c.isLoading, isFalse);

      c.shift(-1);
      expect(c.period, today.subtract(const Duration(days: 1)));
      expect(c.data, isNull, reason: 'a new period must not show old numbers');
      expect(repo.requests.last.$1, c.period);
      c.dispose();
    });

    test('a slow, outdated response never overwrites a newer one', () async {
      final repo = _ManualRepo();
      final c = DayInsightsController(repository: repo, userId: 'u');
      final yesterday = DateUtils.dateOnly(
        DateTime.now(),
      ).subtract(const Duration(days: 1));
      c.setDay(yesterday);

      // Newer request answers first, then the stale one.
      repo.requests[1].$2.complete(_empty(yesterday));
      await pumpEventQueue();
      repo.requests[0].$2.complete(_empty(DateUtils.dateOnly(DateTime.now())));
      await pumpEventQueue();

      expect(c.data!.from, yesterday);
      c.dispose();
    });
  });

  test('NavigationProvider returns to the dashboard for a new user', () {
    final nav = NavigationProvider()..onUserChanged('a');
    nav.selectIndex(NavIndex.team);
    nav.onUserChanged('a');
    expect(
      nav.selectedIndex,
      NavIndex.team,
      reason: 'same user keeps the page',
    );
    nav.onUserChanged('b');
    expect(nav.selectedIndex, NavIndex.dashboard);
  });
}
