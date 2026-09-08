class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.status,
    required this.role,
    required this.roles,
    required this.permissions,
    required this.quotaBytes,
    required this.usedBytes,
    this.displayName,
    this.email,
    this.avatarUrl,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      email: json['email']?.toString(),
      status: json['status']?.toString() ?? AdminUserStatus.active,
      role: json['role']?.toString() ?? AdminRoles.member,
      roles: _stringSet(json['roles']),
      permissions: _stringSet(json['permissions']),
      quotaBytes: _intValue(json['quotaBytes']),
      usedBytes: _intValue(json['usedBytes']),
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? email;
  final String status;
  final String role;
  final Set<String> roles;
  final Set<String> permissions;
  final int quotaBytes;
  final int usedBytes;

  String get title =>
      displayName == null || displayName!.isEmpty ? username : displayName!;

  bool get isQuotaUnlimited => quotaBytes < 0;

  double get quotaUsage {
    if (isQuotaUnlimited) {
      return 0;
    }
    if (quotaBytes <= 0) {
      return 0;
    }
    return (usedBytes / quotaBytes).clamp(0, 1);
  }

  bool get isSuperAdmin => roles.contains(AdminRoles.superAdmin);

  bool get isActive => status == AdminUserStatus.active;

  static Set<String> _stringSet(Object? rawValue) {
    if (rawValue is! List) {
      return const {};
    }
    return rawValue.map((value) => value.toString()).toSet();
  }

  static int _intValue(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return int.tryParse(rawValue?.toString() ?? '') ?? 0;
  }
}

class AdminUserStatus {
  const AdminUserStatus._();

  static const active = 'ACTIVE';
  static const disabled = 'DISABLED';
}

class AdminCreateUserInput {
  const AdminCreateUserInput({
    required this.username,
    required this.password,
    required this.roles,
    this.displayName,
    this.email,
    this.status = 'ACTIVE',
  });

  final String username;
  final String? displayName;
  final String? email;
  final String password;
  final Set<String> roles;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'displayName': displayName,
      'email': email,
      'password': password,
      'roles': roles.toList(),
      'status': status,
    };
  }
}

class AdminRoles {
  const AdminRoles._();

  static const superAdmin = 'SUPER_ADMIN';
  static const admin = 'ADMIN';
  static const member = 'MEMBER';
  static const guest = 'GUEST';

  static const manageableRoles = [admin, member, guest];
  static const allRoles = [superAdmin, admin, member, guest];
}
