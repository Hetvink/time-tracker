import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../../core/utils/csv_export.dart';
import '../../../../../../core/widgets/ui_kit.dart';
import '../../../../../admin/presentation/screens/member_profile_page.dart';
import '../../../../../insights/data/insights.dart';
import '../../../../../insights/data/insights_repository.dart';
import '../../../../data/models/company.dart';
import '../../../../data/models/team_member.dart';
import '../../../../data/repository/company_repository.dart';
import '../team_page.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class MemberMonthRow {
  final TeamMember member;
  final Insights insights;
  const MemberMonthRow(this.member, this.insights);
}

class ReportsTab extends StatefulWidget {
  final Company company;
  final List<TeamMember> members;
  final ValueChanged<TeamMember> onOpen;

  const ReportsTab({
    super.key,
    required this.company,
    required this.members,
    required this.onOpen,
  });

  @override
  State<ReportsTab> createState() => ReportsTabState();
}

/// Report period plus the on-demand detailed monthly report.

class ReportsController extends ChangeNotifier {
  final InsightsRepository repository;
  ReportsController(this.repository);

  Period _period = Period.week;
  List<MemberMonthRow>? _detail;
  bool _loadingDetail = false;
  int _progress = 0;
  bool _disposed = false;

  Period get period => _period;
  List<MemberMonthRow>? get detail => _detail;
  bool get loadingDetail => _loadingDetail;
  int get progress => _progress;

  void setPeriod(Period p) {
    _period = p;
    _notify();
  }

