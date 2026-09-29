import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/csv_export.dart';
import '../../../../core/widgets/charts.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../../company/data/models/company.dart';
import '../../../company/presentation/screens/team/team_page.dart';
import '../platform_admin_controller.dart';

enum _Sort { newest, name, members, working }

/// Platform owner console: overview of the whole platform, the company
/// registration queue, and every company → its admins and members → a
/// member's tracked activity.
class PlatformAdminPage extends StatelessWidget {
  const PlatformAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.read<PlatformAdminController>();
    // Land on the queue when something is waiting.
    return DefaultTabController(
      length: 3,
      initialIndex: admin.pendingCount > 0 ? 1 : 0,
      child: const _PlatformAdminView(),
    );
  }
}

class _PlatformAdminView extends StatefulWidget {
  const _PlatformAdminView();

  @override
  State<_PlatformAdminView> createState() => _PlatformAdminViewState();
}

/// Holds no data of its own: everything comes from [PlatformAdminController].
/// The State only gives the actions a context for dialogs and snackbars.
class _PlatformAdminViewState extends State<_PlatformAdminView> {
  PlatformAdminController get _admin => context.read<PlatformAdminController>();
  List<CompanyOverview> get _companies => _admin.companies;

  @override
  void initState() {
    super.initState();
    // Fresh numbers whenever the console is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _admin.load(silent: true);
    });
  }

  Future<void> _load() => _admin.load();

  void _report(String? error, String success) {
    if (mounted) showSnack(context, error ?? success, error: error != null);
  }

  Future<void> _approve(CompanyOverview c) async => _report(
    await _admin.approve(c),
    '${c.company.name} approved. ${c.creatorName ?? c.creatorEmail ?? 'The requester'} is now its admin.',
  );

  Future<void> _reject(CompanyOverview c) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.block_rounded,
          color: AppColors.danger,
          size: 32,
        ),
        title: Text('Reject ${c.company.name}?'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason (shown to the requester)',
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    _report(
      await _admin.reject(c, reason.isEmpty ? null : reason),
      '${c.company.name} rejected',
    );
  }

  Future<void> _setSuspended(CompanyOverview c, bool suspended) async {
    if (suspended &&
        !await confirmAction(
          context,
          title: 'Suspend ${c.company.name}?',
          message:
              'Members lose access and tracking stops until you reactivate the company.',
          confirmLabel: 'Suspend',
          destructive: true,
        )) {
      return;
    }
    if (!mounted) return;
    _report(
      await _admin.setSuspended(c, suspended),
      suspended
          ? '${c.company.name} suspended'
          : '${c.company.name} reactivated',
    );
  }

  Future<void> _delete(CompanyOverview c) async {
    if (!await confirmAction(
      context,
      title: 'Delete ${c.company.name}?',
      message:
          'This permanently deletes the company and its invitations. ${c.memberCount} member(s) are detached but keep their accounts and history.',
      confirmLabel: 'Delete company',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    _report(await _admin.delete(c), 'Company deleted');
  }

  void _open(CompanyOverview c) {
    if (c.company.status == CompanyStatus.pending ||
        c.company.status == CompanyStatus.rejected) {
      _showRequestDetails(c);
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TeamPage(
              company: c.company,
              platformView: true,
              extraActions: [
                StatusPill(
                  label: c.company.status.label,
                  color: companyStatusColor(c.company.status),
                  dot: true,
                ),
                if (c.company.status == CompanyStatus.approved)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _setSuspended(c, true);
                    },
                    icon: const Icon(
                      Icons.pause_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Suspend'),
                  ),
                if (c.company.status == CompanyStatus.suspended)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _setSuspended(c, false);
                    },
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Reactivate'),
                  ),
              ],
            ),
          ),
        )
        .then((_) => _load());
  }

  void _showRequestDetails(CompanyOverview c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            _RequestCard(
              overview: c,
              expanded: true,
              onApprove: () {
                Navigator.pop(ctx);
                _approve(c);
              },
              onReject: () {
                Navigator.pop(ctx);
                _reject(c);
              },
              onDelete: () {
                Navigator.pop(ctx);
                _delete(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<PlatformAdminController>();
    final gutter = context.gutter;
    final pending = admin.pending;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 8),
            child: PageHeader(
              eyebrow: 'Platform admin',
              title: 'Platform console',
              subtitle: 'Every company and user on Time Trak',
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: admin.isLoading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                OutlinedButton.icon(
                  onPressed: _companies.isEmpty ? null : _export,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter - 8),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Overview'),
                Tab(
                  child: Badge(
                    isLabelVisible: pending.isNotEmpty,
                    label: Text('${pending.length}'),
                    offset: const Offset(14, -6),
                    child: const Text('Requests'),
                  ),
                ),
                Tab(text: 'Companies (${_companies.length})'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: admin.isLoading && admin.stats == null
                ? const Center(child: CircularProgressIndicator())
                : admin.error != null && admin.stats == null
                ? ErrorState(
                    title: 'Could not load the platform',
                    error: admin.error,
                    onRetry: _load,
                  )
                : TabBarView(
                    children: [
                      _Overview(
                        stats: admin.stats!,
                        companies: _companies,
                        onOpen: _open,
                        onShowRequests: () =>
                            DefaultTabController.of(context).animateTo(1),
                        onRefresh: _load,
                      ),
                      _Requests(
                        pending: pending,
                        onRefresh: _load,
                        onApprove: _approve,
                        onReject: _reject,
                        onDelete: _delete,
                      ),
                      KeepAlivePage(
                        child: _Companies(
                          companies: _companies,
                          onRefresh: _load,
                          onOpen: _open,
                          onApprove: _approve,
                          onReject: _reject,
                          onSuspend: _setSuspended,
                          onDelete: _delete,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() => exportCsv(
    context,
    filename: 'timetrak-companies.csv',
    header: const [
      'Company',
      'Status',
      'Owner',
      'Owner e-mail',
      'Members',
      'Admins',
      'Working now',
      'Industry',
      'Size',
      'Country',
      'Created',
    ],
    rows: [
      for (final c in _companies)
        [
          c.company.name,
          c.company.status.label,
          c.creatorName,
          c.creatorEmail,
          c.memberCount,
          c.adminCount,
          c.workingNow,
          c.company.industry,
          c.company.companySize,
          c.company.country,
          c.company.createdAt?.toIso8601String(),
        ],
    ],
  );
}

Color companyStatusColor(CompanyStatus s) => switch (s) {
  CompanyStatus.pending => AppColors.warning,
  CompanyStatus.approved => AppColors.success,
  CompanyStatus.rejected => AppColors.danger,
  CompanyStatus.suspended => AppColors.idle,
};

// =============================================================================
// Overview
// =============================================================================

class _Overview extends StatelessWidget {
  final PlatformStats stats;
  final List<CompanyOverview> companies;
  final ValueChanged<CompanyOverview> onOpen;
  final VoidCallback onShowRequests;
  final Future<void> Function() onRefresh;

  const _Overview({
    required this.stats,
    required this.companies,
    required this.onOpen,
    required this.onShowRequests,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final active = companies
        .where((c) => c.company.status == CompanyStatus.approved)
        .toList();
    final bySize = [...active]
      ..sort((a, b) => b.memberCount.compareTo(a.memberCount));
    final byWorking = [...active]
      ..sort((a, b) => b.workingNow.compareTo(a.workingNow));
    final recent = [...companies]
      ..sort(
        (a, b) => (b.company.createdAt ?? DateTime(0)).compareTo(
          a.company.createdAt ?? DateTime(0),
        ),
      );
    final assigned = s.usersTotal - s.usersWithoutCompany;
    String short(String n) => n.length > 10 ? '${n.substring(0, 9)}…' : n;

    final items = <Widget>[
      if (s.companiesPending > 0)
        SurfaceCard(
          gradient: LinearGradient(
            colors: [
              AppColors.warning.withValues(alpha: 0.18),
              AppColors.warning.withValues(alpha: 0.04),
            ],
          ),
          onTap: onShowRequests,
          child: Row(
            children: [
              const IconBadge(
                icon: Icons.inbox_rounded,
                color: AppColors.warning,
                size: 46,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.companiesPending} compan${s.companiesPending == 1 ? 'y is' : 'ies are'} waiting for review',
                      style: context.text.titleMedium,
                    ),
                    Text(
                      'Approve or reject registration requests.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      AdaptiveGrid(
        phoneMinItemWidth: 150,
        minItemWidth: 190,
        spacing: 14,
        children: [
          KpiCard(
            label: 'Companies',
            numeric: s.companiesTotal.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.domain_rounded,
            color: AppColors.primary,
            caption: '${s.companiesApproved} active',
          ),
          KpiCard(
            label: 'Pending requests',
            numeric: s.companiesPending.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.inbox_rounded,
            color: AppColors.warning,
            onTap: onShowRequests,
          ),
          KpiCard(
            label: 'Users',
            numeric: s.usersTotal.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.people_alt_rounded,
            color: AppColors.violet,
            caption: '${s.usersWithoutCompany} without a company',
          ),
          KpiCard(
            label: 'Working now',
            numeric: s.workingNow.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.bolt_rounded,
            color: AppColors.success,
            caption:
                '${assigned == 0 ? 0 : (s.workingNow / assigned * 100).round()}% of assigned users',
          ),
        ],
      ),
      SplitPanes(
        primaryFlex: 2,
        secondaryFlex: 3,
        primary: AppCard(
          title: 'Companies by status',
          icon: Icons.donut_large_rounded,
          child: Center(
            child: Column(
              children: [
                DonutChart(
                  centerValue: '${s.companiesTotal}',
                  centerLabel: 'companies',
                  slices: [
                    DonutSlice(
                      'Active',
                      s.companiesApproved.toDouble(),
                      AppColors.success,
                    ),
                    DonutSlice(
                      'Pending',
                      s.companiesPending.toDouble(),
                      AppColors.warning,
                    ),
                    DonutSlice(
                      'Suspended',
                      s.companiesSuspended.toDouble(),
                      AppColors.idle,
                    ),
                    DonutSlice(
                      'Rejected',
                      s.companiesRejected.toDouble(),
                      AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    LegendDot(
                      color: AppColors.success,
                      label: 'Active ${s.companiesApproved}',
                    ),
                    LegendDot(
                      color: AppColors.warning,
                      label: 'Pending ${s.companiesPending}',
                    ),
                    LegendDot(
                      color: AppColors.idle,
                      label: 'Suspended ${s.companiesSuspended}',
                    ),
                    LegendDot(
                      color: AppColors.danger,
                      label: 'Rejected ${s.companiesRejected}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShareBar(
                  label: 'Users in a company',
                  trailing: '$assigned / ${s.usersTotal}',
                  fraction: s.usersTotal == 0 ? 0 : assigned / s.usersTotal,
                  color: AppColors.violet,
                ),
              ],
            ),
          ),
        ),
        secondary: AppCard(
          title: 'Largest companies',
          subtitle: 'Members per company',
          icon: Icons.bar_chart_rounded,
          child: bySize.isEmpty
              ? const SizedBox(
                  height: 200,
                  child: EmptyState(
                    icon: Icons.domain_disabled_rounded,
                    title: 'No active companies',
                  ),
                )
              : HoursBarChart(
                  height: 260,
                  labelEvery: 1,
                  color: AppColors.violet,
                  axisLabel: (v) => '${v.round()}',
                  onTap: (i) => onOpen(bySize[i]),
                  data: [
                    for (final c in bySize.take(10))
                      BarDatum(
                        short(c.company.name),
                        c.memberCount.toDouble(),
                        tooltip: '${c.company.name} · ${c.memberCount} members',
                      ),
                  ],
                ),
        ),
      ),
      SplitPanes(
        primary: AppCard(
          title: 'Working right now',
          subtitle: 'Live members per company',
          icon: Icons.sensors_rounded,
          actions: [
            if (s.workingNow > 0) const PulseDot(color: AppColors.success),
          ],
          child: byWorking.every((c) => c.workingNow == 0)
              ? const SizedBox(
                  height: 160,
                  child: EmptyState(
                    icon: Icons.nights_stay_rounded,
                    title: 'Nobody is working right now',
                    color: AppColors.idle,
                  ),
                )
              : Column(
                  children: [
                    for (final (i, c)
                        in byWorking
                            .where((c) => c.workingNow > 0)
                            .take(8)
                            .indexed)
                      InkWell(
                        onTap: () => onOpen(c),
                        child: ShareBar(
                          label: c.company.name,
                          trailing: '${c.workingNow} / ${c.memberCount}',
                          fraction: c.memberCount == 0
                              ? 0
                              : c.workingNow / c.memberCount,
                          color: AppColors.chartAt(i),
                        ),
                      ),
                  ],
                ),
        ),
        secondary: AppCard(
          title: 'Recent registrations',
          icon: Icons.fiber_new_rounded,
          bodyPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              for (final c in recent.take(6))
                ListTile(
                  onTap: () => onOpen(c),
                  leading: _CompanyAvatar(name: c.company.name),
                  title: Text(
                    c.company.name,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${formatRelative(c.company.createdAt)} · ${c.creatorName ?? c.creatorEmail ?? ''}',
                    style: context.text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusPill(
                    label: c.company.status.label,
                    color: companyStatusColor(c.company.status),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];

    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (context, i) => ContentWidth(child: items[i]),
      ),
    );
  }
}

class _CompanyAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _CompanyAvatar({required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = UserAvatar.colorFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, AppColors.violet, 0.6)!],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

// =============================================================================
// Requests queue
// =============================================================================

class _Requests extends StatelessWidget {
  final List<CompanyOverview> pending;
  final Future<void> Function() onRefresh;
  final ValueChanged<CompanyOverview> onApprove;
  final ValueChanged<CompanyOverview> onReject;
  final ValueChanged<CompanyOverview> onDelete;

  const _Requests({
    required this.pending,
    required this.onRefresh,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    if (pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 60),
            EmptyState(
              icon: Icons.task_alt_rounded,
              color: AppColors.success,
              title: 'Inbox zero',
              message: 'No company registrations are waiting for review.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        children: [
          ContentWidth(
            child: AdaptiveGrid(
              minItemWidth: 380,
              maxColumns: 2,
              children: [
                for (final c in pending)
                  _RequestCard(
                    overview: c,
                    onApprove: () => onApprove(c),
                    onReject: () => onReject(c),
                    onDelete: () => onDelete(c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final CompanyOverview overview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;
  final bool expanded;

  const _RequestCard({
    required this.overview,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = overview.company;
    final pending = c.status == CompanyStatus.pending;
    Widget field(IconData icon, String label, String? value) =>
        value == null || value.isEmpty
        ? const SizedBox.shrink()
        : InfoRow(icon: icon, label: label, value: value);

    return TiltCard(
      maxTilt: 0.04,
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _CompanyAvatar(name: c.name, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: context.text.titleLarge),
                      Text(
                        'Submitted ${formatRelative(c.createdAt)}',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: c.status.label,
                  color: companyStatusColor(c.status),
                  dot: pending,
                ),
              ],
            ),
            const SizedBox(height: 14),
            field(Icons.person_rounded, 'Requested by', overview.creatorName),
            field(
              Icons.alternate_email_rounded,
              'E-mail',
              overview.creatorEmail,
            ),
            field(Icons.language_rounded, 'Website', c.website),
            field(Icons.work_outline_rounded, 'Industry', c.industry),
            field(Icons.groups_2_rounded, 'Team size', c.companySize),
            field(Icons.public_rounded, 'Country', c.country),
            field(Icons.phone_rounded, 'Phone', c.phone),
            if (c.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  c.description!,
                  style: context.text.bodyMedium,
                  maxLines: expanded ? null : 4,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                ),
              ),
            ],
            if (c.rejectionReason?.isNotEmpty == true)
              field(Icons.block_rounded, 'Rejection reason', c.rejectionReason),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: pending
                  ? [
                      OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                      ),
                      GradientButton(
                        label: 'Approve',
                        icon: Icons.check_rounded,
                        onPressed: onApprove,
                      ),
                    ]
                  : [
                      OutlinedButton.icon(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Delete request'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Companies
// =============================================================================

/// Status filter, search and sort of the Companies tab.
class _CompanyListController extends ChangeNotifier {
  CompanyStatus? _filter;
  String _query = '';
  _Sort _sort = _Sort.newest;

  CompanyStatus? get filter => _filter;
  String get query => _query;
  _Sort get sort => _sort;

  void setFilter(CompanyStatus? f) {
    _filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setSort(_Sort s) {
    _sort = s;
    notifyListeners();
  }
}

class _Companies extends StatelessWidget {
  final List<CompanyOverview> companies;
  final Future<void> Function() onRefresh;
  final ValueChanged<CompanyOverview> onOpen;
  final ValueChanged<CompanyOverview> onApprove;
  final ValueChanged<CompanyOverview> onReject;
  final void Function(CompanyOverview, bool) onSuspend;
  final ValueChanged<CompanyOverview> onDelete;

  const _Companies({
    required this.companies,
    required this.onRefresh,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
    required this.onSuspend,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => _CompanyListController(),
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final list = context.watch<_CompanyListController>();
    final filter = list.filter;
    final sort = list.sort;
    final q = list.query.trim().toLowerCase();
    final visible =
        companies.where((c) {
          final matchesFilter = filter == null || c.company.status == filter;
          final matchesQuery =
              q.isEmpty ||
              c.company.name.toLowerCase().contains(q) ||
              (c.creatorEmail ?? '').toLowerCase().contains(q) ||
              (c.creatorName ?? '').toLowerCase().contains(q) ||
              (c.company.industry ?? '').toLowerCase().contains(q);
          return matchesFilter && matchesQuery;
        }).toList()..sort(switch (sort) {
          _Sort.newest =>
            (a, b) => (b.company.createdAt ?? DateTime(0)).compareTo(
              a.company.createdAt ?? DateTime(0),
            ),
          _Sort.name => (a, b) => a.company.name.toLowerCase().compareTo(
            b.company.name.toLowerCase(),
          ),
          _Sort.members => (a, b) => b.memberCount.compareTo(a.memberCount),
          _Sort.working => (a, b) => b.workingNow.compareTo(a.workingNow),
        });
    int count(CompanyStatus s) =>
        companies.where((c) => c.company.status == s).length;
    final gutter = context.gutter;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        children: [
          ContentWidth(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SearchField(
                  hint: 'Search company, owner or industry',
                  onChanged: list.setQuery,
                  width: 320,
                ),
                SegmentedTabs<_Sort>(
                  items: const [
                    (_Sort.newest, 'Newest'),
                    (_Sort.name, 'A–Z'),
                    (_Sort.members, 'Largest'),
                    (_Sort.working, 'Most active'),
                  ],
                  value: sort,
                  onChanged: list.setSort,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ContentWidth(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('All · ${companies.length}'),
                      selected: filter == null,
                      onSelected: (_) => list.setFilter(null),
                    ),
                  ),
                  for (final s in CompanyStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.circle,
                          size: 10,
                          color: companyStatusColor(s),
                        ),
                        label: Text('${s.label} · ${count(s)}'),
                        selected: filter == s,
                        onSelected: (_) => list.setFilter(s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ContentWidth(
            child: visible.isEmpty
                ? const EmptyState(
                    icon: Icons.domain_disabled_rounded,
                    title: 'No companies found',
                  )
                : SurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _CompanyRow(
                            overview: visible[i],
                            onOpen: () => onOpen(visible[i]),
                            onApprove: () => onApprove(visible[i]),
                            onReject: () => onReject(visible[i]),
                            onSuspend: (s) => onSuspend(visible[i], s),
                            onDelete: () => onDelete(visible[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompanyRow extends StatelessWidget {
  final CompanyOverview overview;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final ValueChanged<bool> onSuspend;
  final VoidCallback onDelete;

  const _CompanyRow({
    required this.overview,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
    required this.onSuspend,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = overview.company;
    final compact = context.screenWidth < 760;
    final owner = [
      overview.creatorName,
      overview.creatorEmail,
    ].whereType<String>().join(' · ');

    final menu = PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        switch (v) {
          case 'open':
            onOpen();
          case 'suspend':
            onSuspend(true);
          case 'reactivate':
            onSuspend(false);
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        if (c.status == CompanyStatus.approved)
          const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
        if (c.status == CompanyStatus.suspended)
          const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );

    final stats = Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        _Stat(
          icon: Icons.people_alt_rounded,
          value: '${overview.memberCount}',
          label: 'members',
        ),
        _Stat(
          icon: Icons.shield_rounded,
          value: '${overview.adminCount}',
          label: 'admins',
        ),
        _Stat(
          icon: Icons.bolt_rounded,
          value: '${overview.workingNow}',
          label: 'working',
          color: overview.workingNow > 0 ? AppColors.success : null,
        ),
      ],
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              c.name,
              style: context.text.titleSmall?.copyWith(fontSize: 15),
            ),
            StatusPill(
              label: c.status.label,
              color: companyStatusColor(c.status),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          [
            if (owner.isNotEmpty) owner,
            if (c.industry?.isNotEmpty == true) c.industry!,
            'since ${formatDate(c.createdAt)}',
          ].join(' · '),
          style: context.text.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final pendingActions = c.status == CompanyStatus.pending
        ? [
            TextButton(onPressed: onReject, child: const Text('Reject')),
            FilledButton(onPressed: onApprove, child: const Text('Approve')),
          ]
        : const <Widget>[];

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CompanyAvatar(name: c.name),
                      const SizedBox(width: 12),
                      Expanded(child: info),
                      menu,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: stats,
                  ),
                  if (pendingActions.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: 6, children: pendingActions),
                    ),
                ],
              )
            : Row(
                children: [
                  _CompanyAvatar(name: c.name),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: info),
                  Expanded(flex: 4, child: stats),
                  ...pendingActions.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: w,
                    ),
                  ),
                  menu,
                ],
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 4),
        Text(value, style: context.text.labelLarge?.copyWith(color: color)),
        const SizedBox(width: 3),
        Text(label, style: context.text.bodySmall),
      ],
    );
  }
}
