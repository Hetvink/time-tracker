import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'core/constants/platform_config.dart';
import 'core/constants/supabase_config.dart';
import 'core/network/supabase_sync_service.dart';
import 'core/network/localhost_server_service.dart';
import 'features/auth/data/datasource/auth_service.dart';
import 'features/auth/data/repository/user_repository.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login/login_page.dart';
import 'features/company/data/repository/company_repository.dart';
import 'features/company/presentation/providers/company_provider.dart';
import 'features/company/presentation/screens/company_gate.dart';
import 'features/tracking/data/models/attendance_state.dart';
import 'features/tracking/data/datasource/database_service.dart';
import 'features/tracking/data/datasource/platform_channel_service.dart';
import 'features/tracking/data/repository/app_activity_repository.dart';
import 'features/tracking/data/repository/attendance_repository.dart';
import 'features/tracking/data/repository/synced_app_activity_repository.dart';
import 'features/tracking/data/repository/synced_attendance_repository.dart';
import 'features/tracking/data/repository/tracking_integration_service.dart';
import 'features/tracking/presentation/providers/activity_tracking_provider.dart';
import 'features/tracking/presentation/providers/attendance_provider.dart';
import 'features/tracking/presentation/providers/dashboard_provider.dart';
import 'features/tracking/presentation/providers/timer_provider.dart';
import 'features/tracking/presentation/screens/desktop_dashboard_page.dart';
import 'features/timesheet/presentation/providers/history_page_provider.dart';
import 'features/timesheet/presentation/providers/timeline_provider.dart';
import 'features/timesheet/presentation/providers/timesheet_page_provider.dart';
import 'features/timesheet/presentation/providers/timesheet_provider.dart';
import 'features/settings/presentation/providers/preferences_service.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/settings/presentation/screens/settings/settings_page.dart';
import 'services/app_installation_service.dart';
import 'routes/navigation_provider.dart';
import 'core/constants/app_env.dart';
import 'core/widgets/splash.dart';
import 'core/widgets/ui_kit.dart';
import 'routes/app_shell.dart';
import 'package:time_trak/core/constants/app_strings.dart';


void _log(String message) {
  try {
    final file = File('startup_debug.log');
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()}: $message\n',
      mode: FileMode.append,
    );
  } catch (e) {
    // Ignore logging errors in production (read-only directory)
  }
}

// Platform-specific services
LocalhostServerService? _localhostServerService;

