import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/widgets/splash.dart';
import '../core/widgets/ui_kit.dart';
import '../infrastructure/supabase/repositories/supabase_session_repository.dart';
import '../infrastructure/supabase/repositories/supabase_activity_repository.dart';
import '../infrastructure/supabase/repositories/supabase_user_repository.dart';
import '../features/auth/data/datasource/auth_service.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/auth/presentation/screens/login/login_page.dart';
import '../features/company/data/repository/company_repository.dart';
import '../features/company/presentation/providers/company_provider.dart';
import '../features/company/presentation/screens/company_gate.dart';
import '../features/company/presentation/screens/team/team_page.dart';
import '../features/home/presentation/home/home_page.dart';
import '../features/insights/data/insights_repository.dart';
import '../features/insights/presentation/my_activity_page.dart';
import '../features/platform_admin/presentation/platform_admin_controller.dart';
import '../features/platform_admin/presentation/screens/platform_admin/platform_admin_page.dart';
import '../features/tracking/data/datasource/platform_channel_service.dart';
import '../features/tracking/data/repository/app_activity_repository.dart';
import '../features/tracking/data/repository/attendance_repository.dart';
import '../features/tracking/data/repository/web_attendance_repository.dart';
import '../features/tracking/data/repository/web_app_activity_repository.dart';
import '../features/tracking/presentation/providers/activity_tracking_provider.dart';
import '../features/tracking/presentation/providers/attendance_provider.dart';
import '../features/tracking/presentation/providers/dashboard_provider.dart';
import '../features/tracking/presentation/providers/timer_provider.dart';
import '../features/timesheet/presentation/providers/history_page_provider.dart';
import '../features/timesheet/presentation/providers/timeline_provider.dart';
import '../features/timesheet/presentation/providers/timesheet_page_provider.dart';
import '../features/timesheet/presentation/providers/timesheet_provider.dart';
import '../features/timesheet/data/datasource/web_cache_service.dart';
import '../features/timesheet/presentation/screens/timesheet_hub/timesheet_hub_page.dart';
import '../features/admin/data/repository/admin_repository.dart';
import '../features/admin/presentation/providers/impersonation_provider.dart';
import '../features/settings/presentation/providers/preferences_service.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../features/settings/presentation/screens/settings/settings_page.dart';
import '../routes/app_shell.dart';
import '../routes/navigation_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// The reporting portal shared by the web and mobile builds: personal
/// dashboard, activity and timesheets, the company Team area, and the
/// platform admin console. Desktop builds run the tracker UI in
/// `main_desktop.dart` instead.
///
/// Call after Supabase is initialised and the session restored.
void runPortalApp({
  required SupabaseClient supabaseClient,
  required AuthService authService,
  required PreferencesService preferencesService,
  String? oauthError,
  String? oauthErrorDescription,
  VoidCallback? onClearOAuthError,
}) {
  final sessionRepository = SupabaseSessionRepository(supabaseClient);
  final activityRepository = SupabaseActivityRepository(supabaseClient);
  final userRepository = SupabaseUserRepository(supabaseClient);
  final companyRepository = CompanyRepository(supabaseClient);
  final platformService = PlatformChannelService();

  // Portal reads everything from Supabase through these wrappers
  final webAttendanceRepo = WebAttendanceRepository(sessionRepository);
  final webActivityRepo = WebAppActivityRepository(activityRepository);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: sessionRepository),
        Provider.value(value: activityRepository),
        Provider<WebAttendanceRepository>.value(value: webAttendanceRepo),
        Provider<WebAppActivityRepository>.value(value: webActivityRepo),
        // For widgets written against the desktop repositories
        Provider<AttendanceRepository>.value(value: webAttendanceRepo),
        Provider<AppActivityRepository>.value(value: webActivityRepo),
        Provider.value(value: userRepository),
        Provider.value(value: companyRepository),
        Provider.value(value: authService),
        Provider.value(value: preferencesService),
        Provider.value(value: platformService),
        Provider(create: (_) => AdminRepository(supabaseClient)),
        Provider(create: (_) => InsightsRepository(supabaseClient)),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => WebCacheService()),

        ChangeNotifierProvider(
          create: (_) {
            final provider = AuthProvider(authService);
            if (oauthError != null) {
              provider.setOAuthError(oauthError, oauthErrorDescription);
            }
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, CompanyProvider>(
          create: (_) => CompanyProvider(companyRepository),
          update: (_, auth, company) =>
              company!
                ..onUserChanged(auth.isAuthenticated ? auth.userId : null),
        ),

        ChangeNotifierProvider(
          create: (_) => AttendanceProvider(
            repository: webAttendanceRepo,
            platformService: platformService,
            preferencesService: preferencesService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ActivityTrackingProvider(
            repository: webActivityRepo as dynamic,
            platformService: platformService,
            attendanceRepository: webAttendanceRepo,
          ),
        ),

        ChangeNotifierProxyProvider<AuthProvider, NavigationProvider>(
          create: (_) => NavigationProvider(),
          update: (_, auth, nav) =>
              nav!..onUserChanged(auth.isAuthenticated ? auth.userId : null),
        ),
        ChangeNotifierProvider(
          create: (_) => TimeSheetProvider(repository: webAttendanceRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadSettings(),
        ),
        ChangeNotifierProvider(create: (_) => TimeSheetPageProvider()),
        ChangeNotifierProvider(
          create: (_) => HistoryPageProvider(
            TimeSheetProvider(repository: webAttendanceRepo),
          ),
        ),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(
          create: (_) => TimelineProvider(
            TimeSheetProvider(repository: webAttendanceRepo),
          ),
        ),
        ChangeNotifierProvider(create: (_) => TimerProvider()),
        ChangeNotifierProvider(create: (_) => ImpersonationProvider()),
      ],
      child: PortalApp(onClearOAuthError: onClearOAuthError),
    ),
  );
}

