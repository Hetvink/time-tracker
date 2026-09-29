import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'sort.dart';
import 'company_list_controller.dart';
import 'company_row.dart';

import '../platform_admin_page.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class Companies extends StatelessWidget {
  final List<CompanyOverview> companies;
  final Future<void> Function() onRefresh;
  final ValueChanged<CompanyOverview> onOpen;
  final ValueChanged<CompanyOverview> onApprove;
  final ValueChanged<CompanyOverview> onReject;
  final void Function(CompanyOverview, bool) onSuspend;
  final ValueChanged<CompanyOverview> onDelete;

  const Companies({
    super.key,
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
    create: (_) => CompanyListController(),
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final list = context.watch<CompanyListController>();
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
          PlatformAdminSort.newest =>
            (a, b) => (b.company.createdAt ?? DateTime(0)).compareTo(
              a.company.createdAt ?? DateTime(0),
            ),
          PlatformAdminSort.name =>
            (a, b) => a.company.name.toLowerCase().compareTo(
              b.company.name.toLowerCase(),
            ),
          PlatformAdminSort.members => (a, b) => b.memberCount.compareTo(
            a.memberCount,
          ),
          PlatformAdminSort.working => (a, b) => b.workingNow.compareTo(
            a.workingNow,
          ),
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
                SegmentedTabs<PlatformAdminSort>(
                  items: const [
                    (PlatformAdminSort.newest, 'Newest'),
                    (PlatformAdminSort.name, 'A–Z'),
                    (PlatformAdminSort.members, 'Largest'),
                    (PlatformAdminSort.working, 'Most active'),
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
                    title: AppStrings.noCompaniesFound,
                  )
                : SurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          CompanyRow(
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
