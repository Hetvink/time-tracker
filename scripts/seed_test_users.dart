// Dev-only CLI script: seeds test accounts.
//   SUPABASE_SERVICE_ROLE_KEY=... dart run scripts/seed_test_users.dart
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:io';

import 'package:supabase/supabase.dart';

Future<void> main() async {
  const supabaseUrl = 'https://libmlmlpwxuevggmmtub.supabase.co';
  // Never hard-code the service role key: it bypasses all RLS.
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    print('Set SUPABASE_SERVICE_ROLE_KEY before running this script.');
    exit(1);
  }

  final supabase = SupabaseClient(supabaseUrl, serviceRoleKey);

  print('🚀 Starting to seed test users...');

  try {
    Future<String> getOrCreateUser(String email) async {
      print('Setting up $email...');
      try {
        final res = await supabase.auth.admin.createUser(
          AdminUserAttributes(
            email: email,
            password: 'password123',
            emailConfirm: true,
          ),
        );
        return res.user!.id;
      } catch (e) {
        if (e.toString().contains('already been registered') ||
            e.toString().contains('email_exists')) {
          print('User $email already exists, fetching ID...');
          // Fetch from public.users table where trigger should have created them
          final existing = await supabase
              .from('users')
              .select('id')
              .eq('email', email)
              .maybeSingle();
          if (existing != null) {
            return existing['id'] as String;
          }
          throw Exception('User exists in auth but not in public.users yet.');
        }
        rethrow;
      }
    }

    // 1. Create Platform Admin
    await getOrCreateUser('admin@test.com');
    await supabase.from('platform_admin_emails').upsert({
      'email': 'admin@test.com',
    });

    // 2. Create Company Admin
    final companyAdminId = await getOrCreateUser('company@test.com');

    // 3. Create Member
    final memberId = await getOrCreateUser('member@test.com');

    // Set up the company (Approved)
    print('Setting up company and roles...');

    // Check if company exists first
    final existingCompany = await supabase
        .from('companies')
        .select('id')
        .eq('slug', 'test-company-llc')
        .maybeSingle();

    String companyId;
    if (existingCompany != null) {
      companyId = existingCompany['id'] as String;
      print('Company already exists.');
    } else {
      final companyRes = await supabase
          .from('companies')
          .insert({
            'name': 'Test Company LLC',
            'slug': 'test-company-llc',
            'status': 'approved',
          })
          .select()
          .single();
      companyId = companyRes['id'];
    }

    // Assign Company Admin
    await supabase
        .from('users')
        .update({'company_id': companyId, 'role': 'admin'})
        .eq('id', companyAdminId);

    // Assign Member
    await supabase
        .from('users')
        .update({'company_id': companyId, 'role': 'member'})
        .eq('id', memberId);

    print('✅ Success! Test accounts created and linked.');
    print('-----------------------------------------');
    print('Platform Admin : admin@test.com / password123');
    print('Company Admin  : company@test.com / password123');
    print('Member         : member@test.com / password123');
    print('-----------------------------------------');
  } catch (e) {
    print('❌ Error: $e');
  }

  exit(0);
}
