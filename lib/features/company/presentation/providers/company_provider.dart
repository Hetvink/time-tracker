import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/company.dart';
import '../../data/models/company_invitation.dart';
import '../../data/models/user_context.dart';
import '../../data/repository/company_repository.dart';

/// Holds the signed-in user's company context (company, role, pending
/// request, invitations) and exposes the onboarding actions.
///
/// Wired to [AuthProvider] with a ChangeNotifierProxyProvider: call
/// [onUserChanged] whenever the authenticated user changes.
class CompanyProvider extends ChangeNotifier {
  static const _pendingInviteKey = 'pending_invite_token';

  final CompanyRepository repository;

  CompanyProvider(this.repository) {
    _restorePendingInvite();
  }

  String? _userId;
  UserContext? _context;
  bool _isLoading = false;
  String? _error;
  String? _pendingInviteToken;
  CompanyInvitation? _linkInvitation;

  UserContext? get context => _context;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Company? get company => _context?.company;
  bool get isSuperAdmin => _context?.isSuperAdmin ?? false;
  bool get isCompanyAdmin => _context?.isCompanyAdmin ?? false;
  bool get canTrack => _context?.canTrack ?? false;

  /// Invitation opened through an invite link (`?invite=<token>`).
  CompanyInvitation? get linkInvitation => _linkInvitation;

  /// Invitations to show on the onboarding screen: the one from the link
  /// first, then any others addressed to this e-mail.
  List<CompanyInvitation> get openInvitations {
    final fromEmail = _context?.invitations ?? const <CompanyInvitation>[];
    final link = _linkInvitation;
    if (link == null || !link.isOpen) return fromEmail;
    return [link, ...fromEmail.where((i) => i.id != link.id)];
  }

  void onUserChanged(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _context = null;
    _error = null;
    _linkInvitation = null;
    // Called from ProxyProvider.update during build: defer notifications
    Future.microtask(userId != null ? load : notifyListeners);
  }

  Future<void> load() async {
    if (_userId == null) return;
    final requestedFor = _userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final ctx = await repository.getMyContext();
      if (requestedFor != _userId) return; // user switched meanwhile
      _context = ctx;
      await _resolveLinkInvitation();
    } catch (e) {
      debugPrint('[CompanyProvider] load failed: $e');
      if (requestedFor == _userId) _error = friendlyError(e);
    } finally {
      if (requestedFor == _userId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Invite links
  // ---------------------------------------------------------------------------

  Future<void> _restorePendingInvite() async {
    if (_pendingInviteToken != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingInviteToken = prefs.getString(_pendingInviteKey);
      if (_pendingInviteToken != null) notifyListeners();
    } catch (_) {}
  }

  /// Remember an invite token until the user has signed in and handled it.
  Future<void> setPendingInviteToken(String token) async {
    _pendingInviteToken = token.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingInviteKey, _pendingInviteToken!);
    } catch (_) {}
    if (_context != null) {
      await _resolveLinkInvitation();
      notifyListeners();
    }
  }

  bool get hasPendingInviteLink => _pendingInviteToken != null;

  Future<void> _clearPendingInvite() async {
    _pendingInviteToken = null;
    _linkInvitation = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingInviteKey);
    } catch (_) {}
  }

  Future<void> _resolveLinkInvitation() async {
    await _restorePendingInvite();
    final token = _pendingInviteToken;
    if (token == null) return;
    try {
      final preview = await repository.getInvitationPreview(token);
      if (preview == null || !preview.isOpen || _context?.hasCompany == true) {
        // Unknown, used, expired, or the user already has a company
        if (preview != null && preview.isOpen) {
          _linkInvitation = preview; // still show why it can't be used
        } else {
          await _clearPendingInvite();
        }
        return;
      }
      _linkInvitation = preview;
    } catch (e) {
      debugPrint('[CompanyProvider] invite preview failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Actions (each returns an error message, or null on success)
  // ---------------------------------------------------------------------------

  Future<String?> _run(Future<void> Function() action) async {
    try {
      await action();
      await load();
      return null;
    } catch (e) {
      debugPrint('[CompanyProvider] action failed: $e');
      return friendlyError(e);
    }
  }

  Future<String?> requestCompany(CompanyDetails details) =>
      _run(() => repository.requestCompany(details));

  Future<String?> cancelRequest(String companyId) =>
      _run(() => repository.cancelCompanyRequest(companyId));

  Future<String?> acceptInvitation(String token) => _run(() async {
    await repository.acceptInvitation(token);
    if (token == _pendingInviteToken) await _clearPendingInvite();
  });

  Future<String?> declineInvitation(String token) => _run(() async {
    await repository.declineInvitation(token);
    if (token == _pendingInviteToken) await _clearPendingInvite();
  });

  /// Accepts an invite code or full invite link pasted by the user.
  Future<String?> acceptInviteCode(String input) async {
    final token = extractInviteToken(input);
    if (token == null) return 'That does not look like an invitation link.';
    return acceptInvitation(token);
  }

  Future<String?> leaveCompany() => _run(repository.leaveCompany);

  Future<String?> updateCompanyProfile(CompanyDetails details) =>
      _run(() => repository.updateCompanyProfile(details));

  /// Pulls the token out of `https://app/?invite=<token>` or a bare token.
  static String? extractInviteToken(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final fromQuery = uri?.queryParameters['invite'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    return RegExp(r'^[a-f0-9]{32,}$').hasMatch(text) ? text : null;
  }
}
