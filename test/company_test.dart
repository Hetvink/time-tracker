import 'package:flutter_test/flutter_test.dart';
import 'package:time_trak/features/auth/data/models/user_role.dart';
import 'package:time_trak/features/company/data/models/company.dart';
import 'package:time_trak/features/company/data/models/company_invitation.dart';
import 'package:time_trak/features/company/data/models/team_member.dart';
import 'package:time_trak/features/company/data/models/user_context.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';

// Shapes below mirror what the RPCs in supabase/schema.sql return.
Map<String, dynamic> _company({String status = 'approved'}) => {
  'id': 'c1',
  'name': 'Acme Inc',
  'slug': 'acme-inc',
  'status': status,
  'created_by': 'u1',
  'created_at': '2026-09-01T10:00:00+00:00',
};

Map<String, dynamic> _user({String role = 'member', bool active = true}) => {
  'id': 'u1',
  'email': 'alice@acme.com',
  'name': 'Alice',
  'role': role,
  'company_id': 'c1',
  'is_active': active,
  'created_at': '2026-09-01T10:00:00+00:00',
};

void main() {
  group('CompanyProvider.extractInviteToken', () {
    const token =
        '3f2a9c1b7d4e4f0a8b6c2d1e9f7a5b3c3f2a9c1b7d4e4f0a8b6c2d1e9f7a5b3c';

    test('reads the token from an invite link', () {
      expect(
        CompanyProvider.extractInviteToken(
          'https://app.example.com/?invite=$token',
        ),
        token,
      );
    });

    test('accepts a bare token', () {
      expect(CompanyProvider.extractInviteToken('  $token  '), token);
    });

    test('rejects unrelated text', () {
      expect(CompanyProvider.extractInviteToken('hello'), isNull);
      expect(CompanyProvider.extractInviteToken(''), isNull);
      expect(
        CompanyProvider.extractInviteToken('https://app.example.com/'),
        isNull,
      );
    });
  });

  group('UserContext', () {
    test('company admin of an approved company can manage and track', () {
      final ctx = UserContext.fromJson({
        'user': _user(role: 'admin'),
        'is_super_admin': false,
        'company': _company(),
        'latest_request': null,
        'invitations': [],
      });
      expect(ctx.isCompanyAdmin, isTrue);
      expect(ctx.canTrack, isTrue);
    });

    test('suspended company blocks admin rights and tracking', () {
      final ctx = UserContext.fromJson({
        'user': _user(role: 'admin'),
        'is_super_admin': false,
        'company': _company(status: 'suspended'),
        'invitations': [],
      });
      expect(ctx.isCompanyAdmin, isFalse);
      expect(ctx.canTrack, isFalse);
    });

    test('deactivated member cannot track', () {
      final ctx = UserContext.fromJson({
        'user': _user(active: false),
        'is_super_admin': false,
        'company': _company(),
        'invitations': [],
      });
      expect(ctx.canTrack, isFalse);
    });

    test('user without company sees pending request and invitations', () {
      final ctx = UserContext.fromJson({
        'user': {..._user(), 'company_id': null},
        'is_super_admin': false,
        'company': null,
        'latest_request': _company(status: 'pending'),
        'invitations': [
          {
            'id': 'i1',
            'token': 'abc',
            'email': 'alice@acme.com',
            'role': 'member',
            'status': 'pending',
            'expires_at': DateTime.now()
                .add(const Duration(days: 3))
                .toIso8601String(),
            'company_name': 'Other Co',
            'invited_by_name': 'Bob',
          },
        ],
      });
      expect(ctx.hasCompany, isFalse);
      expect(ctx.canTrack, isFalse);
      expect(ctx.latestRequest?.status, CompanyStatus.pending);
      expect(ctx.invitations.single.isOpen, isTrue);
      expect(ctx.invitations.single.invitedBy, 'Bob');
    });

    test('platform admin may track without a company', () {
      final ctx = UserContext.fromJson({
        'user': {..._user(), 'company_id': null},
        'is_super_admin': true,
        'invitations': [],
      });
      expect(ctx.canTrack, isTrue);
    });
  });

  group('CompanyInvitation', () {
    test('expired pending invitation is not open', () {
      final inv = CompanyInvitation.fromJson({
        'id': 'i1',
        'token': 't',
        'email': 'x@y.com',
        'role': 'admin',
        'status': 'pending',
        'expires_at': DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      });
      expect(inv.role, UserRole.admin);
      expect(inv.isExpired, isTrue);
      expect(inv.isOpen, isFalse);
    });
  });

  group('TeamMember', () {
    test('parses live status and totals', () {
      final m = TeamMember.fromJson({
        'id': 'u2',
        'email': 'sam.lee@acme.com',
        'name': null,
        'role': 'member',
        'is_active': true,
        'is_working': true,
        'is_on_break': false,
        'today_work_seconds': 5400,
        'week_work_seconds': 36000,
        'month_work_seconds': 90000,
      });
      expect(m.displayName, 'sam.lee');
      expect(m.today, const Duration(hours: 1, minutes: 30));
      expect(m.week.inHours, 10);
      expect(m.toProfileMap()['role'], 'member');
    });
  });

  group('CompanyDetails', () {
    test('maps to RPC parameter names', () {
      const details = CompanyDetails(name: 'Acme', companySize: '11-50');
      expect(details.toRpcParams(), containsPair('p_name', 'Acme'));
      expect(details.toRpcParams(), containsPair('p_company_size', '11-50'));
    });
  });
}
