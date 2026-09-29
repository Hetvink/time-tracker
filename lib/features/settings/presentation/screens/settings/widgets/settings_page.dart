import 'dart:io' show exit;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:time_trak/core/constants/app_env.dart';
import 'package:time_trak/core/constants/platform_config.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/services/app_installation_service.dart';
import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/features/tracking/presentation/providers/attendance_provider.dart';
import 'package:time_trak/features/settings/presentation/providers/settings_provider.dart';

import 'section.dart';
import 'switch_row.dart';
import 'slider_row.dart';
import 'permission_row.dart';
import 'danger_row.dart';
import 'profile_card.dart';
import 'appearance_card.dart';
import 'password_card.dart';
import 'company_tile.dart';

import '../settings_page.dart';

class SettingsPageState extends State<SettingsPage> {
  final _keys = <String, GlobalKey>{};
  final _scroll = ScrollController();

  /// Section highlighted in the side navigation.
  final _active = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _active.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final settings = context.read<SettingsProvider>();
    await settings.loadSettings();
    if (!PlatformConfig.isTracker) return;

    final autoStart = await widget.platformService.getAutoStartStatus();
    // Only check accessibility permission on macOS
    var accessibility = false;
    if (PlatformConfig.isMacOS) {
      accessibility = await widget.platformService
          .getAccessibilityPermissionStatus();
    }
    if (mounted) {
      settings.setAutoStartEnabledSync(autoStart);
      settings.setAccessibilityPermissionGranted(accessibility);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  SettingsProvider get _settings => context.read<SettingsProvider>();

  Future<void> _toggleAutoStart(bool value) async {
    final success = await widget.platformService.setAutoStart(value);
    if (success) _settings.setAutoStartEnabledSync(value);
  }

  Future<void> _toggleAutoCheckIn(bool value) async {
    await widget.preferencesService.setAutoCheckInEnabled(value);
    await _settings.setAutoCheckInEnabled(value);
  }

  Future<void> _toggleAutoCheckInOnBootOnly(bool value) async {
    await widget.preferencesService.setAutoCheckInOnBootOnly(value);
    await _settings.setAutoCheckInOnBootOnly(value);
  }

  Future<void> _updateSleepThreshold(double value) async {
    final minutes = value.round();
    await widget.preferencesService.setSleepThresholdMinutes(minutes);
    await widget.platformService.setSleepThreshold(minutes * 60);
    await _settings.setSleepThresholdMinutes(minutes);
  }

  Future<void> _updateDailyGoal(double value) async {
    final minutes = value.round();
    await widget.preferencesService.setDailyGoalMinutes(minutes);
    await _settings.setDailyGoalMinutes(minutes);
  }

  Future<void> _toggleActivityTracking(bool value) async {
    await widget.preferencesService.setActivityTrackingEnabled(value);
    if (value) {
      await widget.platformService.startActivityTracking();
    } else {
      await widget.platformService.stopActivityTracking();
    }
    await _settings.setActivityTrackingEnabled(value);
  }

  Future<void> _updateTrackingInterval(double value) async {
    final seconds = value.round();
    await widget.preferencesService.setTrackingIntervalSeconds(seconds);
    await widget.platformService.setTrackingInterval(seconds);
    await _settings.setTrackingIntervalSeconds(seconds);
  }

  Future<void> _refreshAccessibilityStatus() async {
    final status = await widget.platformService
        .getAccessibilityPermissionStatus();
    _settings.setAccessibilityPermissionGranted(status);
  }

  Future<void> _signOut() async {
    if (!await confirmAction(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to access your data.',
      confirmLabel: 'Sign out',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await context.read<AuthProvider>().signOut();
    } catch (e) {
      if (mounted) showSnack(context, 'Failed to sign out: $e', error: true);
    }
  }

  Future<void> _clearData() async {
    if (!await confirmAction(
      context,
      title: 'Delete all data?',
      message:
          'This cannot be undone. All attendance sessions, activity tracking data, breaks and logs on this computer will be permanently deleted.',
      confirmLabel: 'Delete everything',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    try {
      // Activity records are linked to sessions and cleaned up with them.
      await context.read<AttendanceProvider>().clearData();
      if (mounted) showSnack(context, 'All data cleared');
    } catch (e) {
      if (mounted) showSnack(context, 'Failed to clear data: $e', error: true);
    }
  }

  Future<void> _resetApp() async {
    if (!await confirmAction(
      context,
      title: 'Reset app & clear all storage?',
      message:
          'This signs you out, deletes the local database, clears all settings and cached sessions, then quits the app. You will need to sign in again. This cannot be undone.',
      confirmLabel: 'Reset everything',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final auth = context.read<AuthProvider>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Resetting app…'),
          ],
        ),
      ),
    );
    try {
      await auth.signOut();
      await AppInstallationService.forceCompleteReset();
      navigator.pop();
      if (mounted) showSnack(context, 'App reset. Quitting…');
      await Future.delayed(const Duration(seconds: 2));
      // Quitting is the safest way to guarantee a clean restart on desktop.
      exit(0);
    } catch (e) {
      navigator.pop();
      if (mounted) showSnack(context, 'Failed to reset app: $e', error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  List<Section> _sections(SettingsProvider s) {
    final tracker = PlatformConfig.isTracker;
    final auth = context.watch<AuthProvider>();
    return [
      const Section('profile', Icons.person_rounded, 'Profile', ProfileCard()),
      const Section(
        'appearance',
        Icons.palette_rounded,
        'Appearance',
        AppearanceCard(),
        subtitle: 'Theme and motion',
      ),
      Section(
        'goals',
        Icons.flag_rounded,
        'Goals',
        SliderRow(
          title: 'Daily work goal',
          value: s.dailyGoalMinutes.toDouble(),
          min: 60,
          max: 960,
          divisions: (960 - 60) ~/ 15,
          label: formatHm(Duration(minutes: s.dailyGoalMinutes)),
          help:
              'Used for progress rings, goal lines and "days at goal" across the app.',
          onChanged: _updateDailyGoal,
        ),
        subtitle: 'Your daily target',
      ),
      if (tracker) ...[
        Section(
          'general',
          Icons.tune_rounded,
          'Tracker',
          Column(
            children: [
              SwitchRow(
                title: 'Launch at login',
                subtitle: 'Start Time Trak automatically when you log in',
                value: s.autoStartEnabled,
                onChanged: _toggleAutoStart,
                trailing: TextButton(
                  onPressed: widget.platformService.openSystemPreferences,
                  child: const Text('System Settings'),
                ),
              ),
              const Divider(height: 1),
              SwitchRow(
                title: 'Auto check-in',
                subtitle: 'Check in automatically when the app launches',
                value: s.autoCheckInEnabled,
                onChanged: _toggleAutoCheckIn,
              ),
              if (s.autoCheckInEnabled) ...[
                const Divider(height: 1),
                SwitchRow(
                  title: 'Only on system boot',
                  subtitle: 'Restrict auto check-in to computer startup',
                  value: s.autoCheckInOnBootOnly,
                  onChanged: _toggleAutoCheckInOnBootOnly,
                ),
              ],
            ],
          ),
          subtitle: 'Startup and check-in',
        ),
        Section(
          'breaks',
          Icons.bedtime_rounded,
          'Break detection',
          SliderRow(
            title: 'Sleep threshold',
            value: s.sleepThresholdMinutes.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '${s.sleepThresholdMinutes} min',
            help:
                'Counts a break when the computer has been asleep for this long.',
            onChanged: _updateSleepThreshold,
          ),
        ),
        Section(
          'activity',
          Icons.apps_rounded,
          'Activity tracking',
          Column(
            children: [
              SwitchRow(
                title: 'Track apps and windows',
                subtitle: 'Record active applications and window titles',
                value: s.activityTrackingEnabled,
                onChanged: _toggleActivityTracking,
              ),
              if (PlatformConfig.isMacOS) ...[
                const Divider(height: 1),
                PermissionRow(
                  title: 'Accessibility permission',
                  subtitle: 'Required to read window titles and app usage',
                  granted: s.accessibilityPermissionGranted,
                  onOpen: () async {
                    await widget.platformService.openAccessibilityPreferences();
                    Future.delayed(
                      const Duration(seconds: 2),
                      _refreshAccessibilityStatus,
                    );
                  },
                  onCheck: _refreshAccessibilityStatus,
                ),
                const Divider(height: 1),
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                  title: Text('Automation permission'),
                  subtitle: Text(
                    'macOS asks for this automatically when needed — click "OK" when the dialog appears.',
                  ),
                  trailing: StatusPill(
                    label: 'Auto-requested',
                    color: AppColors.info,
                  ),
                ),
              ],
              if (s.activityTrackingEnabled) ...[
                const Divider(height: 1),
                SliderRow(
                  title: 'Tracking interval',
                  value: s.trackingIntervalSeconds.toDouble(),
                  min: 30,
                  max: 300,
                  divisions: 27,
                  label: s.trackingIntervalSeconds >= 60
                      ? '${(s.trackingIntervalSeconds / 60).toStringAsFixed(1)} min'
                      : '${s.trackingIntervalSeconds} sec',
                  help: 'How often to check for active window changes.',
                  onChanged: _updateTrackingInterval,
                ),
              ],
            ],
          ),
        ),
      ],
      if (auth.usesPassword)
        const Section(
          'security',
          Icons.lock_rounded,
          'Security',
          PasswordCard(),
          subtitle: 'Password',
        ),
      Section(
        'account',
        Icons.badge_rounded,
        'Account & workspace',
        Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const IconBadge(
                icon: Icons.alternate_email_rounded,
                color: AppColors.primary,
                size: 38,
              ),
              title: const Text('Signed in as'),
              subtitle: Text(auth.user?.email ?? 'Not signed in'),
              trailing: OutlinedButton.icon(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
              ),
            ),
            const Divider(height: 1),
            const CompanyTile(),
            if (tracker && AppEnv.webAppUrl.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const IconBadge(
                  icon: Icons.public_rounded,
                  color: AppColors.cyan,
                  size: 38,
                ),
                title: const Text('Open web dashboard'),
                subtitle: const Text(
                  'Reports, timesheets and team in your browser',
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrl(
                  Uri.parse(AppEnv.webAppUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ],
        ),
      ),
      Section(
        'about',
        Icons.info_rounded,
        'About',
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => Column(
            children: [
              InfoRow(
                label: 'Version',
                value: snap.hasData
                    ? '${snap.data!.version} (${snap.data!.buildNumber})'
                    : '—',
              ),
              InfoRow(
                label: 'Platform',
                value: PlatformConfig.isWeb
                    ? 'Web'
                    : PlatformConfig.isMobile
                    ? 'Mobile'
                    : PlatformConfig.isMacOS
                    ? 'macOS tracker'
                    : PlatformConfig.isWindows
                    ? 'Windows tracker'
                    : 'Desktop',
              ),
            ],
          ),
        ),
      ),
      if (tracker)
        Section(
          'danger',
          Icons.warning_amber_rounded,
          'Danger zone',
          Column(
            children: [
              DangerRow(
                title: 'Clear all data',
                subtitle:
                    'Permanently delete attendance sessions, activity data, breaks and logs on this computer',
                icon: Icons.delete_forever_rounded,
                onTap: _clearData,
              ),
              const Divider(height: 1),
              DangerRow(
                title: 'Reset app & clear all storage',
                subtitle:
                    'Clear login, settings, database and preferences. The app quits afterwards.',
                icon: Icons.restart_alt_rounded,
                onTap: _resetApp,
              ),
            ],
          ),
        ),
    ];
  }

  void _jump(String id) {
    _active.value = id;
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final sections = _sections(settings);
    final gutter = context.gutter;
    final showNav = context.screenWidth >= 1180;

    final content = ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter + 40),
      children: [
        const PageHeader(
          eyebrow: 'Preferences',
          title: 'Settings',
          subtitle: 'Personalise Time Trak and manage your account.',
        ),
        const SizedBox(height: 24),
        if (settings.isLoading) const LinearProgressIndicator(),
        for (final s in sections) ...[
          Container(
            key: _keys.putIfAbsent(s.id, GlobalKey.new),
            child: AppCard(
              title: s.title,
              subtitle: s.subtitle,
              icon: s.icon,
              child: s.body,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );

    if (!showNav) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ContentWidth(maxWidth: 820, child: content),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 230,
                child: ValueListenableBuilder<String?>(
                  valueListenable: _active,
                  builder: (context, active, _) => ListView(
                    padding: EdgeInsets.fromLTRB(gutter, 140, 0, 24),
                    children: [
                      for (final s in sections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: ListTile(
                            dense: true,
                            selected: active == s.id,
                            selectedTileColor: AppColors.primary.withValues(
                              alpha: 0.12,
                            ),
                            selectedColor: AppColors.primary,
                            leading: Icon(s.icon, size: 18),
                            title: Text(s.title),
                            onTap: () => _jump(s.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Rows
// =============================================================================
