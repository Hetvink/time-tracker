import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_env.dart';
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../routes/navigation_provider.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../company/data/models/company.dart';
import '../../company/data/models/team_member.dart';
import '../../company/data/repository/company_repository.dart';
import '../../company/presentation/providers/company_provider.dart';
import '../../insights/data/insights.dart';
import '../../insights/data/insights_repository.dart';
import 'home_controller.dart';
import '../../insights/presentation/insight_cards.dart';
import '../../settings/presentation/providers/settings_provider.dart';

/// At-a-glance home: live status, today vs goal, this week, apps, sessions,
/// plus team / platform snapshots for admins. State lives in [HomeController].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AuthProvider, String?>((a) => a.userId);
    final company = context.watch<CompanyProvider>();
    if (userId == null) return const SizedBox.shrink();
    final companyId = company.isCompanyAdmin ? company.company?.id : null;
    return ChangeNotifierProvider(
      // New controller when the user or their admin scope changes.
      key: ValueKey('$userId|$companyId|${company.isSuperAdmin}'),
      create: (context) => HomeController(
        insightsRepository: context.read<InsightsRepository>(),
        companyRepository: context.read<CompanyRepository>(),
        userId: userId,
        companyId: companyId,
        platformAdmin: company.isSuperAdmin,
      ),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HomeController>();
    final company = context.watch<CompanyProvider>();
    final auth = context.watch<AuthProvider>();
    final name =
        company.context?.user?.displayName ??
        auth.user?.email?.split('@').first ??
        '';
    final goal = Duration(
      minutes: context.watch<SettingsProvider>().dailyGoalMinutes,
    );
    final i = c.insights;
    final loading = i == null && c.error == null;

    return AppPage(
      eyebrow: DateFormat('EEEE, d MMMM').format(DateTime.now()),
      title:
          '${greeting()}${name.isEmpty ? '' : ', ${name.split(' ').first}'} 👋',
      subtitle: 'Here is how your day is going.',
      onRefresh: c.refresh,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: c.isLoading ? null : c.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        FilledButton.icon(
          onPressed: () =>
              context.read<NavigationProvider>().selectIndex(NavIndex.activity),
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Full analytics'),
        ),
      ],
      children: [
        if (c.error != null)
          ErrorState(error: c.error, onRetry: c.refresh)
        else ...[
          _Hero(insights: i, goal: goal),
          _KpiRow(insights: i, goal: goal, loading: loading),
          if (i != null && i.sessions.isEmpty) const _GetStartedCard(),
          if (i != null) ...[
            SplitPanes(
              primary: _WeekCard(insights: i, goal: goal),
              secondary: HabitsCard(insights: i, goal: goal),
            ),
            if (company.isCompanyAdmin) _TeamPulseCard(members: c.team),
            if (company.isSuperAdmin)
              _PlatformSnapshotCard(stats: c.platformStats),
            SplitPanes(
              primary: AppUsageCard(insights: _today(i), title: 'Apps today'),
              secondary: SessionsCard(
                insights: i,
                limit: 5,
                title: 'Recent sessions',
              ),
            ),
          ] else
            const SkeletonCard(height: 300),
        ],
      ],
    );
  }

  static Insights _today(Insights i) {
    final today = DateUtils.dateOnly(DateTime.now());
    return Insights(
      from: today,
      to: today.add(const Duration(days: 1)),
      sessions: i.sessions,
      activities: i.activities,
      computedAt: i.computedAt,
    );
  }
}

