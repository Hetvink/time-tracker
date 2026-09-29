enum UserRole {
  admin,
  member,
  unknown;

  static UserRole fromString(String? value) {
    if (value == null) return UserRole.unknown;
    try {
      return UserRole.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => UserRole.unknown,
      );
    } catch (_) {
      return UserRole.unknown;
    }
  }

  bool get isAdmin => this == UserRole.admin;

  String get value => name;
}
