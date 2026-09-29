import 'package:flutter/material.dart';
import 'package:time_trak/theme/macos_theme.dart';
import 'package:provider/provider.dart';
import '../../data/repository/admin_repository.dart';
import '../providers/admin_dashboard_provider.dart';
import '../widgets/user_activity_overview.dart';
import '../widgets/user_day_view.dart';
import '../widgets/user_month_view.dart';
import '../widgets/user_monthly_summary_dashboard.dart';

/// Main user detail page for admin panel – web-optimised layout
class UserDetailPage extends StatelessWidget {
  final Map<String, dynamic>? user;
  final String? userId;
  final String? userName;
  final AdminRepository? adminRepository;

  const UserDetailPage({
    super.key,
    this.user,
    this.userId,
    this.userName,
    this.adminRepository,
  });

  String get _effectiveUserId => userId ?? user?['id'] as String? ?? '';
  String get _effectiveUserName =>
      userName ?? user?['name'] as String? ?? 'User';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = adminRepository ?? context.read<AdminRepository>();

    // The tab widgets share date/month selection through this provider.
    return ChangeNotifierProvider(
      create: (_) =>
          AdminDashboardProvider()..setSelectedUserId(_effectiveUserId),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: repo.getUserById(_effectiveUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: MacOSTheme.darkBackground,
              appBar: _buildAppBar(context, theme, 'Loading…'),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final userProfile = snapshot.data ?? user ?? {};
          final displayName =
              userProfile['name'] as String? ?? _effectiveUserName;

          return DefaultTabController(
            length: 4,
            child: Scaffold(
              backgroundColor: MacOSTheme.darkBackground,
              appBar: _buildAppBar(context, theme, displayName),
              body: Column(
                children: [
                  _buildHeader(theme, userProfile),
                  _buildTabBar(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        UserActivityOverview(userId: _effectiveUserId),
                        UserDayView(userId: _effectiveUserId),
                        UserMonthView(userId: _effectiveUserId),
                        UserMonthlySummaryDashboard(userId: _effectiveUserId),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    String title,
  ) {
    return AppBar(
      backgroundColor: MacOSTheme.darkSidebar,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white70,
          size: 18,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Map<String, dynamic> userProfile) {
    final rawName = userProfile['name'] as String?;
    final email = userProfile['email'] as String? ?? '';
    final name = (rawName != null && rawName.trim().isNotEmpty)
        ? rawName
        : (email.isNotEmpty ? email.split('@').first : 'User');
    final role = userProfile['role'] as String? ?? 'member';
    final photoUrl = userProfile['avatar_url'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: MacOSTheme.darkSidebar,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.2),
            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                ? NetworkImage(photoUrl)
                : null,
            child: photoUrl == null || photoUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Color(0xFF007AFF),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: role == 'admin'
                  ? const Color(0xFFFF9500).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: role == 'admin'
                    ? const Color(0xFFFF9500).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              role.toUpperCase(),
              style: TextStyle(
                color: role == 'admin'
                    ? const Color(0xFFFF9500)
                    : Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: MacOSTheme.darkSidebar,
      child: const TabBar(
        indicatorColor: Color(0xFF007AFF),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        tabs: [
          Tab(text: 'Overview'),
          Tab(text: 'Day View'),
          Tab(text: 'Month View'),
          Tab(text: 'Monthly Summary'),
        ],
      ),
    );
  }
}
