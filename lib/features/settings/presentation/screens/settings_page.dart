import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_env.dart';
import '../../../../core/constants/platform_config.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../../../services/app_installation_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../company/presentation/providers/company_provider.dart';
import '../../../tracking/data/datasource/platform_channel_service.dart';
import '../../../tracking/presentation/providers/attendance_provider.dart';
import '../providers/preferences_service.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends StatefulWidget {
  final PreferencesService preferencesService;
  final PlatformChannelService platformService;

  const SettingsPage({
    super.key,
    required this.preferencesService,
    required this.platformService,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _Section {
  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  const _Section(this.id, this.icon, this.title, this.body, {this.subtitle});
}

class _SettingsPageState extends State<SettingsPage> {
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

  List<_Section> _sections(SettingsProvider s) {
    final tracker = PlatformConfig.isTracker;
    final auth = context.watch<AuthProvider>();
    return [
      const _Section(
        'profile',
        Icons.person_rounded,
        'Profile',
        _ProfileCard(),
      ),
      const _Section(
        'appearance',
        Icons.palette_rounded,
        'Appearance',
        _AppearanceCard(),
        subtitle: 'Theme and motion',
      ),
      _Section(
        'goals',
        Icons.flag_rounded,
        'Goals',
        _SliderRow(
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
        _Section(
          'general',
          Icons.tune_rounded,
          'Tracker',
          Column(
            children: [
              _SwitchRow(
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
              _SwitchRow(
                title: 'Auto check-in',
                subtitle: 'Check in automatically when the app launches',
                value: s.autoCheckInEnabled,
                onChanged: _toggleAutoCheckIn,
              ),
              if (s.autoCheckInEnabled) ...[
                const Divider(height: 1),
                _SwitchRow(
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
        _Section(
          'breaks',
          Icons.bedtime_rounded,
          'Break detection',
          _SliderRow(
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
        _Section(
          'activity',
          Icons.apps_rounded,
          'Activity tracking',
          Column(
            children: [
              _SwitchRow(
                title: 'Track apps and windows',
                subtitle: 'Record active applications and window titles',
                value: s.activityTrackingEnabled,
                onChanged: _toggleActivityTracking,
              ),
              if (PlatformConfig.isMacOS) ...[
                const Divider(height: 1),
                _PermissionRow(
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
                _SliderRow(
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
        const _Section(
          'security',
          Icons.lock_rounded,
          'Security',
          _PasswordCard(),
          subtitle: 'Password',
        ),
      _Section(
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
            const _CompanyTile(),
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
      _Section(
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
        _Section(
          'danger',
          Icons.warning_amber_rounded,
          'Danger zone',
          Column(
            children: [
              _DangerRow(
                title: 'Clear all data',
                subtitle:
                    'Permanently delete attendance sessions, activity data, breaks and logs on this computer',
                icon: Icons.delete_forever_rounded,
                onTap: _clearData,
              ),
              const Divider(height: 1),
              _DangerRow(
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

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(subtitle, style: context.text.bodySmall),
                ?trailing,
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final String help;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.help,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
          Text(help, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onOpen;
  final VoidCallback onCheck;

  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onOpen,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(subtitle, style: context.text.bodySmall),
                  ],
                ),
              ),
              StatusPill(
                label: granted ? 'Granted' : 'Required',
                color: granted ? AppColors.success : AppColors.warning,
                icon: granted
                    ? Icons.check_circle_rounded
                    : Icons.warning_rounded,
              ),
            ],
          ),
          if (!granted) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: const Text('Open System Settings'),
                ),
                TextButton.icon(
                  onPressed: onCheck,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Check again'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _DangerRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: IconBadge(icon: icon, color: AppColors.danger, size: 38),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

// =============================================================================
// Cards
// =============================================================================

class _ProfileCard extends StatefulWidget {
  const _ProfileCard();

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late final _name = TextEditingController(
    text: context.read<CompanyProvider>().context?.user?.name ?? '',
  );
  final _submit = SubmitController();

  @override
  void dispose() {
    _name.dispose();
    _submit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final company = context.read<CompanyProvider>();
    final ok = await _submit.run(() async {
      if (!await auth.updateProfile(name: name)) {
        return auth.errorMessage ?? 'Could not update profile';
      }
      await company.load();
      return null;
    });
    if (!mounted) return;
    showSnack(context, ok ? 'Profile updated' : _submit.error!, error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final company = context.watch<CompanyProvider>();
    final auth = context.watch<AuthProvider>();
    final user = company.context?.user;
    final display = user?.displayName ?? auth.user?.email ?? '';
    final role = company.isSuperAdmin
        ? 'Platform admin'
        : company.isCompanyAdmin
        ? 'Company admin'
        : 'Member';

    final avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.auroraGradient,
      ),
      child: UserAvatar(name: display, imageUrl: user?.avatarUrl, radius: 36),
    );
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Display name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(
              label: role,
              color: AppColors.primary,
              icon: Icons.verified_user_rounded,
            ),
            if (company.company != null)
              StatusPill(
                label: company.company!.name,
                color: AppColors.cyan,
                icon: Icons.business_rounded,
              ),
            if (user?.createdAt != null)
              StatusPill(
                label: 'Member since ${formatDate(user!.createdAt)}',
                color: AppColors.idle,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ListenableBuilder(
            listenable: _submit,
            builder: (context, _) => GradientButton(
              label: 'Save',
              icon: Icons.check_rounded,
              loading: _submit.isBusy,
              onPressed: _save,
            ),
          ),
        ),
      ],
    );

    return context.isPhone
        ? Column(children: [avatar, const SizedBox(height: 16), form])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TiltCard(child: avatar),
              const SizedBox(width: 20),
              Expanded(child: form),
            ],
          );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const options = [
      (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
      (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
      (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdaptiveGrid(
          minItemWidth: 150,
          maxColumns: 3,
          spacing: 12,
          children: [
            for (final (mode, icon, label) in options)
              TiltCard(
                onTap: () => theme.setMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: theme.mode == mode
                          ? AppColors.primary
                          : context.colors.border,
                      width: theme.mode == mode ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      _ThemePreview(mode: mode),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color: theme.mode == mode
                                ? AppColors.primary
                                : null,
                          ),
                          const SizedBox(width: 6),
                          Text(label, style: context.text.labelLarge),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Motion',
                    style: context.text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    theme.reducedMotion
                        ? '3D tilt, spinning and drifting effects are off.'
                        : 'Hover tilt and background effects are on.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SegmentedTabs<bool>(
              items: const [(false, 'Full'), (true, 'Reduced')],
              value: theme.reducedMotion,
              onChanged: theme.setReducedMotion,
            ),
          ],
        ),
      ],
    );
  }
}

/// Miniature mock of the UI in a given theme.
class _ThemePreview extends StatelessWidget {
  final ThemeMode mode;
  const _ThemePreview({required this.mode});

  @override
  Widget build(BuildContext context) {
    Widget pane(AppColors c) => Container(
      color: c.background,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Container(
            width: 14,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: c.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: 70,
        child: switch (mode) {
          ThemeMode.light => pane(AppColors.light),
          ThemeMode.dark => pane(AppColors.dark),
          ThemeMode.system => Row(
            children: [
              Expanded(child: pane(AppColors.light)),
              Expanded(child: pane(AppColors.dark)),
            ],
          ),
        },
      ),
    );
  }
}

class _PasswordCard extends StatefulWidget {
  const _PasswordCard();

  @override
  State<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends State<_PasswordCard> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  final _submit = SubmitController();
  final _obscure = ValueNotifier(true);

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    _submit.dispose();
    _obscure.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await _submit.run(() => auth.changePassword(_pw.text));
    if (ok) {
      _pw.clear();
      _confirm.clear();
    }
    if (mounted) {
      showSnack(context, ok ? 'Password updated' : _submit.error!, error: !ok);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_submit, _obscure]),
    builder: (context, _) => _build(context, _obscure.value, _submit.isBusy),
  );

  Widget _build(BuildContext context, bool obscure, bool busy) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _pw,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () => _obscure.value = !obscure,
              ),
            ),
            validator: (v) =>
                (v?.length ?? 0) < 8 ? 'Use at least 8 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
            validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GradientButton(
              label: 'Update password',
              icon: Icons.key_rounded,
              loading: busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// Company membership row in the Account section.
class _CompanyTile extends StatelessWidget {
  const _CompanyTile();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CompanyProvider>();
    final ctx = provider.context;
    final company = ctx?.company;
    final role = ctx?.isSuperAdmin == true
        ? 'Platform admin'
        : ctx?.isCompanyAdmin == true
        ? 'Company admin'
        : 'Member';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const IconBadge(
        icon: Icons.business_rounded,
        color: AppColors.violet,
        size: 38,
      ),
      title: Text(company?.name ?? 'No company'),
      subtitle: Text(
        company == null ? role : '$role · ${company.status.label}',
      ),
      trailing: company == null || provider.isCompanyAdmin
          ? null
          : TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                if (!await confirmAction(
                  context,
                  title: 'Leave ${company.name}?',
                  message:
                      'Your admin will no longer see your tracked time and tracking stops until you join a company again.',
                  confirmLabel: 'Leave',
                  destructive: true,
                )) {
                  return;
                }
                final error = await provider.leaveCompany();
                if (error != null && context.mounted) {
                  showSnack(context, error, error: true);
                }
              },
              child: const Text('Leave'),
            ),
    );
  }
}