Future<void> main() async {
  try {
    if (File('startup_debug.log').existsSync()) {
      File('startup_debug.log').deleteSync();
    }
  } catch (e) {
    // Ignore deletion errors in production
  }
  _log('App starting...');
  WidgetsFlutterBinding.ensureInitialized();
  _log('WidgetsFlutterBinding initialized');

  try {
    // Check for first run and clean persisted data if needed
    _log('Checking for first run...');
    await AppInstallationService.handleFirstRun();
    _log('First run check completed');

    // Print platform info
    PlatformConfig.printPlatformInfo();
    _log('Platform info printed');

    // Initialize Supabase
    _log('Initializing Supabase...');
    await SupabaseConfig.initialize();
    _log('Supabase initialized');

    // Initialize local database (runtime cache only)
    _log('Initializing Database...');
    final db = await DatabaseService.database;
    _log('Database initialized');

    // Initialize services
    _log('Initializing services...');
    final platformService = PlatformChannelService();
    final repository = AttendanceRepository(db);
    final activityRepository = AppActivityRepository();
    final userRepository = UserRepository(db);
    final syncService = SupabaseSyncService(db);
    final preferencesService = await PreferencesService.create();
    final authService = AuthService();
    final companyRepository = CompanyRepository(SupabaseConfig.client);

    // Initialize Window Manager
    _log('Initializing windowManager...');
    await windowManager.ensureInitialized();
    _log('windowManager initialized');

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 800),
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    _log('Waiting for window system to be ready...');
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      _log('Window system ready, showing window...');
      await windowManager.show();
      await windowManager.focus();
      _log('Window shown and focused');

      // For Windows, set preventClose to ensure window_manager doesn't override native WM_CLOSE handler
      if (Platform.isWindows) {
        try {
          await windowManager.setPreventClose(true);
          _log(
            'Windows preventClose enabled to work with native WM_CLOSE handler',
          );
        } catch (e) {
          _log('ERROR setting preventClose: $e');
        }
      }
    });

    // Platform-specific OAuth callback handling
    // All desktop platforms (macOS/Windows/Linux) use localhost server
    _localhostServerService = LocalhostServerService(authService);
    try {
      await _localhostServerService!.startServer();
      debugPrint(
        '[DESKTOP] ✅ OAuth callback server on http://localhost:${_localhostServerService!.port}',
      );
    } catch (e) {
      debugPrint(
        '[DESKTOP] ⚠️  Could not start localhost server (port may be in use): $e',
      );
      debugPrint(
        '[DESKTOP] This is usually safe - existing server will handle OAuth',
      );
      // Continue anyway - app can still function if server already running
    }

    // Restore session (check for existing login)
    _log('Restoring session...');
    Session? session;
    try {
      session = await authService.restoreSession();
      if (session != null) {
        _log('Session restored for user: ${session.user.email}');
        // We do NOT validate the session with a network call here (isSessionValid).
        // If the network is down (common after reboot), that check would fail and force logout.
        // Instead, we trust the restored session. If the token is invalid,
        // subsequent API calls will fail naturally or the auth state listener will handle it.
      } else {
        _log('No existing session found');
      }
    } catch (e) {
      debugPrint('[DESKTOP] ❌ Session restoration failed: $e');
      debugPrint('[DESKTOP] User will need to sign in again');
      // Session will be null, so user will see login screen
    }

    // Create synced repository wrappers for automatic Supabase sync
    final syncedRepository = SyncedAttendanceRepository(
      repository: repository,
      syncService: syncService,
      userRepository: userRepository,
    );

    final syncedActivityRepository = SyncedAppActivityRepository(
      syncService: syncService,
      userRepository: userRepository,
    );

    runApp(
      MultiProvider(
        providers: [
          Provider.value(value: db),
          Provider.value(value: repository),
          Provider.value(value: syncedRepository),
          Provider.value(value: activityRepository),
          Provider.value(value: syncedActivityRepository),
          Provider.value(value: userRepository),
          Provider.value(value: syncService),
          Provider.value(value: preferencesService),
          Provider.value(value: platformService),
          Provider.value(value: authService),
          Provider.value(value: companyRepository),
          // Auth Provider - must be before other providers that depend on it
          ChangeNotifierProvider(
            create: (_) =>
                AuthProvider(authService, userRepository: userRepository),
          ),
          ChangeNotifierProxyProvider<AuthProvider, CompanyProvider>(
            create: (_) => CompanyProvider(companyRepository),
            update: (_, auth, company) =>
                company!
                  ..onUserChanged(auth.isAuthenticated ? auth.userId : null),
          ),
          ChangeNotifierProvider(
            create: (_) => AttendanceProvider(
              repository: syncedRepository,
              platformService: platformService,
              preferencesService: preferencesService,
              activityRepository: syncedActivityRepository,
            ),
          ),
          ChangeNotifierProvider(
            create: (context) {
              final activityProvider = ActivityTrackingProvider(
                repository: syncedActivityRepository,
                platformService: platformService,
                attendanceRepository: repository,
                syncService: syncService,
              );
              return activityProvider;
            },
          ),
          ChangeNotifierProxyProvider<AuthProvider, NavigationProvider>(
            create: (_) => NavigationProvider(),
            update: (_, auth, nav) =>
                nav!..onUserChanged(auth.isAuthenticated ? auth.userId : null),
          ),
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(
            create: (_) => TimeSheetProvider(repository: repository),
          ),

          // New UI State Providers
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => TimeSheetPageProvider()),
          ChangeNotifierProvider(
            create: (_) =>
                HistoryPageProvider(TimeSheetProvider(repository: repository)),
          ),
          ChangeNotifierProvider(create: (_) => DashboardProvider()),
          ChangeNotifierProvider(
            create: (_) =>
                TimelineProvider(TimeSheetProvider(repository: repository)),
          ),

          ChangeNotifierProvider(create: (_) => TimerProvider()),
        ],
        child: const DesktopApp(),
      ),
    );
  } catch (e, stackTrace) {
    debugPrint('CRITICAL INITIALIZATION ERROR: $e');
    debugPrint('Stack trace: $stackTrace');
    runApp(InitializationErrorApp(error: e, stackTrace: stackTrace));
  }
}

class InitializationErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;

  const InitializationErrorApp({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to Initialize Application',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please check your internet connection and try again. If the problem persists, contact support.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$error\n\n$stackTrace',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => exit(1),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text(AppStrings.quit),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Attempt to restart (only works if run from shell wrapper usually,
                        // but gives user feedback action)
                        // In debug, hot restart is separate.
                        // For now just exit which is safe.
                        exit(0);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text(AppStrings.restart),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopApp extends StatefulWidget {
  const DesktopApp({super.key});

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  TrackingIntegrationService? _integrationService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initSystemTray();

    // Initialize integration service early using post-frame callback
    // This ensures it's ready before any auto check-in happens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeIntegrationService();
    });
    _companyRefreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _refreshCompanyContext(force: true),
    );
  }

  Timer? _companyRefreshTimer;
  DateTime _lastCompanyRefresh = DateTime.now();
  bool? _trackingAllowed;

  /// Tells the native tracker whether it may track, and checks out if the
  /// user just lost access (removed, deactivated or company suspended).
  void _syncTrackingPermission() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final company = context.read<CompanyProvider>();
    final allowed = auth.isAuthenticated && company.canTrack;
    if (allowed == _trackingAllowed) return;
    _trackingAllowed = allowed;
    context.read<PlatformChannelService>().setAuthenticationStatus(allowed);
    debugPrint('[LIFECYCLE] Tracking allowed: $allowed');

    final attendance = context.read<AttendanceProvider>();
    final active =
        attendance.state.status == AttendanceStatus.checkedIn ||
        attendance.state.status == AttendanceStatus.onBreak;
    if (!allowed && auth.isAuthenticated && company.context != null && active) {
      attendance.checkOut(EventSource.systemRecovery);
    }
  }

  /// Re-reads company status so admin changes reach running trackers.
  void _refreshCompanyContext({bool force = false}) {
    if (!mounted || !context.read<AuthProvider>().isAuthenticated) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastCompanyRefresh) < const Duration(minutes: 5)) {
      return;
    }
    _lastCompanyRefresh = now;
    context.read<CompanyProvider>().load();
  }

  /// Initialize tracking integration service as early as possible
  /// This ensures activity tracking starts correctly even during auto check-in
  void _initializeIntegrationService() {
    if (_integrationService != null) {
      debugPrint('[LIFECYCLE] Integration service already initialized');
      return;
    }

    try {
      final attendanceProvider = context.read<AttendanceProvider>();
      final activityProvider = context.read<ActivityTrackingProvider>();
      final authProvider = context.read<AuthProvider>();

      debugPrint('[LIFECYCLE] 🔧 Initializing integration service...');
      debugPrint('[LIFECYCLE] Auth status: ${authProvider.isAuthenticated}');
      debugPrint(
        '[LIFECYCLE] Attendance status: ${attendanceProvider.state.status}',
      );

      _integrationService = TrackingIntegrationService(
        attendanceProvider: attendanceProvider,
        activityProvider: activityProvider,
      );

      // Native auto check-in is allowed only for signed-in users of an
      // active company (see CompanyGate)
      final companyProvider = context.read<CompanyProvider>();
      _syncTrackingPermission();
      companyProvider.addListener(_syncTrackingPermission);
      debugPrint('[LIFECYCLE] ✅ Integration service initialized');

      // Listen to auth state changes and update native side
      authProvider.addListener(() {
        final currentAuthState = authProvider.isAuthenticated;
        _syncTrackingPermission();
        debugPrint('[LIFECYCLE] Auth status changed: $currentAuthState');

        // Clear user context on sign out
        if (!currentAuthState) {
          final repo = context.read<AttendanceRepository>();
          repo.setCurrentUserId(null);

          debugPrint('[LIFECYCLE] 🚪 User signed out - cleared user context');
        }
      });
    } catch (e, stackTrace) {
      debugPrint('[LIFECYCLE] ❌ Error initializing integration service: $e');
      debugPrint('[LIFECYCLE] Stack trace: $stackTrace');
    }
  }

  Future<void> _initSystemTray() async {
    // Initialize system tray for Windows and menu bar for macOS
    if (!Platform.isWindows && !Platform.isMacOS) {
      debugPrint('[TRAY] System tray not supported on this platform');
      return;
    }

    debugPrint('[TRAY] Initializing system tray...');
    // macOS: black template image, tinted by the system for light/dark menu
    // bars. Windows: the tray needs an .ico.
    final iconPath = Platform.isWindows
        ? 'assets/icon/tray_icon.ico'
        : 'assets/icon/tray_icon.png';

    try {
      await trayManager.setIcon(iconPath, isTemplate: Platform.isMacOS);
      debugPrint('[TRAY] ✅ Tray icon set: $iconPath');
    } catch (e) {
      debugPrint('[TRAY] ❌ Failed to set tray icon: $e');
      return;
    }

    Menu menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: AppStrings.showWindow),
        MenuItem(key: 'hide_window', label: AppStrings.hideWindow),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: AppStrings.quitTimeTrakCloseApp),
      ],
    );

    try {
      await trayManager.setContextMenu(menu);
      debugPrint('[TRAY] ✅ Context menu set');
    } catch (e) {
      debugPrint('[TRAY] ❌ Failed to set context menu: $e');
    }

    debugPrint('[TRAY] ✅ System tray initialization complete');
  }

  Future<void> _handleQuit() async {
    try {
      debugPrint('[QUIT] 🛑 User initiated quit from menu');
      final attendanceProvider = context.read<AttendanceProvider>();
      final authProvider = context.read<AuthProvider>();
      final activityProvider = context.read<ActivityTrackingProvider>();

      // Save current state immediately
      if (authProvider.isAuthenticated) {
        await attendanceProvider.saveSessionOnPause();
        await activityProvider.saveStateOnPause();
      }

      // Auto-checkout if user is checked in or on break
      if (authProvider.isAuthenticated &&
          (attendanceProvider.state.status == AttendanceStatus.checkedIn ||
              attendanceProvider.state.status == AttendanceStatus.onBreak)) {
        debugPrint('[QUIT] Active session detected, checking out...');
        await attendanceProvider.checkOut(EventSource.manualUser);
      }

      debugPrint('[QUIT] ✅ Quit handler complete - destroying window');
      // ONLY when quit is called from menu should we destroy
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (e) {
      debugPrint('[QUIT] ❌ Error during quit: $e');
      await windowManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      debugPrint('[TRAY_MENU] 👁️  Show window selected');
      windowManager.show();
    } else if (menuItem.key == 'hide_window') {
      debugPrint('[TRAY_MENU] 🪟  Hide window selected');
      windowManager.hide();
    } else if (menuItem.key == 'quit') {
      debugPrint('[TRAY_MENU] 🛑  Quit selected from tray menu');
      _handleQuit();
    }
  }

  @override
  void onWindowClose() async {
    try {
      debugPrint('[WINDOW_CLOSE] Close event received - hiding to tray');

      // Save state before hiding
      final attendanceProvider = context.read<AttendanceProvider>();
      final activityProvider = context.read<ActivityTrackingProvider>();
      await attendanceProvider.saveSessionOnPause();
      await activityProvider.saveStateOnPause();

      // Hide window instead of closing
      await windowManager.hide();
      debugPrint('[WINDOW_CLOSE] Window hidden - app continues in background');
    } catch (e) {
      debugPrint('[WINDOW_CLOSE] Error: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Integration service is now initialized in initState via post-frame callback
    // This method kept for potential future use
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final attendanceProvider = context.read<AttendanceProvider>();
    final activityProvider = context.read<ActivityTrackingProvider>();
    final authProvider = context.read<AuthProvider>();

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App is being paused - save session and activity state
        attendanceProvider.saveSessionOnPause();
        activityProvider.saveStateOnPause();
        debugPrint('[LIFECYCLE] App paused - saved state');
        break;

      case AppLifecycleState.detached:
        // App is being terminated - save state and auto-checkout
        attendanceProvider.saveSessionOnPause();
        activityProvider.saveStateOnPause();

        // Auto-checkout on app termination (power cut/force quit scenario)
        if (authProvider.isAuthenticated &&
            (attendanceProvider.state.status == AttendanceStatus.checkedIn ||
                attendanceProvider.state.status == AttendanceStatus.onBreak)) {
          attendanceProvider.checkOut(EventSource.systemRecovery);
        }
        debugPrint('[LIFECYCLE] App detached - saved state and checked out');
        break;

      case AppLifecycleState.resumed:
        // App is coming back - refresh session state
        attendanceProvider.refresh();
        _refreshCompanyContext();
        debugPrint('[LIFECYCLE] App resumed - refreshed state');
        break;

      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _companyRefreshTimer?.cancel();
    _integrationService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.timeTrakDesktop,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<ThemeController>().mode,
      builder: context.read<ThemeController>().applyMotion,
      themeAnimationDuration: const Duration(milliseconds: 350),
      home: const AuthGate(),
    );
  }
}

/// Login → company onboarding → tracker.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    // Only the first session restore shows the splash; later "loading"
    // states (signing in) keep the login form mounted.
    if (!authProvider.isInitialized) return const AppSplash();
    if (!authProvider.isAuthenticated) return const LoginPage();

    // Tracking starts only once the user belongs to an active company
    return CompanyGate(
      child: ChangeNotifierProvider(
        // One bootstrap per signed-in user
        key: ValueKey(authProvider.userId),
        create: (context) => _TrackerBootstrapController(
          user: authProvider.user!,
          userRepository: context.read<UserRepository>(),
          repository: context.read<AttendanceRepository>(),
          attendanceProvider: context.read<AttendanceProvider>(),
          syncService: context.read<SupabaseSyncService>(),
          platformService: context.read<PlatformChannelService>(),
          company: context.read<CompanyProvider>(),
        ),
        child: const _TrackerBootstrap(),
      ),
    );
  }
}

