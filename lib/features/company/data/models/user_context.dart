import 'package:time_trak/core/models/user_model.dart';
import 'package:time_trak/features/auth/data/models/user_role.dart';

import 'company.dart';
import 'company_invitation.dart';

/// Everything the app needs to decide what a signed-in user may see,
/// loaded in one call from the `get_my_context` RPC.
class UserContext {
  final UserModel? user;
  final bool isSuperAdmin;
  final Company? company;

  /// The newest company registration request this user submitted.
  final Company? latestRequest;

  /// Open invitations addressed to this user's e-mail.
  final List<CompanyInvitation> invitations;

  const UserContext({
    required this.user,
    required this.isSuperAdmin,
    required this.company,
    required this.latestRequest,
    required this.invitations,
  });

  bool get hasCompany => company != null;
  bool get isActive => user?.isActive ?? true;

  bool get isCompanyAdmin =>
      company?.status == CompanyStatus.approved &&
      user?.role == UserRole.admin &&
      isActive;

  /// Whether the desktop tracker may record time for this user.
  bool get canTrack =>
      isActive && (company?.status == CompanyStatus.approved || isSuperAdmin);

  factory UserContext.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? map(String key) =>
        (json[key] as Map?)?.cast<String, dynamic>();
    final user = map('user');
    final company = map('company');
    final request = map('latest_request');
    return UserContext(
      user: user == null ? null : UserModel.fromJson(user),
      isSuperAdmin: json['is_super_admin'] as bool? ?? false,
      company: company == null ? null : Company.fromJson(company),
      latestRequest: request == null ? null : Company.fromJson(request),
      invitations: ((json['invitations'] as List?) ?? const [])
          .map((e) => CompanyInvitation.fromJson((e as Map).cast()))
          .toList(),
    );
  }
}
