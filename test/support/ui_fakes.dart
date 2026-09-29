// Offline fakes shared by the UI smoke test and the browser preview.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/auth/data/datasource/auth_service.dart';
import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/features/company/data/models/company.dart';
import 'package:time_trak/features/company/data/models/company_invitation.dart';
import 'package:time_trak/features/company/data/models/team_member.dart';
import 'package:time_trak/features/company/data/models/user_context.dart';
import 'package:time_trak/features/company/data/repository/company_repository.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';
import 'package:time_trak/features/insights/data/insights.dart';
import 'package:time_trak/features/insights/data/insights_repository.dart';
import 'package:time_trak/features/settings/presentation/providers/preferences_service.dart';
import 'package:time_trak/features/settings/presentation/providers/settings_provider.dart';
import 'package:time_trak/features/timesheet/data/models/daily_timesheet.dart';
import 'package:time_trak/features/tracking/data/datasource/platform_channel_service.dart';
import 'package:time_trak/features/tracking/data/models/attendance_state.dart';
import 'package:time_trak/features/tracking/presentation/providers/activity_tracking_provider.dart';
import 'package:time_trak/features/tracking/presentation/providers/attendance_provider.dart';
import 'package:time_trak/features/platform_admin/presentation/platform_admin_controller.dart';
import 'package:time_trak/routes/app_shell.dart';
import 'package:time_trak/routes/navigation_provider.dart';

// -----------------------------------------------------------------------------
// Fake data
// -----------------------------------------------------------------------------

final _rand = math.Random(7);
final now = DateTime.now();

Insights fakeInsights(DateTime from, DateTime to) {
  final sessions = <SessionInfo>[];
  final acts = <ActivityEntry>[];
  const apps = [
    'VS Code',
    'Chrome',
    'Slack',
    'Figma',
    'Terminal',
    'Zoom',
    'Notion',
    'Mail',
  ];
  for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.isAfter(now) || d.weekday == 7) continue;
    final start = DateTime(
      d.year,
      d.month,
      d.day,
      8 + _rand.nextInt(2),
      _rand.nextInt(60),
    );
    final live = DateUtils.isSameDay(d, now);
    var end = start.add(
      Duration(hours: 6 + _rand.nextInt(4), minutes: _rand.nextInt(60)),
    );
    if (live) end = now.isAfter(start) ? now : start;
    final b = start.add(const Duration(hours: 3));
    final breaks = [
      if (b.isBefore(end)) BreakInfo(b, b.add(const Duration(minutes: 35))),
    ];
    final work = [
      if (breaks.isEmpty)
        TimeSpan(start, end)
      else ...[
        TimeSpan(start, b),
        TimeSpan(breaks.first.end, end),
      ],
    ];
    sessions.add(
      SessionInfo(
        id: '$d',
        start: start,
        end: end,
        isOpen: live,
        checkInSource: 'autoSystemStart',
        checkOutSource: live ? null : 'manualUser',
        breaks: breaks,
        sleep: const [],
        workIntervals: work,
      ),
    );
    for (
      var t = start;
      t.isBefore(end);
      t = t.add(Duration(minutes: 7 + _rand.nextInt(25)))
    ) {
      final app = apps[_rand.nextInt(apps.length)];
      acts.add(
        ActivityEntry(
          app,
          '$app — a quite long window title that should ellipsize nicely ${_rand.nextInt(9)}',
          t,
          t.add(const Duration(minutes: 6)),
        ),
      );
    }
  }
  return Insights(
    from: from,
    to: to,
    sessions: sessions,
    activities: acts,
    computedAt: now,
  );
}

class FakeInsightsRepository implements InsightsRepository {
  /// Simulates a brand-new account with nothing tracked.
  final bool empty;
  FakeInsightsRepository({this.empty = false});

  @override
  Future<Insights> load({
    required String userId,
    required DateTime from,
    required DateTime to,
    bool activities = true,
    bool force = false,
  }) async => empty
      ? Insights(
          from: DateUtils.dateOnly(from),
          to: DateUtils.dateOnly(to),
          sessions: const [],
          activities: const [],
          computedAt: now,
        )
      : fakeInsights(DateUtils.dateOnly(from), DateUtils.dateOnly(to));

  @override
  Future<Insights> day(String userId, DateTime day, {bool force = false}) =>
      load(
        userId: userId,
        from: day,
        to: DateTime(day.year, day.month, day.day + 1),
      );

  @override
  Future<Insights> month(
    String userId,
    int year,
    int month, {
    bool force = false,
  }) => load(
    userId: userId,
    from: DateTime(year, month),
    to: DateTime(year, month + 1),
  );

  @override
  Future<Insights> recent(String userId, int days, {bool force = false}) {
    final t = DateUtils.dateOnly(now);
    return load(
      userId: userId,
      from: t.subtract(Duration(days: days - 1)),
      to: t.add(const Duration(days: 1)),
    );
  }

