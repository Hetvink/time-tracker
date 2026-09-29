import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:time_trak/core/constants/app_env.dart';
import 'package:time_trak/features/auth/data/models/user_role.dart';

import '../models/company.dart';
import '../models/company_invitation.dart';
import '../models/team_member.dart';
import '../models/user_context.dart';

/// Turns Supabase / network errors into a message fit for a snackbar.
String friendlyError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return error.reasonPhrase ?? 'Request failed (${error.status}).';
  }
  if (error is AuthException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

/// Companies, memberships and invitations. Every call goes through a
/// SECURITY DEFINER RPC in `supabase/schema.sql`, which enforces who may
/// do what — the checks here are only for nicer UX.
class CompanyRepository {
  final SupabaseClient _supabase;

  CompanyRepository(this._supabase);

  Future<Map<String, dynamic>?> _rpcRow(
    String fn, [
    Map<String, dynamic>? params,
  ]) async {
    final result = await _supabase.rpc(fn, params: params);
    if (result == null) return null;
    if (result is List) {
      return result.isEmpty ? null : (result.first as Map).cast();
    }
    return (result as Map).cast();
  }

  Future<List<Map<String, dynamic>>> _rpcRows(
    String fn, [
    Map<String, dynamic>? params,
  ]) async {
    final result = await _supabase.rpc(fn, params: params) as List;
    return result.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  // ---------------------------------------------------------------------------
  // Current user
  // ---------------------------------------------------------------------------

  Future<UserContext> getMyContext() async {
    final json = await _rpcRow('get_my_context');
    if (json == null) throw Exception('Could not load your account.');
    return UserContext.fromJson(json);
  }

  Future<Company> requestCompany(CompanyDetails details) async {
    final row = await _rpcRow('request_company', details.toRpcParams());
    return Company.fromJson(row!);
  }

  Future<void> cancelCompanyRequest(String companyId) => _supabase.rpc(
    'cancel_company_request',
    params: {'p_company_id': companyId},
  );

  Future<CompanyInvitation?> getInvitationPreview(String token) async {
    final row = await _rpcRow('get_invitation_preview', {'p_token': token});
    return row == null ? null : CompanyInvitation.fromJson(row);
  }

  Future<Company> acceptInvitation(String token) async {
    final row = await _rpcRow('accept_invitation', {'p_token': token});
    return Company.fromJson(row!);
  }

  Future<void> declineInvitation(String token) =>
      _supabase.rpc('decline_invitation', params: {'p_token': token});

  Future<void> leaveCompany() => _supabase.rpc('leave_company');

  Future<void> deleteMyAccount() => _supabase.rpc('delete_my_account');

  // ---------------------------------------------------------------------------
  // Company admin
  // ---------------------------------------------------------------------------

  Future<Company> updateCompanyProfile(
    CompanyDetails details, {
    String? companyId,
  }) async {
    final row = await _rpcRow('update_company_profile', {
      ...details.toRpcParams(),
      'p_company_id': companyId,
    });
    return Company.fromJson(row!);
  }

  /// Team list with live status. Day/week/month totals use the viewer's
  /// local calendar.
  Future<List<TeamMember>> getTeamMembers({String? companyId}) async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final weekStart = dayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month);

    final rows = await _rpcRows('get_company_members', {
      'p_company_id': companyId,
      'p_day_start': dayStart.toUtc().toIso8601String(),
      'p_week_start': weekStart.toUtc().toIso8601String(),
      'p_month_start': monthStart.toUtc().toIso8601String(),
    });
    return rows.map(TeamMember.fromJson).toList();
  }

  Future<List<CompanyInvitation>> getInvitations(String companyId) async {
    final rows = await _supabase
        .from('company_invitations')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map(CompanyInvitation.fromJson).toList();
  }

  String? inviteUrlFor(String token) {
    final base = AppEnv.webAppUrl;
    return base.isEmpty ? null : '$base/?invite=$token';
  }

  /// Creates the invitation and e-mails it via the `invite-member` Edge
  /// Function. If the function is not deployed, the invitation is still
  /// created and the link is returned for manual sharing.
  Future<InviteResult> inviteMember({
    required String email,
    UserRole role = UserRole.member,
    String? companyId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'invite-member',
        body: {
          'email': email,
          'role': role.value,
          'company_id': ?companyId,
          if (AppEnv.webAppUrl.isNotEmpty) 'app_url': AppEnv.webAppUrl,
        },
      );
      final data = (response.data as Map).cast<String, dynamic>();
      final invitation = CompanyInvitation.fromJson(
        (data['invitation'] as Map).cast(),
      );
      return InviteResult(
        invitation: invitation,
        inviteUrl:
            data['invite_url'] as String? ?? inviteUrlFor(invitation.token),
        emailSent: data['email_sent'] as bool? ?? false,
        emailError: data['email_error'] as String?,
      );
    } on FunctionException catch (e) {
      // 404 → function not deployed. Anything else is a real error
      // (e.g. "already a member") and is shown to the admin.
      if (e.status != 404) rethrow;
      debugPrint('[CompanyRepository] invite-member not deployed, using RPC');
    }

    final row = await _rpcRow('create_invitation', {
      'p_email': email,
      'p_role': role.value,
      'p_company_id': companyId,
    });
    final invitation = CompanyInvitation.fromJson(row!);
    return InviteResult(
      invitation: invitation,
      inviteUrl: inviteUrlFor(invitation.token),
      emailSent: false,
      emailError:
          'E-mail sending is not set up yet (deploy the invite-member function). Share the link manually.',
    );
  }

  Future<void> revokeInvitation(String invitationId) => _supabase.rpc(
    'revoke_invitation',
    params: {'p_invitation_id': invitationId},
  );

  Future<void> updateMemberRole(String userId, UserRole role) => _supabase.rpc(
    'update_member_role',
    params: {'p_user_id': userId, 'p_role': role.value},
  );

  Future<void> setMemberActive(String userId, bool active) => _supabase.rpc(
    'set_member_active',
    params: {'p_user_id': userId, 'p_active': active},
  );

  Future<void> removeMember(String userId) =>
      _supabase.rpc('remove_member', params: {'p_user_id': userId});

  // ---------------------------------------------------------------------------
  // Platform admin
  // ---------------------------------------------------------------------------

  Future<PlatformStats> getPlatformStats() async {
    final row = await _rpcRow('get_platform_stats');
    return PlatformStats.fromJson(row ?? const {});
  }

  Future<List<CompanyOverview>> getCompaniesOverview({
    CompanyStatus? status,
  }) async {
    final rows = await _rpcRows('get_companies_overview', {
      'p_status': status?.name,
    });
    return rows.map(CompanyOverview.fromJson).toList();
  }

  Future<Company> approveCompany(String companyId) async {
    final row = await _rpcRow('approve_company', {'p_company_id': companyId});
    return Company.fromJson(row!);
  }

  Future<Company> rejectCompany(String companyId, String? reason) async {
    final row = await _rpcRow('reject_company', {
      'p_company_id': companyId,
      'p_reason': reason,
    });
    return Company.fromJson(row!);
  }

  Future<Company> setCompanySuspended(String companyId, bool suspended) async {
    final row = await _rpcRow('set_company_suspended', {
      'p_company_id': companyId,
      'p_suspended': suspended,
    });
    return Company.fromJson(row!);
  }

  Future<void> deleteCompany(String companyId) =>
      _supabase.rpc('delete_company', params: {'p_company_id': companyId});
}
