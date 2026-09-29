// Browser preview of the UI with demo data — no Supabase needed.
//   flutter run -d chrome -t test/support/ui_preview_main.dart
// then add ?screen=home|activity|timesheet|team|platform|member|settings|
// tracker|onboarding and &theme=light|dark to the URL.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/admin/presentation/screens/member_profile_page.dart';
import 'package:time_trak/features/company/data/models/company.dart';
import 'package:time_trak/features/company/presentation/screens/onboarding/onboarding_page.dart';
import 'package:time_trak/features/company/presentation/screens/team_page.dart';
import 'package:time_trak/features/home/presentation/home_page.dart';
import 'package:time_trak/features/insights/presentation/my_activity_page.dart';
import 'package:time_trak/features/platform_admin/presentation/screens/platform_admin_page.dart';
import 'package:time_trak/features/settings/presentation/providers/preferences_service.dart';
import 'package:time_trak/features/settings/presentation/screens/settings_page.dart';
import 'package:time_trak/features/timesheet/presentation/screens/timesheet_hub_page.dart';
import 'package:time_trak/features/tracking/data/datasource/platform_channel_service.dart';
import 'package:time_trak/features/tracking/presentation/screens/desktop_dashboard_page.dart';
import 'package:time_trak/routes/navigation_provider.dart';

import 'ui_fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final q = Uri.base.queryParameters;
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController();
  await theme.setMode(q['theme'] == 'light' ? ThemeMode.light : ThemeMode.dark);
  final company = Company.fromJson(companyJson());
  final page = switch (q['screen']) {
    'activity' => fakeShell(const MyActivityPage(), index: NavIndex.activity),
    'timesheet' => fakeShell(
      const TimesheetHubPage(),
      index: NavIndex.timesheet,
    ),
    'team' => fakeShell(TeamPage(company: company), index: NavIndex.team),
    'platform' => fakeShell(
      const PlatformAdminPage(),
      index: NavIndex.platformAdmin,
    ),
    'member' => MemberProfilePage(member: fakeMembers()[3]),
    'settings' => fakeShell(
      SettingsPage(
        preferencesService: PreferencesService(prefs),
        platformService: PlatformChannelService(),
      ),
      index: NavIndex.settings,
    ),
    'tracker' => fakeShell(const DesktopDashboardPage()),
    'onboarding' => const OnboardingPage(),
    _ => fakeShell(const HomePage()),
  };
  runApp(
    fakeApp(
      page: page,
      prefs: prefs,
      theme: theme,
      ctx: q['screen'] == 'onboarding' ? fakeContext(withCompany: false) : null,
    ),
  );
}