  @override
  void invalidate() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> companyJson([
  String status = 'approved',
  String name = 'Acme Interplanetary Logistics',
]) => {
  'id': 'c-$name',
  'name': name,
  'slug': 'acme',
  'status': status,
  'industry': 'Software',
  'company_size': '11-50',
  'country': 'India',
  'website': 'https://acme.example',
  'description':
      'We build rockets and ship packages across the galaxy, quickly.',
  'created_by': 'u1',
  'created_at': now.subtract(const Duration(days: 40)).toIso8601String(),
};

List<TeamMember> fakeMembers() => [
  for (var i = 0; i < 14; i++)
    TeamMember.fromJson({
      'id': 'm$i',
      'email': 'person.number$i@acme-interplanetary.example',
      'name': i == 3
          ? null
          : [
              'Alice Johnson',
              'Bob',
              'Chandrasekhar Venkataraman',
              'x',
              'Eve',
              'Frank',
              'Grace Hopper',
            ][i % 7],
      'role': i < 2 ? 'admin' : 'member',
      'is_active': i != 9,
      'is_working': i % 3 == 0 && i != 9,
      'is_on_break': i == 6,
      'session_started_at': now
          .subtract(Duration(minutes: 30 + i * 7))
          .toIso8601String(),
      'last_seen_at': i == 5
          ? null
          : now.subtract(Duration(days: i % 5)).toIso8601String(),
      'today_work_seconds': i * 1900,
      'week_work_seconds': i * 11000,
      'month_work_seconds': i * 42000,
      'joined_company_at': now
          .subtract(const Duration(days: 30))
          .toIso8601String(),
    }),
];

List<CompanyInvitation> fakeInvites() => [
  for (final (i, s) in [
    'pending',
    'accepted',
    'declined',
    'revoked',
    'pending',
  ].indexed)
    CompanyInvitation.fromJson({
      'id': 'i$i',
      'email': 'invitee$i@example.com',
      'role': i == 0 ? 'admin' : 'member',
      'token': 'a' * 40,
      'status': s,
      'expires_at': now.add(Duration(days: i == 4 ? 1 : 6)).toIso8601String(),
      'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      'company_name': 'Acme',
      'invited_by_name': 'Alice',
    }),
];

class FakeCompanyRepository implements CompanyRepository {
  final UserContext ctx;
  final bool empty;
  FakeCompanyRepository(this.ctx, {this.empty = false});

