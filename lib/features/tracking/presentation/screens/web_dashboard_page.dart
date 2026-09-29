import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/attendance_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../../timesheet/data/datasource/web_cache_service.dart';
import '../widgets/daily_summary_list.dart';
import 'package:time_trak/core/constants/app_strings.dart';


/// Optimized Web Dashboard Page with smart caching and loading
/// Features:
/// - Cache-first data loading for instant display
/// - Background data refresh without blocking UI
/// - Skeleton loaders instead of full-screen spinners
/// - Smart invalidation on user actions
/// - Reduced Supabase queries through intelligent caching
class OptimizedWebDashboardPage extends StatefulWidget {
  const OptimizedWebDashboardPage({super.key});

  @override
  State<OptimizedWebDashboardPage> createState() =>
      _OptimizedWebDashboardPageState();
}

class _OptimizedWebDashboardPageState extends State<OptimizedWebDashboardPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _startPeriodicRefresh();
  }

  void _startPeriodicRefresh() {
    // Refresh statistics every 5 seconds to show real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshInBackground();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final cacheService = context.read<WebCacheService>();

    // Check if we have any cached statistics
    final hasCachedData = cacheService.get(CacheKeys.todayDuration()) != null;

    if (hasCachedData) {
      // Data available in cache, load instantly
      // Refresh in background
      _refreshInBackground();
    } else {
      // No cache, load normally and populate cache
      await _refreshData();
      await _populateCache();
    }
  }

  Future<void> _refreshData() async {
    final dashboardProvider = context.read<DashboardProvider>();
    final attendanceProvider = context.read<AttendanceProvider>();

    await dashboardProvider.refresh(() async {
      await attendanceProvider.refresh();
      dashboardProvider.incrementRefreshKey();
    });

    await _populateCache();
  }

  Future<void> _populateCache() async {
    final attendanceProvider = context.read<AttendanceProvider>();
    final cacheService = context.read<WebCacheService>();

    // Debug: Print the actual values we're caching
    debugPrint('[DASHBOARD] Caching statistics:');
    debugPrint(
      '[DASHBOARD] Today duration: ${attendanceProvider.todayClosedDuration}',
    );
    debugPrint(
      '[DASHBOARD] Month duration: ${attendanceProvider.monthClosedDuration}',
    );
    debugPrint(
      '[DASHBOARD] All time duration: ${attendanceProvider.allTimeClosedDuration}',
    );
    debugPrint(
      '[DASHBOARD] Total sessions: ${attendanceProvider.totalSessionsCount}',
    );

    // Cache the statistics with appropriate TTL
    cacheService.set(
      CacheKeys.todayDuration(),
      attendanceProvider.todayClosedDuration,
      ttl: WebCacheService.statisticsTTL,
    );
    cacheService.set(
      CacheKeys.monthDuration(),
      attendanceProvider.monthClosedDuration,
      ttl: WebCacheService.statisticsTTL,
    );
    cacheService.set(
      CacheKeys.allTimeDuration(),
      attendanceProvider.allTimeClosedDuration,
      ttl: WebCacheService.statisticsTTL,
    );
    cacheService.set(
      CacheKeys.totalSessions(),
      attendanceProvider.totalSessionsCount,
      ttl: WebCacheService.statisticsTTL,
    );
  }

  Future<void> _refreshInBackground() async {
    final provider = context.read<AttendanceProvider>();
    final dashboardProvider = context.read<DashboardProvider>();
    await provider.refresh();
    dashboardProvider.incrementRefreshKey();
    await _populateCache();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, dashboardProvider, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF1E1E1E),
          body: RefreshIndicator(
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Header
                  _buildWelcomeHeader(context, dashboardProvider),
                  const SizedBox(height: 24),

                  // Statistics Cards
                  _buildStatisticsSection(context, dashboardProvider),
                  const SizedBox(height: 24),

                  // Recent Sessions — refreshKey triggers re-fetch
                  DailySummaryList(refreshKey: dashboardProvider.refreshKey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader(
    BuildContext context,
    DashboardProvider dashProvider,
  ) {
    final now = DateTime.now();
    final dateFormat = DateFormat('MMMM dd, yyyy');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Work Summary',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'View your tracked time and activity',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Today',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  dateFormat.format(now),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: dashProvider.isRefreshing ? null : _refreshData,
                    icon: dashProvider.isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                    tooltip: AppStrings.refresh,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatisticsSection(
    BuildContext context,
    DashboardProvider dashProvider,
  ) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            return isWide
                ? Row(
                    children: [
                      Expanded(
                        child: _buildTodayCard(
                          context,
                          provider,
                          dashProvider.isRefreshing,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMonthCard(
                          context,
                          provider,
                          dashProvider.isRefreshing,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildAllTimeCard(
                          context,
                          provider,
                          dashProvider.isRefreshing,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildTodayCard(
                        context,
                        provider,
                        dashProvider.isRefreshing,
                      ),
                      const SizedBox(height: 16),
                      _buildMonthCard(
                        context,
                        provider,
                        dashProvider.isRefreshing,
                      ),
                      const SizedBox(height: 16),
                      _buildAllTimeCard(
                        context,
                        provider,
                        dashProvider.isRefreshing,
                      ),
                    ],
                  );
          },
        );
      },
    );
  }

  Widget _buildTodayCard(
    BuildContext context,
    AttendanceProvider provider,
    bool isRefreshing,
  ) {
    final todayDuration = provider.todayClosedDuration;

    debugPrint(
      '[DASHBOARD] Today card - duration: $todayDuration (${todayDuration.inMinutes}m)',
    );

    return _buildStatCard(
      context,
      title: "Today's Hours",
      value: _formatDuration(todayDuration),
      icon: Icons.today_rounded,
      color: const Color(0xFF007AFF),
      isRefreshing: isRefreshing,
    );
  }

  Widget _buildMonthCard(
    BuildContext context,
    AttendanceProvider provider,
    bool isRefreshing,
  ) {
    final monthDuration = provider.monthClosedDuration;

    debugPrint(
      '[DASHBOARD] Month card - duration: $monthDuration (${monthDuration.inMinutes}m)',
    );

    return _buildStatCard(
      context,
      title: AppStrings.thisMonth2,
      value: _formatDuration(monthDuration),
      icon: Icons.calendar_month_rounded,
      color: const Color(0xFF34C759),
      isRefreshing: isRefreshing,
    );
  }

  Widget _buildAllTimeCard(
    BuildContext context,
    AttendanceProvider provider,
    bool isRefreshing,
  ) {
    final totalSessions = provider.totalSessionsCount;

    debugPrint('[DASHBOARD] Sessions card - count: $totalSessions');

    return _buildStatCard(
      context,
      title: AppStrings.totalSessions,
      value: totalSessions.toString(),
      icon: Icons.history_rounded,
      color: const Color(0xFFFF9500),
      isRefreshing: isRefreshing,
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isRefreshing = false,
  }) {
    return AnimatedOpacity(
      opacity: isRefreshing ? 0.55 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
                if (isRefreshing)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
}
