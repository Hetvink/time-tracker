import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../company/data/models/company.dart';
import '../../company/data/repository/company_repository.dart';

/// Platform-wide stats and the company list, for platform admins.
/// App-scoped: it also feeds the "pending requests" navigation badge, and
/// refreshes itself every 2 minutes.
class PlatformAdminController extends ChangeNotifier {
  final CompanyRepository repository;

  PlatformAdminController(this.repository) {
    load();
    _timer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => load(silent: true),
    );
  }

  Timer? _timer;
  bool _disposed = false;

  PlatformStats? _stats;
  List<CompanyOverview> _companies = const [];
  bool _loading = false;
  String? _error;

  PlatformStats? get stats => _stats;
  List<CompanyOverview> get companies => _companies;
  bool get isLoading => _loading;
  String? get error => _error;

  int get pendingCount => _stats?.companiesPending ?? 0;

  /// Pending registrations, oldest first.
  List<CompanyOverview> get pending =>
      _companies
          .where((c) => c.company.status == CompanyStatus.pending)
          .toList()
        ..sort(
          (a, b) => (a.company.createdAt ?? DateTime(0)).compareTo(
            b.company.createdAt ?? DateTime(0),
          ),
        );

  Future<void> load({bool silent = false}) async {
    _loading = true;
    if (!silent) _error = null;
    _notify();
    try {
      final results = await Future.wait([
        repository.getPlatformStats(),
        repository.getCompaniesOverview(),
      ]);
      _stats = results[0] as PlatformStats;
      _companies = results[1] as List<CompanyOverview>;
      _error = null;
    } catch (e) {
      if (!silent || _stats == null) _error = friendlyError(e);
    }
    _loading = false;
    _notify();
  }

  /// Runs a mutating call and reloads. Returns an error message or null.
  Future<String?> _mutate(Future<void> Function() action) async {
    try {
      await action();
      await load(silent: true);
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  Future<String?> approve(CompanyOverview c) =>
      _mutate(() => repository.approveCompany(c.company.id));

  Future<String?> reject(CompanyOverview c, String? reason) =>
      _mutate(() => repository.rejectCompany(c.company.id, reason));

  Future<String?> setSuspended(CompanyOverview c, bool suspended) =>
      _mutate(() => repository.setCompanySuspended(c.company.id, suspended));

  Future<String?> delete(CompanyOverview c) =>
      _mutate(() => repository.deleteCompany(c.company.id));

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
