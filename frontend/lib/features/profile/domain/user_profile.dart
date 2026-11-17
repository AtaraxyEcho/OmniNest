/// 用户个人资料实体
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.email,
    this.avatarUrl,
    this.role = 'MEMBER',
    this.createdAt,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? email;
  final String? avatarUrl;
  final String role;
  final DateTime? createdAt;

  /// 从 JSON 解析
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      email: json['email']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      role: json['role']?.toString() ?? 'MEMBER',
      createdAt:
          json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString())
              : null,
    );
  }

  /// 显示名称（优先 displayName，回退 username）
  String get effectiveName =>
      displayName?.isNotEmpty == true ? displayName! : username;

  /// 是否为管理员
  bool get isAdmin => role == 'ADMIN' || role == 'SUPER_ADMIN';

  /// 是否为超级管理员
  bool get isSuperAdmin => role == 'SUPER_ADMIN';

  UserProfile copyWith({
    String? displayName,
    String? email,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role,
      createdAt: createdAt,
    );
  }
}
