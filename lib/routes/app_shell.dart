import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/widgets/ui_kit.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/company/presentation/providers/company_provider.dart';
import 'navigation_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class ShellDestination {
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String section;

  /// Shown in the phone bottom bar (others go under "More").
  final bool primary;
  final int badge;

  const ShellDestination({
    required this.index,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.section = 'Workspace',
    this.primary = true,
    this.badge = 0,
  });
}

/// Extra sidebar link that is not a page (e.g. "Open web portal").
class ShellLink {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ShellLink(this.icon, this.label, this.onTap);
}

/// Responsive app chrome:
/// * desktop — collapsible sidebar + top bar
/// * tablet  — icon rail + top bar
/// * phone   — top bar + bottom navigation with a "More" sheet
class AppShell extends StatelessWidget {
  final List<ShellDestination> destinations;
  final List<ShellLink> links;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget child;

  const AppShell({
    super.key,
    required this.destinations,
    this.links = const [],
    required this.selectedIndex,
    required this.onSelect,
    required this.child,
  });

  ShellDestination? get _current =>
      destinations.where((d) => d.index == selectedIndex).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final content = _PageSwitcher(pageKey: selectedIndex, child: child);

    if (context.isPhone) {
      return _PhoneShell(shell: this, content: content);
    }

    final collapsed =
        context.isTablet || context.watch<NavigationProvider>().isCollapsed;
    // A still colour glow behind everything, showing through the glass.
    return AuroraBackground(
      animate: false,
      intensity: 0.55,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Row(
          children: [
            _Sidebar(
              shell: this,
              collapsed: collapsed,
              allowToggle: !context.isTablet,
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(title: _current?.label ?? 'Time Trak'),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Page transition
// -----------------------------------------------------------------------------

/// Quick, plain cross-fade between pages.
class _PageSwitcher extends StatelessWidget {
  final Object pageKey;
  final Widget child;
  const _PageSwitcher({required this.pageKey, required this.child});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(pageKey), child: child),
    );
  }
}

// -----------------------------------------------------------------------------
// Sidebar (desktop / tablet)
// -----------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  final AppShell shell;
  final bool collapsed;
  final bool allowToggle;

  const _Sidebar({
    required this.shell,
    required this.collapsed,
    required this.allowToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final company = context.watch<CompanyProvider>();
    final sections = <String, List<ShellDestination>>{};
    for (final d in shell.destinations) {
      sections.putIfAbsent(d.section, () => []).add(d);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: collapsed ? 84 : 272,
      child: GlassBar(
        border: Border(right: BorderSide(color: colors.border)),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand
              Padding(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 0 : 18,
                  20,
                  collapsed ? 0 : 10,
                  12,
                ),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    const BrandMark(size: 40),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Time Trak',
                              style: context.text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              company.company?.name ??
                                  (company.isSuperAdmin
                                      ? 'Platform console'
                                      : 'Workspace'),
                              style: context.text.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (allowToggle)
                        IconButton(
                          tooltip: AppStrings.collapseSidebar,
                          onPressed: context
                              .read<NavigationProvider>()
                              .toggleSidebar,
                          icon: const Icon(
                            Icons.keyboard_double_arrow_left_rounded,
                            size: 20,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (collapsed && allowToggle)
                Center(
                  child: IconButton(
                    tooltip: AppStrings.expandSidebar,
                    onPressed: context.read<NavigationProvider>().toggleSidebar,
                    icon: const Icon(
                      Icons.keyboard_double_arrow_right_rounded,
                      size: 20,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    for (final entry in sections.entries) ...[
                      if (!collapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: context.text.labelSmall?.copyWith(
                              color: colors.textSubtle,
                              letterSpacing: 1.2,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 14),
                      for (final d in entry.value)
                        _NavItem(
                          icon: d.selectedIndexMatches(shell.selectedIndex)
                              ? d.selectedIcon
                              : d.icon,
                          label: d.label,
                          badge: d.badge,
                          selected: d.selectedIndexMatches(shell.selectedIndex),
                          collapsed: collapsed,
                          onTap: () => shell.onSelect(d.index),
                        ),
                    ],
                    if (shell.links.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      for (final l in shell.links)
                        _NavItem(
                          icon: l.icon,
                          label: l.label,
                          selected: false,
                          collapsed: collapsed,
                          onTap: l.onTap,
                          trailing: Icons.open_in_new_rounded,
                        ),
                    ],
                  ],
                ),
              ),
              _UserCard(collapsed: collapsed),
            ],
          ),
        ),
      ),
    );
  }
}

extension on ShellDestination {
  bool selectedIndexMatches(int i) => index == i;
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final int badge;
  final IconData? trailing;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge = 0,
    this.trailing,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  final _hover = ValueNotifier(false);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _hover,
    builder: (context, hover, _) => _build(context, hover),
  );

  Widget _build(BuildContext context, bool hover) {
    final colors = context.colors;
    final selected = widget.selected;
    final fg = selected
        ? Colors.white
        : (hover ? colors.text : colors.textMuted);

    final item = MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.collapsed ? 0 : 12,
            vertical: 11,
          ),
          transform: Matrix4.translationValues(
            hover && !selected && !widget.collapsed ? 3 : 0,
            0,
            0,
          ),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brandGradient : null,
            color: selected
                ? null
                : (hover ? colors.surfaceHover : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Badge(
                isLabelVisible: widget.badge > 0 && widget.collapsed,
                label: Text('${widget.badge}'),
                backgroundColor: AppColors.danger,
                child: Icon(widget.icon, size: 20, color: fg),
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: context.text.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.25)
                          : AppColors.danger,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.badge}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (widget.trailing != null)
                  Icon(widget.trailing, size: 14, color: colors.textSubtle),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.collapsed
        ? Tooltip(message: widget.label, preferBelow: false, child: item)
        : item;
  }
}

