import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'company_avatar.dart';
import 'stat.dart';

import '../platform_admin_page.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class CompanyRow extends StatelessWidget {
  final CompanyOverview overview;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final ValueChanged<bool> onSuspend;
  final VoidCallback onDelete;

  const CompanyRow({
    super.key,
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
        const PopupMenuItem(value: 'open', child: Text(AppStrings.open)),
        if (c.status == CompanyStatus.approved)
          const PopupMenuItem(value: 'suspend', child: Text(AppStrings.suspend)),
        if (c.status == CompanyStatus.suspended)
          const PopupMenuItem(value: 'reactivate', child: Text(AppStrings.reactivate)),
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
        Stat(
          icon: Icons.people_alt_rounded,
          value: '${overview.memberCount}',
          label: AppStrings.members,
        ),
        Stat(
          icon: Icons.shield_rounded,
          value: '${overview.adminCount}',
          label: AppStrings.admins,
        ),
        Stat(
          icon: Icons.bolt_rounded,
          value: '${overview.workingNow}',
          label: AppStrings.working2,
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
            TextButton(onPressed: onReject, child: const Text(AppStrings.reject)),
            FilledButton(onPressed: onApprove, child: const Text(AppStrings.approve)),
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
                      CompanyAvatar(name: c.name),
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
                  CompanyAvatar(name: c.name),
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
