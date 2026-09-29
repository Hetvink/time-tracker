import 'package:time_trak/features/auth/data/models/user_role.dart';

import 'company.dart';

enum InvitationStatus {
  pending,
  accepted,
  declined,
  revoked,
  expired;

  static InvitationStatus fromString(String? value) =>
      InvitationStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => InvitationStatus.pending,
      );
}

class CompanyInvitation {
  final String id;
  final String email;
  final UserRole role;
  final String token;
  final InvitationStatus status;
  final DateTime expiresAt;
  final DateTime? createdAt;
  final String? companyId;
  final String? companyName;
  final CompanyStatus? companyStatus;
  final String? invitedByName;
  final String? invitedByEmail;

  /// Only set by the invitation preview: does the signed-in account's
  /// e-mail match the invited address?
  final bool? emailMatches;

  const CompanyInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.token,
    required this.status,
    required this.expiresAt,
    this.createdAt,
    this.companyId,
    this.companyName,
    this.companyStatus,
    this.invitedByName,
    this.invitedByEmail,
    this.emailMatches,
  });

  bool get isExpired =>
      status == InvitationStatus.expired || expiresAt.isBefore(DateTime.now());

  bool get isOpen => status == InvitationStatus.pending && !isExpired;

  String get invitedBy => invitedByName ?? invitedByEmail ?? 'Your admin';

  factory CompanyInvitation.fromJson(Map<String, dynamic> json) {
    final companyStatus = json['company_status'] as String?;
    return CompanyInvitation(
      id: json['id'] as String,
      email: json['email'] as String,
      role: UserRole.fromString(json['role'] as String?),
      token: json['token'] as String,
      status: InvitationStatus.fromString(json['status'] as String?),
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String).toLocal(),
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String?,
      companyStatus: companyStatus == null
          ? null
          : CompanyStatus.fromString(companyStatus),
      invitedByName: json['invited_by_name'] as String?,
      invitedByEmail: json['invited_by_email'] as String?,
      emailMatches: json['email_matches'] as bool?,
    );
  }
}

/// Result of sending an invitation through the `invite-member` function.
class InviteResult {
  final CompanyInvitation invitation;
  final String? inviteUrl;
  final bool emailSent;
  final String? emailError;

  const InviteResult({
    required this.invitation,
    required this.inviteUrl,
    required this.emailSent,
    this.emailError,
  });
}
