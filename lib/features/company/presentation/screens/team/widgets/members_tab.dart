import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../data/models/team_member.dart';
import '../team_page.dart';
import 'member_row.dart';
import 'member_list_controller.dart';

class MembersTab extends StatelessWidget {
  final List<TeamMember> members;
  final Future<void> Function() onRefresh;
  final ValueChanged<TeamMember> onOpen;
  final Widget Function(TeamMember) menu;
  final VoidCallback? onInvite;

  const MembersTab({
    super.key,
    required this.members,
    required this.onRefresh,
    required this.onOpen,
    required this.menu,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => MemberListController(),
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final c = context.watch<MemberListController>();
    final visible = c.visible(members);
    final gutter = context.gutter;
    final showGrid = c.grid || context.isPhone;
    int count(MemberFilter f) => switch (f) {
      MemberFilter.all => members.length,
      MemberFilter.working =>
        members.where((m) => m.isWorking && !m.isOnBreak).length,
      MemberFilter.onBreak => members.where((m) => m.isOnBreak).length,
      MemberFilter.admins => members.where((m) => m.isAdmin).length,
      MemberFilter.inactive => members.where((m) => !m.isActive).length,
    };

    final toolbar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SearchField(hint: 'Search name or e-mail', onChanged: c.setQuery),
            PopupMenuButton<Sort>(
              tooltip: 'Sort',
              initialValue: c.sort,
              onSelected: c.setSort,
              itemBuilder: (_) => [
                for (final (s, l) in const [
                  (Sort.name, 'Name'),
                  (Sort.today, 'Hours today'),
                  (Sort.week, 'Hours this week'),
                  (Sort.month, 'Hours this month'),
                  (Sort.lastSeen, 'Recently active'),
                ])
                  PopupMenuItem(value: s, child: Text(l)),
              ],
              child: Chip(
                avatar: const Icon(Icons.sort_rounded, size: 16),
                label: Text(
                  'Sort: ${switch (c.sort) {
                    Sort.name => 'Name',
                    Sort.today => 'Today',
                    Sort.week => 'Week',
                    Sort.month => 'Month',
                    Sort.lastSeen => 'Recent',
                  }}',
                ),
              ),
            ),
            if (!context.isPhone)
              SegmentedTabs<bool>(
                items: const [(false, 'Table'), (true, 'Cards')],
                value: c.grid,
                onChanged: c.setGrid,
              ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in MemberFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${switch (f) {
                        MemberFilter.all => 'All',
                        MemberFilter.working => 'Working',
                        MemberFilter.onBreak => 'On break',
                        MemberFilter.admins => 'Admins',
                        MemberFilter.inactive => 'Deactivated',
                      }} · ${count(f)}',
                    ),
                    selected: c.filter == f,
                    onSelected: (_) => c.setFilter(f),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final Widget list;
    if (visible.isEmpty) {
      list = EmptyState(
        icon: Icons.person_search_rounded,
        title: members.isEmpty ? 'No members yet' : 'No matches',
        message: members.isEmpty
            ? 'Invite your team to start tracking.'
            : 'Try a different search or filter.',
        action: members.isEmpty && onInvite != null
            ? GradientButton(
                label: 'Invite members',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: onInvite,
              )
            : null,
      );
    } else if (showGrid) {
      list = AdaptiveGrid(
        minItemWidth: 260,
        spacing: 14,
        children: [
          for (final m in visible)
            MemberCard(member: m, onOpen: () => onOpen(m), menu: menu(m)),
        ],
      );
    } else {
      list = SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const MemberHeaderRow(),
            for (final m in visible) ...[
              const Divider(height: 1),
              MemberRow(member: m, onOpen: () => onOpen(m), menu: menu(m)),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
        children: [
          ContentWidth(child: toolbar),
          const SizedBox(height: 18),
          ContentWidth(child: list),
        ],
      ),
    );
  }
}

class MemberHeaderRow extends StatelessWidget {
  const MemberHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelMedium?.copyWith(
      color: context.colors.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Member', style: style)),
          Expanded(flex: 3, child: Text('Status', style: style)),
          Expanded(
            flex: 2,
            child: Text('Today', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('This week', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('This month', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
