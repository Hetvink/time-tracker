import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/charts.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'company_avatar.dart';

import '../platform_admin_page.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class Overview extends StatelessWidget {
  final PlatformStats stats;
  final List<CompanyOverview> companies;
  final ValueChanged<CompanyOverview> onOpen;
  final VoidCallback onShowRequests;
  final Future<void> Function() onRefresh;

  const Overview({
    super.key,
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
            label: AppStrings.companies,
            numeric: s.companiesTotal.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.domain_rounded,
            color: AppColors.primary,
            caption: '${s.companiesApproved} active',
          ),
          KpiCard(
            label: AppStrings.pendingRequests,
            numeric: s.companiesPending.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.inbox_rounded,
            color: AppColors.warning,
            onTap: onShowRequests,
          ),
          KpiCard(
            label: AppStrings.users,
            numeric: s.usersTotal.toDouble(),
            format: (v) => '${v.round()}',
            icon: Icons.people_alt_rounded,
            color: AppColors.violet,
            caption: '${s.usersWithoutCompany} without a company',
          ),
          KpiCard(
            label: AppStrings.workingNow,
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
          title: AppStrings.companiesByStatus,
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
                  label: AppStrings.usersInACompany,
                  trailing: '$assigned / ${s.usersTotal}',
                  fraction: s.usersTotal == 0 ? 0 : assigned / s.usersTotal,
                  color: AppColors.violet,
                ),
              ],
            ),
          ),
        ),
        secondary: AppCard(
          title: AppStrings.largestCompanies,
          subtitle: AppStrings.membersPerCompany,
          icon: Icons.bar_chart_rounded,
          child: bySize.isEmpty
              ? const SizedBox(
                  height: 200,
                  child: EmptyState(
                    icon: Icons.domain_disabled_rounded,
                    title: AppStrings.noActiveCompanies,
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
          title: AppStrings.workingRightNow,
          subtitle: AppStrings.liveMembersPerCompany,
          icon: Icons.sensors_rounded,
          actions: [
            if (s.workingNow > 0) const PulseDot(color: AppColors.success),
          ],
          child: byWorking.every((c) => c.workingNow == 0)
              ? const SizedBox(
                  height: 160,
                  child: EmptyState(
                    icon: Icons.nights_stay_rounded,
                    title: AppStrings.nobodyIsWorkingRightNow,
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
          title: AppStrings.recentRegistrations,
          icon: Icons.fiber_new_rounded,
          bodyPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              for (final c in recent.take(6))
                ListTile(
                  onTap: () => onOpen(c),
                  leading: CompanyAvatar(name: c.company.name),
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