class _UserCard extends StatelessWidget {
  final bool collapsed;
  const _UserCard({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthProvider>();
    final company = context.watch<CompanyProvider>();
    final user = company.context?.user;
    final name =
        user?.displayName ?? auth.user?.email?.split('@').first ?? 'You';
    final role = company.isSuperAdmin
        ? 'Platform admin'
        : company.isCompanyAdmin
        ? 'Company admin'
        : 'Member';

    final avatar = UserAvatar(name: name, imageUrl: user?.avatarUrl);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.all(collapsed ? 6 : 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: _AccountMenu(
        child: collapsed
            ? Center(child: avatar)
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          role,
                          style: context.text.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 18,
                    color: colors.textSubtle,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Popup with account details, theme choice, version and sign-out.
class _AccountMenu extends StatelessWidget {
  final Widget child;
  const _AccountMenu({required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final theme = context.watch<ThemeController>();
    return PopupMenuButton<String>(
      tooltip: AppStrings.account,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -8),
      onSelected: (v) async {
        switch (v) {
          case 'light':
            theme.setMode(ThemeMode.light);
          case 'dark':
            theme.setMode(ThemeMode.dark);
          case 'system':
            theme.setMode(ThemeMode.system);
          case 'signout':
            if (await confirmAction(
              context,
              title: AppStrings.signOut2,
              message: 'You can sign back in at any time.',
              confirmLabel: 'Sign out',
            )) {
              auth.signOut();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(auth.user?.email ?? '', style: context.text.bodySmall),
        ),
        const PopupMenuDivider(),
        for (final (mode, icon, label) in [
          (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
          (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
          (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
        ])
          PopupMenuItem(
            value: mode.name,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text('$label theme')),
                if (theme.mode == mode)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
              SizedBox(width: 12),
              Text('Sign out', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, s) => Text(
              s.hasData ? 'Time Trak v${s.data!.version}' : '',
              style: context.text.bodySmall,
            ),
          ),
        ),
      ],
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// Top bar (desktop / tablet)
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final company = context.watch<CompanyProvider>();
    return GlassBar(
      border: Border(bottom: BorderSide(color: colors.border)),
      child: Container(
        height: 64,
        padding: EdgeInsets.symmetric(horizontal: context.gutter),
        child: Row(
          children: [
            Text(
              title,
              style: context.text.titleMedium?.copyWith(
                color: colors.textMuted,
              ),
            ),
            if (company.company != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textSubtle,
                ),
              ),
              Flexible(
                child: Text(
                  company.company!.name,
                  style: context.text.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Spacer(),
            _LiveClock(),
            const SizedBox(width: 8),
            const _ThemeToggle(),
          ],
        ),
      ),
    );
  }
}

class _LiveClock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (context.screenWidth < 820) return const SizedBox.shrink();
    return StreamBuilder<DateTime>(
      stream: Stream.periodic(
        const Duration(seconds: 30),
        (_) => DateTime.now(),
      ),
      initialData: DateTime.now(),
      builder: (context, s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time_rounded,
              size: 15,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '${formatDate(s.data)} · ${formatTime(s.data)}',
              style: context.text.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return IconButton(
      tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
      onPressed: () =>
          context.read<ThemeController>().toggle(Theme.of(context).brightness),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween(begin: 0.6, end: 1.0).animate(anim),
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: Icon(
          dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(dark),
          color: dark ? AppColors.warning : AppColors.primary,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Phone
// -----------------------------------------------------------------------------

class _PhoneShell extends StatelessWidget {
  final AppShell shell;
  final Widget content;

  const _PhoneShell({required this.shell, required this.content});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = shell.destinations.where((d) => d.primary).take(4).toList();
    final more = shell.destinations.where((d) => !primary.contains(d)).toList();
    final hasMore = more.isNotEmpty || shell.links.isNotEmpty;
    final selectedPrimary = primary.indexWhere(
      (d) => d.index == shell.selectedIndex,
    );
    final company = context.watch<CompanyProvider>();
    final user = company.context?.user;
    final auth = context.watch<AuthProvider>();
    final name =
        user?.displayName ?? auth.user?.email?.split('@').first ?? 'You';

    return AuroraBackground(
      animate: false,
      intensity: 0.55,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassBar(child: SizedBox.expand()),
          titleSpacing: 16,
          title: Row(
            children: [
              const BrandMark(size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shell._current?.label ?? 'Time Trak',
                      style: context.text.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (company.company != null)
                      Text(
                        company.company!.name,
                        style: context.text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            const _ThemeToggle(),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _AccountMenu(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: UserAvatar(
                    name: name,
                    imageUrl: user?.avatarUrl,
                    radius: 16,
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: colors.border),
          ),
        ),
        body: content,
        bottomNavigationBar: GlassBar(
          border: Border(top: BorderSide(color: colors.border)),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: selectedPrimary >= 0
                ? selectedPrimary
                : primary.length,
            onDestinationSelected: (i) {
              if (i < primary.length) {
                shell.onSelect(primary[i].index);
              } else {
                _showMore(context, more);
              }
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final d in primary)
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: d.badge > 0,
                    label: Text('${d.badge}'),
                    child: Icon(d.icon),
                  ),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
              if (hasMore)
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: more.any((d) => d.badge > 0),
                    smallSize: 8,
                    child: const Icon(Icons.grid_view_rounded),
                  ),
                  selectedIcon: const Icon(Icons.grid_view_rounded),
                  label: AppStrings.more,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMore(BuildContext context, List<ShellDestination> more) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('More', style: ctx.text.headlineSmall),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final (i, d) in more.indexed)
                    _MoreTile(
                      icon: d.icon,
                      label: d.label,
                      badge: d.badge,
                      selected: d.index == shell.selectedIndex,
                      color: AppColors.chartAt(i),
                      onTap: () {
                        Navigator.pop(ctx);
                        shell.onSelect(d.index);
                      },
                    ),
                  for (final (i, l) in shell.links.indexed)
                    _MoreTile(
                      icon: l.icon,
                      label: l.label,
                      color: AppColors.chartAt(more.length + i),
                      onTap: () {
                        Navigator.pop(ctx);
                        l.onTap();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
  final int badge;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(10),
      color: selected ? AppColors.primary.withValues(alpha: 0.15) : null,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badge > 0,
            label: Text('$badge'),
            child: IconBadge(icon: icon, color: color, size: 42),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: context.text.labelMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