class PortalApp extends StatelessWidget {
  final VoidCallback? onClearOAuthError;
  const PortalApp({super.key, this.onClearOAuthError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.timeTrak,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<ThemeController>().mode,
      builder: context.read<ThemeController>().applyMotion,
      themeAnimationDuration: const Duration(milliseconds: 350),
      home: AuthGate(onClearOAuthError: onClearOAuthError),
    );
  }
}

/// Login → company onboarding → app.
class AuthGate extends StatelessWidget {
  final VoidCallback? onClearOAuthError;
  const AuthGate({super.key, this.onClearOAuthError});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    final Widget page;
    if (authProvider.hasOAuthError) {
      page = _OAuthErrorScreen(
        authProvider: authProvider,
        onClear: onClearOAuthError,
      );
    } else if (!authProvider.isInitialized) {
      page = const AppSplash(key: ValueKey('splash'));
    } else if (!authProvider.isAuthenticated) {
      page = const LoginPage(key: ValueKey('login'));
    } else {
      page = const CompanyGate(key: ValueKey('app'), child: PortalView());
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: page,
    );
  }
}

class _OAuthErrorScreen extends StatelessWidget {
  final AuthProvider authProvider;
  final VoidCallback? onClear;
  const _OAuthErrorScreen({required this.authProvider, this.onClear});

  @override
  Widget build(BuildContext context) {
    final error = authProvider.oauthError;
    final description = authProvider.oauthErrorDescription;

    var title = 'Authentication failed';
    var message = description ?? 'An unknown error occurred during sign-in.';
    var icon = Icons.error_outline_rounded;
    Color color = AppColors.danger;

    if (error == 'access_denied') {
      title = 'Access denied';
      message =
          'You cancelled the sign-in or denied access to your Google account.';
      icon = Icons.cancel_outlined;
      color = AppColors.warning;
    } else if (description?.contains('redirect_uri') ?? false) {
      title = 'Configuration error';
      message =
          'The OAuth redirect URL is not allowed. Add this site to Supabase → Auth → URL Configuration.\n\n$description';
      icon = Icons.settings_outlined;
      color = AppColors.warning;
    }

    return NoticeScreen(
      icon: icon,
      color: color,
      title: title,
      message: message,
      actions: [
        GradientButton(
          label: AppStrings.backToSignIn,
          icon: Icons.arrow_back_rounded,
          onPressed: () {
            authProvider.clearError();
            onClear?.call();
          },
        ),
      ],
    );
  }
}

/// Signed-in portal: navigation shell + pages.
class PortalView extends StatelessWidget {
  const PortalView({super.key});

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = context.select<CompanyProvider, bool>(
      (c) => c.isSuperAdmin,
    );
    if (!isSuperAdmin) return const _PortalShell();
    // Platform admins: one app-scoped controller feeds both the console and
    // the "pending requests" badge.
    return ChangeNotifierProvider(
      create: (context) =>
          PlatformAdminController(context.read<CompanyRepository>()),
      child: const _PortalShell(),
    );
  }
}

class _PortalShell extends StatelessWidget {
  const _PortalShell();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final company = context.watch<CompanyProvider>();
    final hasCompany = company.company != null;
    final pendingCompanies =
        context.watch<PlatformAdminController?>()?.pendingCount ?? 0;

    final destinations = [
      const ShellDestination(
        index: NavIndex.dashboard,
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        label: AppStrings.dashboard,
      ),
      if (hasCompany || company.isSuperAdmin) ...[
        const ShellDestination(
          index: NavIndex.activity,
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights_rounded,
          label: AppStrings.myActivity,
        ),
        const ShellDestination(
          index: NavIndex.timesheet,
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month_rounded,
          label: AppStrings.timesheet,
        ),
      ],
      if (company.isCompanyAdmin)
        const ShellDestination(
          index: NavIndex.team,
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
          label: AppStrings.team,
          section: 'Admin',
        ),
      if (company.isSuperAdmin)
        ShellDestination(
          index: NavIndex.platformAdmin,
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
          label: AppStrings.platform,
          section: 'Admin',
          primary: !company.isCompanyAdmin,
          badge: pendingCompanies,
        ),
      const ShellDestination(
        index: NavIndex.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: AppStrings.settings,
        section: 'Account',
        primary: false,
      ),
    ];

    // Fall back to the dashboard if the current page is no longer allowed
    final selected = destinations.any((d) => d.index == nav.selectedIndex)
        ? nav.selectedIndex
        : NavIndex.dashboard;

    return AppShell(
      destinations: destinations,
      selectedIndex: selected,
      onSelect: nav.selectIndex,
      child: _buildContent(context, selected, company),
    );
  }

  Widget _buildContent(
    BuildContext context,
    int index,
    CompanyProvider company,
  ) {
    switch (index) {
      case NavIndex.activity:
        return const MyActivityPage();
      case NavIndex.timesheet:
        return const TimesheetHubPage();
      case NavIndex.settings:
        return SettingsPage(
          preferencesService: context.read<PreferencesService>(),
          platformService: context.read<PlatformChannelService>(),
        );
      case NavIndex.team when company.isCompanyAdmin:
        return TeamPage(
          key: ValueKey(company.company!.id),
          company: company.company!,
        );
      case NavIndex.platformAdmin when company.isSuperAdmin:
        return const PlatformAdminPage();
      default:
        return const HomePage();
    }
  }
}
