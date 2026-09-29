import 'package:flutter/material.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/company/data/models/company.dart';

import 'request_card.dart';

class Requests extends StatelessWidget {
  final List<CompanyOverview> pending;
  final Future<void> Function() onRefresh;
  final ValueChanged<CompanyOverview> onApprove;
  final ValueChanged<CompanyOverview> onReject;
  final ValueChanged<CompanyOverview> onDelete;

  const Requests({
    super.key,
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
                  RequestCard(
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
