/// 当前用户的活跃会话信息。
class UserSession {
  const UserSession({
    required this.id,
    required this.clientPlatform,
    required this.ipAddress,
    required this.issuedAt,
    required this.expiresAt,
    required this.lastActiveAt,
    required this.createdAt,
    this.deviceId,
    this.deviceName,
    this.current = false,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      id: json['id']?.toString() ?? '',
      clientPlatform: json['clientPlatform']?.toString() ?? '',
      deviceId: json['deviceId']?.toString(),
      deviceName: json['deviceName']?.toString(),
      ipAddress: json['ipAddress']?.toString() ?? '',
      issuedAt: json['issuedAt']?.toString() ?? '',
      expiresAt: json['expiresAt']?.toString() ?? '',
      lastActiveAt: json['lastActiveAt']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      current: json['current'] as bool? ?? false,
    );
  }

  final String id;
  final String clientPlatform;
  final String? deviceId;
  final String? deviceName;
  final String ipAddress;
  final String issuedAt;
  final String expiresAt;
  final String lastActiveAt;
  final String createdAt;

  /// 是否为发起本次请求的会话（后端按访问令牌 sid 标记）。
  final bool current;

  /// 获取设备显示名称，优先使用 deviceName，回退到 clientPlatform。
  String get effectiveDeviceName =>
      deviceName?.isNotEmpty == true ? deviceName! : clientPlatform;
}