/// Prepares the local cache for the signed-in user (once per user) and
/// pulls their history from Supabase; [isReady] flips when done.
class _TrackerBootstrapController extends ChangeNotifier {
  static bool _bootEventSent = false;

  _TrackerBootstrapController({
    required User user,
    required UserRepository userRepository,
    required AttendanceRepository repository,
    required AttendanceProvider attendanceProvider,
    required SupabaseSyncService syncService,
    required PlatformChannelService platformService,
    required CompanyProvider company,
  }) {
    _prepare(
      user,
      userRepository,
      repository,
      attendanceProvider,
      syncService,
      platformService,
      company,
    );
  }

  bool _ready = false;
  bool _disposed = false;
  bool get isReady => _ready;

  Future<void> _prepare(
    User user,
    UserRepository userRepository,
    AttendanceRepository repository,
    AttendanceProvider attendanceProvider,
    SupabaseSyncService syncService,
    PlatformChannelService platformService,
    CompanyProvider company,
  ) async {
    try {
      final profile = company.context?.user;
      final localUserId = await userRepository.upsertUser(
        uuid: user.id,
        email: user.email ?? '',
        name: profile?.name,
        role: profile?.role.value ?? 'member',
      );
      repository.setCurrentUserId(localUserId);
      await userRepository.deactivateAllExcept(user.id);

      debugPrint('[Tracker] Pulling data from Supabase...');
      await syncService.pullFromSupabase();
      await attendanceProvider.refresh();

      // Offer the auto check-in prompt once per app launch
      if (!_bootEventSent) {
        _bootEventSent = true;
        platformService.triggerBootEvent();
      }
    } catch (e, stackTrace) {
      debugPrint('[Tracker] ❌ Error preparing local user: $e\n$stackTrace');
    } finally {
      _ready = true;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _TrackerBootstrap extends StatelessWidget {
  const _TrackerBootstrap();

  @override
  Widget build(BuildContext context) {
    final ready = context.select<_TrackerBootstrapController, bool>(
      (c) => c.isReady,
    );
    if (!ready) return const AppSplash(message: 'Syncing your data…');
    return const DesktopTrackingView();
  }
}

// Desktop UI - shows full tracking interface with dashboard
class DesktopTrackingView extends StatelessWidget {
  const DesktopTrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final portalUrl = AppEnv.webAppUrl;
    return AppShell(
      destinations: const [
        ShellDestination(
          index: NavIndex.dashboard,
          icon: Icons.timer_outlined,
          selectedIcon: Icons.timer_rounded,
          label: AppStrings.tracker,
        ),
        ShellDestination(
          index: NavIndex.desktopSettings,
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: AppStrings.settings,
          section: 'Account',
        ),
      ],
      links: [
        // Reports, team and timesheets live in the web portal
        if (portalUrl.isNotEmpty)
          ShellLink(
            Icons.public_rounded,
            'Web portal',
            () => launchUrl(Uri.parse(portalUrl)),
          ),
      ],
      selectedIndex: navProvider.selectedIndex,
      onSelect: navProvider.selectIndex,
      child: navProvider.selectedIndex == NavIndex.desktopSettings
          ? SettingsPage(
              preferencesService: context.read<PreferencesService>(),
              platformService: context.read<PlatformChannelService>(),
            )
          : const DesktopDashboardPage(),
    );
  }
}