// -----------------------------------------------------------------------------
// Hero
// -----------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  final Insights? insights;
  final Duration goal;
  const _Hero({required this.insights, required this.goal});

  @override
  Widget build(BuildContext context) {
    // Only the hero ticks each second while a session is live.
    return Ticking(active: insights?.liveSession != null, builder: _buildHero);
  }

  Widget _buildHero(BuildContext context) {
    final i = insights;
    final today = DateUtils.dateOnly(DateTime.now());
    final live = i?.liveSession;
    final onBreak = live?.onBreak ?? false;

    // Today's work, advanced live while a session runs.
    var worked = i?.daily[today] ?? Duration.zero;
    if (live != null && !onBreak) {
      worked += DateTime.now().difference(i!.computedAt);
    }
    final progress = goal.inSeconds == 0
        ? 0.0
        : worked.inSeconds / goal.inSeconds;
    final remaining = goal - worked;

    final (statusLabel, statusColor, statusDetail) = switch ((live, onBreak)) {
      (null, _) => (
        'Not tracking',
        AppColors.idle,
        'Start the desktop tracker to record time.',
      ),
      (_, true) => (
        'On a break',
        AppColors.warning,
        'Break since ${formatTime(live!.breaks.last.start)}',
      ),
      _ => (
        'Working now',
        AppColors.success,
        'Session started at ${formatTime(live!.start)}',
      ),
    };

    final ring = ProgressRing(
      progress: progress,
      size: context.isPhone ? 132 : 164,
      stroke: 14,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(progress * 100).clamp(0, 999).round()}%',
            style: context.text.headlineLarge?.copyWith(color: Colors.white),
          ),
          Text(
            'of ${formatHm(goal)}',
            style: context.text.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live != null)
                PulseDot(color: statusColor)
              else
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.pause_circle_filled_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: context.text.labelMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Worked today',
          style: context.text.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            i == null ? '--:--:--' : formatClock(worked),
            style: context.text.displayLarge?.copyWith(
              color: Colors.white,
              fontSize: context.isPhone ? 40 : 54,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          statusDetail,
          style: context.text.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _HeroChip(
              icon: Icons.flag_rounded,
              label: remaining > Duration.zero
                  ? '${formatHm(remaining)} to goal'
                  : 'Goal reached 🎉',
            ),
            if (i != null)
              _HeroChip(
                icon: Icons.coffee_rounded,
                label:
                    '${formatHm(Insights(from: today, to: today.add(const Duration(days: 1)), sessions: i.sessions, activities: const [], computedAt: i.computedAt).breakTotal)} breaks',
              ),
            if (i != null && i.streak > 0)
              _HeroChip(
                icon: Icons.local_fire_department_rounded,
                label: '${i.streak}-day streak',
              ),
          ],
        ),
      ],
    );

    return TiltCard(
      maxTilt: 0.05,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0891B2)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -12,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Decorative rings
            const Positioned(right: -60, top: -60, child: _GlowRing(size: 240)),
            const Positioned(
              left: -40,
              bottom: -80,
              child: _GlowRing(size: 200),
            ),
            Padding(
              padding: EdgeInsets.all(context.isPhone ? 20 : 32),
              child: LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        info,
                        const SizedBox(height: 20),
                        Center(child: ring),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 24),
                      ring,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _GlowRing extends StatelessWidget {
  final double size;
  const _GlowRing({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.12),
        width: 26,
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// KPIs
// -----------------------------------------------------------------------------

class _KpiRow extends StatelessWidget {
  final Insights? insights;
  final Duration goal;
  final bool loading;
  const _KpiRow({
    required this.insights,
    required this.goal,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(now.year, now.month);

    Duration sum(bool Function(DateTime d) test) => i == null
        ? Duration.zero
        : i.daily.entries
              .where((e) => test(e.key))
              .fold(Duration.zero, (a, e) => a + e.value);

    final week = sum((d) => !d.isBefore(weekStart));
    final lastWeekSameSpan = sum(
      (d) =>
          !d.isBefore(weekStart.subtract(const Duration(days: 7))) &&
          d.isBefore(today.subtract(const Duration(days: 6))),
    );
    final month = sum((d) => !d.isBefore(monthStart));
    final monthDays = i == null
        ? 0
        : i.daily.entries
              .where(
                (e) => !e.key.isBefore(monthStart) && e.value > Duration.zero,
              )
              .length;
    final weekSpark = i == null
        ? null
        : [
            for (var d = 0; d < 7; d++)
              (i.daily[weekStart.add(Duration(days: d))] ?? Duration.zero)
                      .inMinutes /
                  60,
          ];
    final delta = lastWeekSameSpan.inSeconds == 0
        ? null
        : (week.inSeconds - lastWeekSameSpan.inSeconds) /
              lastWeekSameSpan.inSeconds;
    final weekTarget = goal * math.min(5, today.weekday);

    return AdaptiveGrid(
      phoneMinItemWidth: 150,
      minItemWidth: 210,
      spacing: 14,
      children: [
        KpiCard.duration(
          label: 'This week',
          duration: week,
          icon: Icons.date_range_rounded,
          color: AppColors.primary,
          delta: delta,
          caption: 'Target so far ${formatHm(weekTarget)}',
          spark: weekSpark,
          loading: loading,
        ),
        KpiCard.duration(
          label: DateFormat('MMMM').format(now),
          duration: month,
          icon: Icons.calendar_month_rounded,
          color: AppColors.cyan,
          caption: '$monthDays working days',
          loading: loading,
        ),
        KpiCard.duration(
          label: 'Daily average',
          duration: monthDays == 0 ? Duration.zero : month ~/ monthDays,
          icon: Icons.speed_rounded,
          color: AppColors.violet,
          caption: 'Goal ${formatHm(goal)}',
          loading: loading,
        ),
        KpiCard(
          label: 'Sessions this month',
          numeric:
              (i?.sessions.where((s) => !s.start.isBefore(monthStart)).length ??
                      0)
                  .toDouble(),
          format: (v) => '${v.round()}',
          icon: Icons.layers_rounded,
          color: AppColors.success,
          caption: i == null ? null : 'Longest ${formatHm(i.longestSession)}',
          loading: loading,
        ),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  final Insights insights;
  final Duration goal;
  const _WeekCard({required this.insights, required this.goal});

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var d = 0; d < 7; d++) start.add(Duration(days: d))];
    final total = days.fold(
      Duration.zero,
      (a, d) => a + (insights.daily[d] ?? Duration.zero),
    );
    return AppCard(
      title: 'This week',
      subtitle: '${formatHm(total)} tracked · tap a day for details',
      icon: Icons.bar_chart_rounded,
      child: HoursBarChart(
        height: 240,
        goal: goal.inMinutes / 60,
        onTap: (_) =>
            context.read<NavigationProvider>().selectIndex(NavIndex.activity),
        data: [
          for (final d in days)
            BarDatum(
              DateFormat('E').format(d),
              (insights.daily[d] ?? Duration.zero).inMinutes / 60,
              tooltip:
                  '${DateFormat('d MMM').format(d)} · ${formatHm(insights.daily[d] ?? Duration.zero)}',
              highlight: d == today,
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Admin snapshots
// -----------------------------------------------------------------------------

class _TeamPulseCard extends StatelessWidget {
  /// Null while loading.
  final List<TeamMember>? members;
  const _TeamPulseCard({required this.members});

  @override
  Widget build(BuildContext context) {
    final loaded = members != null;
    return Builder(
      builder: (context) {
        final members = this.members ?? const <TeamMember>[];
        final working = members
            .where((m) => m.isWorking && !m.isOnBreak)
            .toList();
        final onBreak = members.where((m) => m.isOnBreak).length;
        final top = [...members]..sort((a, b) => b.today.compareTo(a.today));
        final teamToday = members.fold(Duration.zero, (a, m) => a + m.today);
        return AppCard(
          title: 'Team pulse',
          subtitle: loaded
              ? '${working.length} working · $onBreak on break · ${formatHm(teamToday)} today'
              : 'Loading team…',
          icon: Icons.groups_rounded,
          actions: [
            TextButton.icon(
              onPressed: () =>
                  context.read<NavigationProvider>().selectIndex(NavIndex.team),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Open team'),
            ),
          ],
          child: !loaded
              ? const Skeleton(height: 90)
              : members.isEmpty
              ? Text(
                  'No members yet — invite your team from the Team page.',
                  style: context.text.bodyMedium,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final m in [
                            ...working,
                            ...members.where((m) => !working.contains(m)),
                          ].take(14))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Tooltip(
                                message:
                                    '${m.displayName} · ${m.isOnBreak
                                        ? 'on break'
                                        : m.isWorking
                                        ? 'working'
                                        : 'offline'}',
                                child: UserAvatar(
                                  name: m.displayName,
                                  imageUrl: m.avatarUrl,
                                  radius: 20,
                                  statusColor: m.isOnBreak
                                      ? AppColors.warning
                                      : m.isWorking
                                      ? AppColors.success
                                      : AppColors.idle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final (n, m) in top.take(3).indexed)
                      ShareBar(
                        label: '${['🥇', '🥈', '🥉'][n]}  ${m.displayName}',
                        trailing: formatHm(m.today),
                        fraction: top.first.today.inSeconds == 0
                            ? 0
                            : m.today.inSeconds / top.first.today.inSeconds,
                        color: AppColors.chartAt(n),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _PlatformSnapshotCard extends StatelessWidget {
  /// Null while loading.
  final PlatformStats? stats;
  const _PlatformSnapshotCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final s = stats;
        return AppCard(
          title: 'Platform snapshot',
          icon: Icons.admin_panel_settings_rounded,
          actions: [
            TextButton.icon(
              onPressed: () => context.read<NavigationProvider>().selectIndex(
                NavIndex.platformAdmin,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Open console'),
            ),
          ],
          child: s == null
              ? const Skeleton(height: 60)
              : Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _Mini(
                      label: 'Pending requests',
                      value: '${s.companiesPending}',
                      color: AppColors.warning,
                    ),
                    _Mini(
                      label: 'Active companies',
                      value: '${s.companiesApproved}',
                      color: AppColors.primary,
                    ),
                    _Mini(
                      label: 'Users',
                      value: '${s.usersTotal}',
                      color: AppColors.violet,
                    ),
                    _Mini(
                      label: 'Working now',
                      value: '${s.workingNow}',
                      color: AppColors.success,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Mini({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: context.text.headlineMedium?.copyWith(color: color)),
      Text(label, style: context.text.bodySmall),
    ],
  );
}

class _GetStartedCard extends StatelessWidget {
  const _GetStartedCard();

  @override
  Widget build(BuildContext context) {
    final url = AppEnv.desktopDownloadUrl;
    return SurfaceCard(
      gradient: LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.14),
          AppColors.cyan.withValues(alpha: 0.08),
        ],
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const IconBadge(
            icon: Icons.desktop_mac_rounded,
            color: AppColors.primary,
            size: 52,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start tracking with the desktop app',
                  style: context.text.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Time is recorded by the Time Trak app for macOS and Windows. Install it, sign in with the same account, and your hours show up here automatically.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (url != null)
            GradientButton(
              label: 'Download tracker',
              icon: Icons.download_rounded,
              onPressed: () => launchUrl(Uri.parse(url)),
            ),
        ],
      ),
    );
  }
}
