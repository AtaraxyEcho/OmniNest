class AuthTokenResponse {
  const AuthTokenResponse({
    required this.tokenType,
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.refreshExpiresAt,
    required this.user,
  });

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) {
    return AuthTokenResponse(
      tokenType: json['tokenType']?.toString() ?? 'Bearer',
      accessToken: json['accessToken']?.toString() ?? '',
      expiresAt: _parseDateTime(json['expiresAt']),
      refreshToken: json['refreshToken']?.toString(),
      refreshExpiresAt: _parseOptionalDateTime(json['refreshExpiresAt']),
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String tokenType;
  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
  final DateTime? refreshExpiresAt;
  final UserProfile user;

  bool isExpired({
    DateTime? now,
    Duration safetyWindow = const Duration(minutes: 1),
  }) {
    final currentTime = now ?? DateTime.now();
    return !expiresAt.subtract(safetyWindow).isAfter(currentTime);
  }

  Map<String, dynamic> toJson() {
    return {
      'tokenType': tokenType,
      'accessToken': accessToken,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'refreshToken': refreshToken,
      'refreshExpiresAt': refreshExpiresAt?.toUtc().toIso8601String(),
      'user': user.toJson(),
    };
  }
}

class UserProfile {
  UserProfile({
    required this.id,
    required this.username,
    required this.role,
    Set<String> roles = const <String>{},
    Set<String> permissions = const <String>{},
    this.displayName,
    this.email,
    this.avatarUrl,
  }) : roles = Set<String>.unmodifiable(roles),
       permissions = Set<String>.unmodifiable(permissions);

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'MEMBER',
      roles: _parseStringSet(json['roles']),
      permissions: _parseStringSet(json['permissions']),
      displayName: json['displayName']?.toString(),
      email: json['email']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }

  final String id;
  final String username;
  final String role;
  final Set<String> roles;
  final Set<String> permissions;
  final String? displayName;
  final String? email;
  final String? avatarUrl;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role,
      'roles': roles.toList()..sort(),
      'permissions': permissions.toList()..sort(),
      'displayName': displayName,
      'email': email,
      'avatarUrl': avatarUrl,
    };
  }
}

Set<String> _parseStringSet(dynamic value) {
  if (value is! Iterable) {
    return const <String>{};
  }
  return Set<String>.unmodifiable(
    value.map((item) => item.toString()).where((item) => item.isNotEmpty),
  );
}

DateTime _parseDateTime(dynamic value) {
  final rawValue = value?.toString() ?? '';
  final parsed = DateTime.tryParse(rawValue);
  if (parsed != null) {
    return parsed.toLocal();
  }
  final normalized = rawValue.replaceFirst(' ', 'T');
  final fallback = DateTime.tryParse(normalized);
  if (fallback != null) {
    return fallback.toLocal();
  }
  throw FormatException('无法解析日期时间: $rawValue');
}

DateTime? _parseOptionalDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) {
    return null;
  }
  return _parseDateTime(value);
}

/// 登录两步验证挑战：密码已通过，等待第二步验证码或注册引导。
class AuthChallenge {
  const AuthChallenge({
    required this.challengeToken,
    required this.type,
    this.expiresAt,
  });

  factory AuthChallenge.fromJson(Map<String, dynamic> json) {
    return AuthChallenge(
      challengeToken: json['challengeToken']?.toString() ?? '',
      type: json['challengeType']?.toString() ?? 'verify',
      expiresAt: _parseOptionalDateTime(json['challengeExpiresAt']),
    );
  }

  final String challengeToken;

  /// verify=已启用待验证；enroll=强制角色待注册。
  final String type;
  final DateTime? expiresAt;

  bool get isEnrollment => type == 'enroll';
}

/// 登录结果：正常令牌，或需要两步验证的挑战。
class AuthLoginResult {
  const AuthLoginResult({this.token, this.challenge});

  factory AuthLoginResult.fromJson(Map<String, dynamic> json) {
    if (json['twoFactorRequired'] == true) {
      return AuthLoginResult(challenge: AuthChallenge.fromJson(json));
    }
    return AuthLoginResult(token: AuthTokenResponse.fromJson(json));
  }

  final AuthTokenResponse? token;
  final AuthChallenge? challenge;

  bool get requiresTwoFactor => challenge != null;
}

/// 两步验证秘钥视图（扫码 URI 与手输秘钥）。
class TwoFactorSetupData {
  const TwoFactorSetupData({required this.secret, required this.otpauthUri});

  factory TwoFactorSetupData.fromJson(Map<String, dynamic> json) {
    return TwoFactorSetupData(
      secret: json['secret']?.toString() ?? '',
      otpauthUri: json['otpauthUri']?.toString() ?? '',
    );
  }

  final String secret;
  final String otpauthUri;
}

/// 注册引导启用结果：一次性备份码与完成令牌。
class TwoFactorBootstrapEnableData {
  const TwoFactorBootstrapEnableData({
    required this.backupCodes,
    required this.finalizeToken,
  });

  factory TwoFactorBootstrapEnableData.fromJson(Map<String, dynamic> json) {
    final codes = json['backupCodes'];
    return TwoFactorBootstrapEnableData(
      backupCodes:
          codes is List
              ? codes.map((item) => item.toString()).toList()
              : const <String>[],
      finalizeToken: json['finalizeToken']?.toString() ?? '',
    );
  }

  final List<String> backupCodes;
  final String finalizeToken;
}

/// 两步验证状态。
class TwoFactorStatusData {
  const TwoFactorStatusData({required this.enabled, required this.required});

  factory TwoFactorStatusData.fromJson(Map<String, dynamic> json) {
    return TwoFactorStatusData(
      enabled: json['enabled'] == true,
      required: json['required'] == true,
    );
  }

  final bool enabled;
  final bool required;
}
