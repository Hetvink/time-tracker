import 'package:time_trak/features/auth/data/models/user_role.dart';

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// A company member with live status and tracked-time totals,
/// as returned by the `get_company_members` RPC.
class TeamMember {
  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final UserRole role;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime? joinedAt;
  final bool isWorking;
  final bool isOnBreak;
  final DateTime? sessionStartedAt;
  final DateTime? lastSeenAt;
  final Duration today;
  final Duration week;
  final Duration month;

  const TeamMember({
    required this.id,
    required this.email,
    this.name,
    this.avatarUrl,
    required this.role,
    required this.isActive,
    this.lastLoginAt,
    this.joinedAt,
    required this.isWorking,
    required this.isOnBreak,
    this.sessionStartedAt,
    this.lastSeenAt,
    required this.today,
    required this.week,
    required this.month,
  });

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email.split('@').first;
  }

  String get initials {
    final parts = displayName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  bool get isAdmin => role == UserRole.admin;

  /// Profile map in the shape `UserDetailPage` expects.
  Map<String, dynamic> toProfileMap() => {
    'id': id,
    'email': email,
    'name': name,
    'avatar_url': avatarUrl,
    'role': role.value,
    'is_active': isActive,
    'last_login_at': lastLoginAt?.toUtc().toIso8601String(),
  };

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    Duration secs(String key) =>
        Duration(seconds: (json[key] as num?)?.toInt() ?? 0);
    return TeamMember(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: UserRole.fromString(json['role'] as String?),
      isActive: json['is_active'] as bool? ?? true,
      lastLoginAt: _parseDate(json['last_login_at']),
      joinedAt: _parseDate(json['joined_company_at']),
      isWorking: json['is_working'] as bool? ?? false,
      isOnBreak: json['is_on_break'] as bool? ?? false,
      sessionStartedAt: _parseDate(json['session_started_at']),
      lastSeenAt: _parseDate(json['last_seen_at']),
      today: secs('today_work_seconds'),
      week: secs('week_work_seconds'),
      month: secs('month_work_seconds'),
    );
  }
}
