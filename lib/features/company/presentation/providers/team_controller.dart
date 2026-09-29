import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../auth/data/models/user_role.dart';
import '../../data/models/company.dart';
import '../../data/models/company_invitation.dart';
import '../../data/models/team_member.dart';
import '../../data/repository/company_repository.dart';

/// Members and invitations of one company, refreshed every minute so the
/// "working now" state stays live. All team mutations go through here.
class TeamController extends ChangeNotifier {
  final CompanyRepository repository;
  final Company company;

  TeamController({required this.repository, required this.company}) {
    load();
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => load(silent: true),
    );
  }

  Timer? _timer;
  bool _disposed = false;

  List<TeamMember> _members = const [];
  List<CompanyInvitation> _invitations = const [];
  bool _loading = true;
  String? _error;
  DateTime? _updatedAt;

  List<TeamMember> get members => _members;
  List<CompanyInvitation> get invitations => _invitations;
  bool get isLoading => _loading;
  String? get error => _error;
  DateTime? get updatedAt => _updatedAt;

  int get workingCount => _members.where((m) => m.isWorking).length;
  int get openInvitationCount => _invitations.where((i) => i.isOpen).length;

  /// A [silent] load keeps the current data on screen and hides errors.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      _notify();
    }
    try {
      final results = await Future.wait([
        repository.getTeamMembers(companyId: company.id),
        repository.getInvitations(company.id),
      ]);
      _members = results[0] as List<TeamMember>;
      _invitations = results[1] as List<CompanyInvitation>;
      _error = null;
      _updatedAt = DateTime.now();
    } catch (e) {
      if (!silent) _error = friendlyError(e);
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

  Future<String?> setRole(TeamMember m, UserRole role) =>
      _mutate(() => repository.updateMemberRole(m.id, role));

  Future<String?> setActive(TeamMember m, bool active) =>
      _mutate(() => repository.setMemberActive(m.id, active));

  Future<String?> remove(TeamMember m) =>
      _mutate(() => repository.removeMember(m.id));

  Future<String?> resendInvitation(CompanyInvitation inv) => _mutate(
    () => repository.inviteMember(
      email: inv.email,
      role: inv.role,
      companyId: company.id,
    ),
  );

  Future<String?> revokeInvitation(CompanyInvitation inv) =>
      _mutate(() => repository.revokeInvitation(inv.id));

  Future<String?> updateProfile(CompanyDetails details) => _mutate(
    () => repository.updateCompanyProfile(details, companyId: company.id),
  );

  String? inviteUrlFor(CompanyInvitation inv) =>
      repository.inviteUrlFor(inv.token);

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
