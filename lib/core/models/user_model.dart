import 'package:time_trak/features/auth/data/models/user_role.dart';

/// Domain model for User
/// Platform-agnostic representation of a user
class UserModel {
  final String id; // Supabase UUID
  final String email;
  final String? name;
  final UserRole role; // Role inside the user's company
  final String? avatarUrl;
  final String? companyId;
  final DateTime? joinedCompanyAt;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isActive;

  const UserModel({
    required this.id,
    required this.email,
    this.name,
    required this.role,
    this.avatarUrl,
    this.companyId,
    this.joinedCompanyAt,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = true,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isMember => role == UserRole.member;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email.split('@').first;
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    UserRole? role,
    String? avatarUrl,
    String? companyId,
    DateTime? joinedCompanyAt,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      companyId: companyId ?? this.companyId,
      joinedCompanyAt: joinedCompanyAt ?? this.joinedCompanyAt,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Only the columns a user may edit themselves; role, company and status
  /// are changed through RPCs and ignored by the database otherwise.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'avatar_url': avatarUrl,
      'last_login_at': lastLoginAt?.toUtc().toIso8601String(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => json[key] == null
        ? null
        : DateTime.tryParse(json[key] as String)?.toLocal();
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      role: UserRole.fromString(json['role'] as String?),
      avatarUrl: json['avatar_url'] as String?,
      companyId: json['company_id'] as String?,
      joinedCompanyAt: date('joined_company_at'),
      createdAt: date('created_at') ?? DateTime.now(),
      lastLoginAt: date('last_login_at'),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