  /// Loads month insights for each member, four at a time.
  /// Returns an error message or null.
  Future<String?> loadDetail(List<TeamMember> members) async {
    final now = DateTime.now();
    _loadingDetail = true;
    _progress = 0;
    _notify();
    final rows = <MemberMonthRow>[];
    try {
      for (var i = 0; i < members.length; i += 4) {
        final batch = members.skip(i).take(4).toList();
        final results = await Future.wait([
          for (final m in batch)
            repository.load(
              userId: m.id,
              from: DateTime(now.year, now.month),
              to: DateTime(now.year, now.month + 1),
              activities: false,
            ),
        ]);
        for (var j = 0; j < batch.length; j++) {
          rows.add(MemberMonthRow(batch[j], results[j]));
        }
        _progress = rows.length;
        _notify();
      }
      rows.sort((a, b) => b.insights.total.compareTo(a.insights.total));
      _detail = rows;
      return null;
    } catch (e) {
      return friendlyError(e);
    } finally {
      _loadingDetail = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ReportsTabState extends State<ReportsTab> {
  late final _reports = ReportsController(context.read<InsightsRepository>());

  Period get _period => _reports.period;
  List<MemberMonthRow>? get _detail => _reports.detail;
  bool get _loadingDetail => _reports.loadingDetail;
  int get _progress => _reports.progress;

  @override
  void dispose() {
    _reports.dispose();
    super.dispose();
  }

  Duration _value(TeamMember m) => switch (_period) {
    Period.today => m.today,
    Period.week => m.week,
    Period.month => m.month,
  };

  String get _periodLabel => switch (_period) {
    Period.today => 'today',
    Period.week => 'this week',
    Period.month => 'this month',
  };

  Future<void> _loadDetail() async {
    final error = await _reports.loadDetail(widget.members);
    if (error != null && mounted) showSnack(context, error, error: true);
  }

  Future<void> _exportSummary(List<TeamMember> sorted) => exportCsv(
    context,
    filename:
        'team-${widget.company.slug.isEmpty ? 'report' : widget.company.slug}-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
    header: const [
      'Member',
      'E-mail',
      'Role',
      'Status',
      'Today (h)',
      'This week (h)',
      'This month (h)',
      'Last seen',
    ],
    rows: [
      for (final m in sorted)
        [
          m.displayName,
          m.email,
          m.role.value,
          memberStatus(m).$1,
          (m.today.inMinutes / 60).toStringAsFixed(2),
          (m.week.inMinutes / 60).toStringAsFixed(2),
          (m.month.inMinutes / 60).toStringAsFixed(2),
          m.lastSeenAt?.toIso8601String() ?? '',
        ],
    ],
  );

  Future<void> _exportDetail() {
    String tod(TimeOfDay? t) => t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return exportCsv(
      context,
      filename:
          'team-month-${DateFormat('yyyy-MM').format(DateTime.now())}.csv',
      header: const [
        'Member',
        'E-mail',
        'Worked (h)',
        'Active days',
        'Avg per day (h)',
        'Sessions',
        'Breaks (h)',
        'Usual start',
        'Usual finish',
        'Longest session (h)',
      ],
      rows: [
        for (final r in _detail!)
          [
            r.member.displayName,
            r.member.email,
            (r.insights.total.inMinutes / 60).toStringAsFixed(2),
            r.insights.activeDays,
            (r.insights.averagePerActiveDay.inMinutes / 60).toStringAsFixed(2),
            r.insights.sessionCount,
            (r.insights.breakTotal.inMinutes / 60).toStringAsFixed(2),
            tod(r.insights.averageStartEnd.$1),
            tod(r.insights.averageStartEnd.$2),
            (r.insights.longestSession.inMinutes / 60).toStringAsFixed(2),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _reports,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final sorted = [...widget.members]
      ..sort((a, b) => _value(b).compareTo(_value(a)));
    final total = sorted.fold(Duration.zero, (a, m) => a + _value(m));
    final max = sorted.isEmpty ? Duration.zero : _value(sorted.first);
    final tracked = sorted.where((m) => _value(m) > Duration.zero).length;
    final gutter = context.gutter;

    final items = <Widget>[
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedTabs<Period>(
            items: const [
              (Period.today, 'Today'),
              (Period.week, 'This week'),
              (Period.month, 'This month'),
            ],
            value: _period,
            onChanged: _reports.setPeriod,
          ),
          OutlinedButton.icon(
            onPressed: sorted.isEmpty ? null : () => _exportSummary(sorted),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text(AppStrings.exportSummary),
          ),
        ],
      ),
      AdaptiveGrid(
        phoneMinItemWidth: 150,
        minItemWidth: 200,
        spacing: 14,
        children: [
          KpiCard.duration(
            label: 'Team total $_periodLabel',
            duration: total,
            icon: Icons.functions_rounded,
            color: AppColors.primary,
          ),
          KpiCard.duration(
            label: AppStrings.averagePerMember,
            duration: tracked == 0 ? Duration.zero : total ~/ tracked,
            icon: Icons.person_rounded,
            color: AppColors.cyan,
            caption: '$tracked of ${sorted.length} tracked',
          ),
          KpiCard(
            label: AppStrings.topPerformer,
            value: sorted.isEmpty || max == Duration.zero
                ? '—'
                : sorted.first.displayName,
            icon: Icons.emoji_events_rounded,
            color: AppColors.warning,
            caption: max == Duration.zero ? null : formatHm(max),
          ),
        ],
      ),
      AppCard(
        title: 'Ranking $_periodLabel',
        subtitle: AppStrings.tapAMemberForTheirFullAnalytics,
        icon: Icons.leaderboard_rounded,
        bodyPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            for (final (i, m) in sorted.indexed)
              InkWell(
                onTap: () => widget.onOpen(m),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          i < 3 && _value(m) > Duration.zero
                              ? ['🥇', '🥈', '🥉'][i]
                              : '${i + 1}',
                          style: context.text.titleSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      UserAvatar(
                        name: m.displayName,
                        imageUrl: m.avatarUrl,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ShareBar(
                          label: m.displayName,
                          trailing:
                              '${formatHm(_value(m))} · ${total.inSeconds == 0 ? 0 : (_value(m).inSeconds / total.inSeconds * 100).round()}%',
                          fraction: max.inSeconds == 0
                              ? 0
                              : _value(m).inSeconds / max.inSeconds,
                          color: AppColors.chartAt(i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      AppCard(
        title: AppStrings.detailedMonthlyReport,
        subtitle:
            'Active days, averages, usual hours and sessions for ${DateFormat('MMMM').format(DateTime.now())}',
        icon: Icons.analytics_rounded,
        actions: [
          if (_detail != null)
            TextButton.icon(
              onPressed: _exportDetail,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text(AppStrings.csv),
            ),
        ],
        child: _detail == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Builds a per-member breakdown from every session this month. Takes a few seconds for larger teams.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loadingDetail) ...[
                    LinearProgressIndicator(
                      value: widget.members.isEmpty
                          ? null
                          : _progress / widget.members.length,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Loaded $_progress of ${widget.members.length} members…',
                      style: context.text.bodySmall,
                    ),
                  ] else
                    GradientButton(
                      label: AppStrings.buildReport,
                      icon: Icons.auto_graph_rounded,
                      onPressed: widget.members.isEmpty ? null : _loadDetail,
                    ),
                ],
              )
            : DetailTable(rows: _detail!, onOpen: widget.onOpen),
      ),
    ];

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, gutter + 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, i) => ContentWidth(child: items[i]),
    );
  }
}

class DetailTable extends StatelessWidget {
  final List<MemberMonthRow> rows;
  final ValueChanged<TeamMember> onOpen;
  const DetailTable({super.key, required this.rows, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    String tod(TimeOfDay? t) => t == null
        ? '—'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final head = context.text.labelMedium?.copyWith(
      color: context.colors.textMuted,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: head,
        columnSpacing: 28,
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text(AppStrings.member)),
          DataColumn(label: Text(AppStrings.worked), numeric: true),
          DataColumn(label: Text(AppStrings.days), numeric: true),
          DataColumn(label: Text(AppStrings.avgDay), numeric: true),
          DataColumn(label: Text(AppStrings.sessions), numeric: true),
          DataColumn(label: Text(AppStrings.breaks), numeric: true),
          DataColumn(label: Text(AppStrings.usualHours)),
          DataColumn(label: Text(AppStrings.streak), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              onSelectChanged: (_) => onOpen(r.member),
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        name: r.member.displayName,
                        imageUrl: r.member.avatarUrl,
                        radius: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.member.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    formatHm(r.insights.total),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text('${r.insights.activeDays}')),
                DataCell(Text(formatHm(r.insights.averagePerActiveDay))),
                DataCell(Text('${r.insights.sessionCount}')),
                DataCell(Text(formatHm(r.insights.breakTotal))),
                DataCell(
                  Text(
                    '${tod(r.insights.averageStartEnd.$1)} – ${tod(r.insights.averageStartEnd.$2)}',
                  ),
                ),
                DataCell(Text('${r.insights.streak}d')),
              ],
            ),
        ],
      ),
    );
  }
}
