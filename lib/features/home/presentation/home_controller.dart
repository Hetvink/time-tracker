import 'dart:async';

import 'package:flutter/material.dart';

import '../../company/data/models/company.dart';
import '../../company/data/models/team_member.dart';
import '../../company/data/repository/company_repository.dart';
import '../../insights/data/insights.dart';
import '../../insights/data/insights_repository.dart';

/// State for the dashboard: the user's recent insights plus, for admins,
/// a team snapshot and platform stats. Reloads quietly every 2 minutes.
class HomeController extends ChangeNotifier {
  final InsightsRepository insightsRepository;
  final CompanyRepository companyRepository;
  final String userId;
  final String? companyId; // set for company admins
  final bool platformAdmin;

  HomeController({
    required this.insightsRepository,
    required this.companyRepository,
    required this.userId,
    this.companyId,
    this.platformAdmin = false,
  }) {
    refresh(force: false);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => refresh());
  }

  Timer? _timer;
  bool _disposed = false;

  Insights? _insights;
  Object? _error;
  bool _loading = false;
  List<TeamMember>? _team;
  PlatformStats? _platform;

  Insights? get insights => _insights;
  Object? get error => _error;
  bool get isLoading => _loading;
  List<TeamMember>? get team => _team;
  PlatformStats? get platformStats => _platform;

  /// Covers this month and the previous full week (for week-over-week).
  static (DateTime, DateTime) get range {
    final today = DateUtils.dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final prevWeek = weekStart.subtract(const Duration(days: 7));
    final monthStart = DateTime(today.year, today.month);
    return (
      prevWeek.isBefore(monthStart) ? prevWeek : monthStart,
      today.add(const Duration(days: 1)),
    );
  }

  Future<void> refresh({bool force = true}) async {
    _loading = true;
    _notify();
    final (from, to) = range;
    await Future.wait([
      insightsRepository
          .load(userId: userId, from: from, to: to, force: force)
          .then((v) {
            _insights = v;
            _error = null;
          })
          .catchError((Object e) {
            // Keep showing the last good data on a failed background refresh.
            _error = _insights == null ? e : null;
          }),
      if (companyId != null)
        companyRepository
            .getTeamMembers(companyId: companyId)
            .then((v) => _team = v)
            .catchError((Object e) {
              debugPrint('[Home] team snapshot failed: ${friendlyError(e)}');
              return _team ?? const <TeamMember>[];
            }),
      if (platformAdmin)
        companyRepository
            .getPlatformStats()
            .then((v) => _platform = v)
            .catchError((Object e) {
              debugPrint('[Home] platform stats failed: ${friendlyError(e)}');
              return _platform ?? PlatformStats.fromJson(const {});
            }),
    ]);
    _loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