  @override
  Future<UserContext> getMyContext() async => ctx;
  @override
  Future<List<TeamMember>> getTeamMembers({String? companyId}) async =>
      empty ? const [] : fakeMembers();
  @override
  Future<List<CompanyInvitation>> getInvitations(String companyId) async =>
      empty ? const [] : fakeInvites();
  @override
  Future<PlatformStats> getPlatformStats() async => PlatformStats.fromJson({
    'companies_total': 9,
    'companies_pending': 2,
    'companies_approved': 5,
    'companies_suspended': 1,
    'companies_rejected': 1,
    'users_total': 120,
    'users_without_company': 7,
    'working_now': 31,
  });
  @override
  Future<List<CompanyOverview>> getCompaniesOverview({
    CompanyStatus? status,
  }) async => [
    for (final (i, s) in [
      'pending',
      'pending',
      'approved',
      'approved',
      'approved',
      'approved',
      'approved',
      'suspended',
      'rejected',
    ].indexed)
      CompanyOverview.fromJson({
        ...companyJson(
          s,
          i.isEven ? 'Company with a really very long name number $i' : 'Co $i',
        ),
        'creator_name': 'Owner $i',
        'creator_email': 'owner$i@example.com',
        'member_count': i * 3,
        'admin_count': 1,
        'working_now': i,
      }),
  ];
  @override
  String? inviteUrlFor(String token) => 'https://app/?invite=$token';
  @override
  Future<CompanyInvitation?> getInvitationPreview(String token) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeAuthService implements AuthService {
  final User? user;
  FakeAuthService(this.user);

  @override
  User? get currentUser => user;
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  Future<Map<String, dynamic>?> getUserProfile() async => {'role': 'admin'};

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeAttendance extends ChangeNotifier implements AttendanceProvider {
  @override
  AttendanceState get state => AttendanceState(
    status: AttendanceStatus.checkedIn,
    checkInTime: now.subtract(const Duration(hours: 3, minutes: 12)),
    lastEventSource: EventSource.autoSystemStart,
  );
  @override
  Duration get todayClosedDuration => const Duration(hours: 3, minutes: 12);
  @override
  Duration get todayClosedBreakDuration => const Duration(minutes: 25);
  @override
  Duration get monthClosedDuration => const Duration(hours: 121);
  @override
  Duration get allTimeClosedDuration => const Duration(hours: 1400);
  @override
  int get totalSessionsCount => 311;
  @override
  Future<void> refresh() async {}
  @override
  Future<List<DailyTimeSheet>> getMonthlyDailyTimeSheets(
    int year,
    int month, {
    bool refresh = false,
  }) async => [
    for (var d = 1; d <= math.min(now.day, 28); d++)
      DailyTimeSheet(
        date: DateTime(year, month, d),
        sessions: [
          AttendanceSession(
            id: d,
            checkInTime: DateTime(year, month, d, 9),
            checkOutTime: DateTime(year, month, d, 17, d),
            checkInSource: EventSource.autoSystemStart,
            checkOutSource: EventSource.manualUser,
            breaks: [
              BreakPeriod(
                startTime: DateTime(year, month, d, 12),
                endTime: DateTime(year, month, d, 12, 40),
              ),
            ],
            isClosed: true,
            capturedWorkDuration: Duration(hours: 7, minutes: d),
          ),
        ],
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeActivityTracking extends ChangeNotifier
    implements ActivityTrackingProvider {
  @override
  DateTime get currentMonth => now;
  @override
  Map<String, dynamic> get monthStats => {
    'total_work_seconds': 400000,
    'total_break_seconds': 20000,
  };
  @override
  Future<void> refreshMonth() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

UserContext fakeContext({bool withCompany = true}) => UserContext.fromJson({
  'user': {
    'id': 'u1',
    'email': 'alice@acme.com',
    'name': 'Alice Johnson',
    'role': 'admin',
    'company_id': withCompany ? 'c1' : null,
    'is_active': true,
    'created_at': '2026-01-01T10:00:00Z',
  },
  'is_super_admin': true,
  'company': withCompany ? companyJson() : null,
  'latest_request': withCompany
      ? null
      : companyJson('pending', 'My Pending Co'),
  'invitations': withCompany
      ? []
      : [
          {
            'id': 'inv',
            'email': 'alice@acme.com',
            'role': 'member',
            'token': 'b' * 40,
            'status': 'pending',
            'expires_at': now.add(const Duration(days: 3)).toIso8601String(),
            'company_name': 'Globex',
            'invited_by_name': 'Hank',
            'email_matches': false,
          },
        ],
});

/// Providers + MaterialApp around [page], wired to the fakes above.
Widget fakeApp({
  required Widget page,
  required SharedPreferences prefs,
  required ThemeController theme,
  UserContext? ctx,
  bool signedIn = true,
  bool empty = false,
}) {
  final companyRepo = FakeCompanyRepository(ctx ?? fakeContext(), empty: empty);
  final user = signedIn
      ? const User(
          id: 'u1',
          appMetadata: {'provider': 'email'},
          userMetadata: {},
          aud: 'a',
          createdAt: '2026-01-01',
          email: 'alice@acme.com',
        )
      : null;
  return MultiProvider(
    providers: [
      Provider<CompanyRepository>.value(value: companyRepo),
      Provider<InsightsRepository>.value(
        value: FakeInsightsRepository(empty: empty),
      ),
      ChangeNotifierProvider(
        create: (_) => PlatformAdminController(companyRepo),
      ),
      Provider.value(value: PreferencesService(prefs)),
      Provider.value(value: PlatformChannelService()),
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider<AttendanceProvider>(
        create: (_) => FakeAttendance(),
      ),
      ChangeNotifierProvider<ActivityTrackingProvider>(
        create: (_) => FakeActivityTracking(),
      ),
      ChangeNotifierProvider(
        create: (_) => AuthProvider(FakeAuthService(user)),
      ),
      ChangeNotifierProxyProvider<AuthProvider, CompanyProvider>(
        create: (_) => CompanyProvider(companyRepo),
        update: (_, auth, c) =>
            c!..onUserChanged(auth.isAuthenticated ? auth.userId : null),
      ),
    ],
    child: Consumer<ThemeController>(
      builder: (context, t, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: t.mode,
        builder: t.applyMotion,
        home: page,
      ),
    ),
  );
}

Widget fakeShell(Widget child, {int index = NavIndex.dashboard}) => AppShell(
  destinations: const [
    ShellDestination(
      index: NavIndex.dashboard,
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
      label: 'Dashboard',
    ),
    ShellDestination(
      index: NavIndex.activity,
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      label: 'My activity',
    ),
    ShellDestination(
      index: NavIndex.timesheet,
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
      label: 'Timesheet',
    ),
    ShellDestination(
      index: NavIndex.team,
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups_rounded,
      label: 'Team',
      section: 'Admin',
    ),
    ShellDestination(
      index: NavIndex.platformAdmin,
      icon: Icons.admin_panel_settings_outlined,
      selectedIcon: Icons.admin_panel_settings_rounded,
      label: 'Platform',
      section: 'Admin',
      primary: false,
      badge: 2,
    ),
    ShellDestination(
      index: NavIndex.settings,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: 'Settings',
      section: 'Account',
      primary: false,
    ),
  ],
  selectedIndex: index,
  onSelect: (_) {},
  child: child,
);
