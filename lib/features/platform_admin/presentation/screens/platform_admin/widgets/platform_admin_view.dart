import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/utils/csv_export.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';
import 'package:time_trak/features/company/presentation/screens/team/team_page.dart';
import 'package:time_trak/features/platform_admin/presentation/platform_admin_controller.dart';

import 'overview.dart';
import 'requests.dart';
import 'request_card.dart';
import 'companies.dart';

import '../platform_admin_page.dart';

class PlatformAdminView extends StatefulWidget {
  const PlatformAdminView({super.key});

  @override
  State<PlatformAdminView> createState() => PlatformAdminViewState();
}

/// Holds no data of its own: everything comes from [PlatformAdminController].
/// The State only gives the actions a context for dialogs and snackbars.

class PlatformAdminViewState extends State<PlatformAdminView> {
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
            RequestCard(
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
                      Overview(
                        stats: admin.stats!,
                        companies: _companies,
                        onOpen: _open,
                        onShowRequests: () =>
                            DefaultTabController.of(context).animateTo(1),
                        onRefresh: _load,
                      ),
                      Requests(
                        pending: pending,
                        onRefresh: _load,
                        onApprove: _approve,
                        onReject: _reject,
                        onDelete: _delete,
                      ),
                      KeepAlivePage(
                        child: Companies(
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

// =============================================================================
// Overview
// =============================================================================
