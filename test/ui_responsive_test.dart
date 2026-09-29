// Renders every main screen with offline fakes at phone, tablet and desktop
// widths (and both themes) and fails on any layout exception or overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/admin/presentation/screens/member_profile_page.dart';
import 'package:time_trak/features/auth/presentation/screens/login/login_page.dart';
import 'package:time_trak/features/company/data/models/company.dart';
import 'package:time_trak/features/company/presentation/screens/onboarding/onboarding_page.dart';
import 'package:time_trak/features/company/presentation/screens/team/team_page.dart';
import 'package:time_trak/features/insights/data/insights.dart';
import 'package:time_trak/features/insights/presentation/my_activity_page.dart';
import 'package:time_trak/features/platform_admin/presentation/screens/platform_admin/platform_admin_page.dart';
import 'package:time_trak/features/settings/presentation/screens/settings/settings_page.dart';
import 'package:time_trak/features/timesheet/presentation/screens/timesheet_hub/timesheet_hub_page.dart';
import 'package:time_trak/features/tracking/presentation/screens/desktop_dashboard_page.dart';
import 'package:time_trak/features/home/presentation/home/home_page.dart';
import 'package:time_trak/routes/navigation_provider.dart';
import 'package:time_trak/features/company/data/models/user_context.dart';
import 'package:time_trak/features/settings/presentation/providers/preferences_service.dart';
import 'package:time_trak/features/tracking/data/datasource/platform_channel_service.dart';

import 'support/ui_fakes.dart';

const _sizes = {
  'phone': Size(390, 844),
  'small-phone': Size(340, 700),
  'tablet': Size(820, 1180),
  'desktop': Size(1440, 900),
};

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Size size,
  required Widget Function() page,
  ThemeMode mode = ThemeMode.dark,
  UserContext? ctx,
  bool signedIn = true,
  bool empty = false,
  Future<void> Function(WidgetTester t)? interact,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController();
  await theme.setMode(mode);

  await tester.pumpWidget(
    fakeApp(
      page: page(),
      prefs: prefs,
      theme: theme,
      ctx: ctx,
      signedIn: signedIn,
      empty: empty,
    ),
  );
  // Let futures resolve and entrance animations run.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  if (interact != null) await interact(tester);
  // Replace the tree so periodic timers are cancelled before the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _tapTabs(WidgetTester t, List<String> labels) async {
  for (final l in labels) {
    final f = find.textContaining(l);
    if (f.evaluate().isEmpty) continue;
    await t.tap(f.first, warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final screens =
      <String, (Widget Function(), Future<void> Function(WidgetTester)?)>{
        'login': (() => const LoginPage(), null),
        'home': (() => fakeShell(const HomePage()), null),
        'my-activity': (
          () => fakeShell(const MyActivityPage(), index: NavIndex.activity),
          (t) => _tapTabs(t, ['Day', 'Month', 'Apps', 'Overview']),
        ),
        'timesheet': (
          () => fakeShell(const TimesheetHubPage(), index: NavIndex.timesheet),
          null,
        ),
        'team': (
          () => fakeShell(
            TeamPage(company: Company.fromJson(companyJson())),
            index: NavIndex.team,
          ),
          (t) => _tapTabs(t, [
            'Members',
            'Invitations',
            'Reports',
            'Company',
            'Overview',
          ]),
        ),
        'platform': (
          () => fakeShell(
            const PlatformAdminPage(),
            index: NavIndex.platformAdmin,
          ),
          (t) => _tapTabs(t, ['Overview', 'Requests', 'Companies']),
        ),
        'member-profile': (
          () => MemberProfilePage(member: fakeMembers()[2]),
          (t) => _tapTabs(t, ['Day', 'Month', 'Apps']),
        ),
        'settings': (
          () => fakeShell(
            SettingsPage(
              preferencesService: PreferencesService(_prefsSync!),
              platformService: PlatformChannelService(),
            ),
            index: NavIndex.settings,
          ),
          null,
        ),
        'desktop-tracker': (
          () => fakeShell(const DesktopDashboardPage()),
          null,
        ),
      };

  for (final (name, (page, interact)) in screens.entries.map(
    (e) => (e.key, e.value),
  )) {
    for (final entry in _sizes.entries) {
      testWidgets('$name renders at ${entry.key}', (tester) async {
        _prefsSync ??= await _prefs();
        await _pumpScreen(
          tester,
          size: entry.value,
          page: page,
          signedIn: name != 'login',
          interact: interact,
        );
      });
    }
  }

  // A brand-new account: every card shows its empty state, often inside
  // short fixed-height boxes (regression test for bottom overflows).
  for (final (name, (page, interact))
      in screens.entries
          .where(
            (e) => const [
              'home',
              'my-activity',
              'team',
              'member-profile',
            ].contains(e.key),
          )
          .map((e) => (e.key, e.value))) {
    for (final size in ['small-phone', 'tablet', 'desktop']) {
      testWidgets('$name renders with no data at $size', (tester) async {
        await _pumpScreen(
          tester,
          size: _sizes[size]!,
          page: page,
          empty: true,
          interact: interact,
        );
      });
    }
  }

  testWidgets('onboarding renders at phone and desktop', (tester) async {
    for (final size in [_sizes['phone']!, _sizes['desktop']!]) {
      await _pumpScreen(
        tester,
        size: size,
        page: () => const OnboardingPage(),
        ctx: fakeContext(withCompany: false),
      );
    }
  });

  testWidgets('light theme: home, team and login at desktop', (tester) async {
    for (final page in [
      () => fakeShell(const HomePage()),
      () => fakeShell(TeamPage(company: Company.fromJson(companyJson()))),
    ]) {
      await _pumpScreen(
        tester,
        size: _sizes['desktop']!,
        page: page,
        mode: ThemeMode.light,
      );
    }
    await _pumpScreen(
      tester,
      size: _sizes['phone']!,
      page: () => const LoginPage(),
      mode: ThemeMode.light,
      signedIn: false,
    );
  });

  test('insights math: merges overlaps and splits days', () {
    final day = DateTime(2026, 9, 10);
    final s = SessionInfo.fromRow({
      'id': 's',
      'check_in_time_utc': DateTime(2026, 9, 10, 22).toUtc().toIso8601String(),
      'check_out_time_utc': DateTime(2026, 9, 11, 2).toUtc().toIso8601String(),
      'is_closed': true,
      'break_periods': [
        {
          'break_start_time_utc': DateTime(
            2026,
            9,
            10,
            23,
          ).toUtc().toIso8601String(),
          'break_end_time_utc': DateTime(
            2026,
            9,
            10,
            23,
            30,
          ).toUtc().toIso8601String(),
        },
      ],
    }, now)!;
    final i = Insights(
      from: day,
      to: day.add(const Duration(days: 2)),
      sessions: [s, s],
      activities: const [],
      computedAt: now,
    );
    expect(i.total, const Duration(hours: 3, minutes: 30));
    expect(i.daily[day], const Duration(hours: 1, minutes: 30));
    expect(i.daily[day.add(const Duration(days: 1))], const Duration(hours: 2));
    expect(i.breakTotal, const Duration(hours: 1)); // both copies counted
    expect(prettySource('autoSystemStart'), 'Auto · startup');
  });
}

SharedPreferences? _prefsSync;
Future<SharedPreferences> _prefs() {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}
