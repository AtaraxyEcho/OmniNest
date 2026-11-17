part of 'admin_operations.dart';

/// 存储、外部存储与会话/登录审计域模型。

class AdminStorageManagementView {
  const AdminStorageManagementView({
    required this.buckets,
    this.locations = const [],
    this.trustedMounts = const [],
  });

  factory AdminStorageManagementView.fromJson(Map<String, dynamic> json) {
    return AdminStorageManagementView(
      buckets: _list(json['buckets']).map(AdminBucketItem.fromJson).toList(),
    );
  }

  final List<AdminBucketItem> buckets;

  /// 本地只读存储位置，来自 `/admin/storage/locations`。
  final List<AdminStorageLocation> locations;

  /// 部署可信挂载，来自 `/admin/storage/mounts`。
  final List<AdminTrustedMount> trustedMounts;
}

class AdminTrustedMount {
  const AdminTrustedMount({
    required this.mountKey,
    required this.displayName,
    required this.available,
  });

  factory AdminTrustedMount.fromJson(Map<String, dynamic> json) {
    return AdminTrustedMount(
      mountKey: json['mountKey']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      available: json['available'] == true,
    );
  }

  final String mountKey;
  final String displayName;
  final bool available;
}

class AdminStorageDirectory {
  const AdminStorageDirectory({
    required this.nodeId,
    required this.name,
    required this.relativePath,
    required this.hasChildren,
  });

  factory AdminStorageDirectory.fromJson(Map<String, dynamic> json) {
    return AdminStorageDirectory(
      nodeId: json['nodeId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      relativePath: json['relativePath']?.toString() ?? '.',
      hasChildren: json['hasChildren'] == true,
    );
  }

  final String nodeId;
  final String name;
  final String relativePath;
  final bool hasChildren;
}

class AdminStorageLocation {
  const AdminStorageLocation({
    required this.id,
    required this.name,
    required this.providerType,
    required this.managementMode,
    required this.mountKey,
    required this.relativeRoot,
    required this.scopeType,
    required this.enabled,
    required this.healthStatus,
    required this.nodeId,
  });

  factory AdminStorageLocation.fromJson(Map<String, dynamic> json) {
    return AdminStorageLocation(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      providerType: json['providerType']?.toString() ?? '',
      managementMode: json['managementMode']?.toString() ?? '',
      mountKey: json['mountKey']?.toString() ?? '',
      relativeRoot: json['relativeRoot']?.toString() ?? '.',
      scopeType: json['scopeType']?.toString() ?? '',
      enabled: json['enabled'] == true,
      healthStatus: json['healthStatus']?.toString() ?? 'UNAVAILABLE',
      nodeId: json['nodeId']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String providerType;
  final String managementMode;
  final String mountKey;
  final String relativeRoot;
  final String scopeType;
  final bool enabled;
  final String healthStatus;
  final String nodeId;
}

class AdminBucketItem {
  const AdminBucketItem({
    required this.name,
    required this.purpose,
    required this.status,
  });

  factory AdminBucketItem.fromJson(Map<String, dynamic> json) {
    return AdminBucketItem(
      name: json['name']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  final String name;
  final String purpose;
  final String status;
}

class AdminExternalStorageView {
  const AdminExternalStorageView({required this.items});

  factory AdminExternalStorageView.fromJson(Map<String, dynamic> json) {
    return AdminExternalStorageView(
      items:
          _list(json['items']).map(AdminExternalStorageItem.fromJson).toList(),
    );
  }

  final List<AdminExternalStorageItem> items;
}

class AdminExternalStorageItem {
  const AdminExternalStorageItem({
    required this.id,
    required this.ownerUserId,
    required this.provider,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AdminExternalStorageItem.fromJson(Map<String, dynamic> json) {
    return AdminExternalStorageItem(
      id: json['id']?.toString() ?? '',
      ownerUserId: json['ownerUserId']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  final String id;
  final String ownerUserId;
  final String provider;
  final String displayName;
  final String status;
  final String createdAt;
  final String updatedAt;
}

class AdminConnectorOAuthApp {
  const AdminConnectorOAuthApp({
    required this.id,
    required this.connectorCode,
    required this.clientId,
    required this.redirectUri,
    required this.enabled,
    required this.updatedAt,
  });

  factory AdminConnectorOAuthApp.fromJson(Map<String, dynamic> json) {
    return AdminConnectorOAuthApp(
      id: json['id']?.toString() ?? '',
      connectorCode: json['connectorCode']?.toString() ?? '',
      clientId: json['clientId']?.toString() ?? '',
      redirectUri: json['redirectUri']?.toString() ?? '',
      enabled: json['enabled'] == true,
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  final String id;
  final String connectorCode;
  final String clientId;
  final String redirectUri;
  final bool enabled;
  final String updatedAt;
}

// ── 会话管理 ──────────────────────────────────────────────────────────

class AdminSessionManagementView {
  const AdminSessionManagementView({required this.items});

  factory AdminSessionManagementView.fromJson(Map<String, dynamic> json) {
    return AdminSessionManagementView(
      items: _list(json['items']).map(AdminSessionItem.fromJson).toList(),
    );
  }

  final List<AdminSessionItem> items;
}

class AdminSessionItem {
  const AdminSessionItem({
    required this.id,
    required this.userId,
    required this.clientPlatform,
    required this.ipAddress,
    required this.issuedAt,
    required this.expiresAt,
    required this.lastActiveAt,
    this.username,
    this.deviceId,
    this.deviceName,
    this.revokedAt,
    this.revokeReason,
  });

  factory AdminSessionItem.fromJson(Map<String, dynamic> json) {
    return AdminSessionItem(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString(),
      clientPlatform: json['clientPlatform']?.toString() ?? '',
      deviceId: json['deviceId']?.toString(),
      deviceName: json['deviceName']?.toString(),
      ipAddress: json['ipAddress']?.toString() ?? '',
      issuedAt: json['issuedAt']?.toString() ?? '',
      expiresAt: json['expiresAt']?.toString() ?? '',
      lastActiveAt: json['lastActiveAt']?.toString() ?? '',
      revokedAt: json['revokedAt']?.toString(),
      revokeReason: json['revokeReason']?.toString(),
    );
  }

  final String id;
  final String userId;
  final String? username;
  final String clientPlatform;
  final String? deviceId;
  final String? deviceName;
  final String ipAddress;
  final String issuedAt;
  final String expiresAt;
  final String lastActiveAt;
  final String? revokedAt;
  final String? revokeReason;

  bool get isRevoked => revokedAt != null && revokedAt!.isNotEmpty;

  bool get isExpired {
    final expires = DateTime.tryParse(expiresAt);
    return !isRevoked &&
        expires != null &&
        expires.isBefore(DateTime.now().toUtc());
  }

  bool get isInactive => isRevoked || isExpired;

  bool get isActive => !isInactive;
}

// ── 登录日志 ──────────────────────────────────────────────────────────

class AdminLoginAuditView {
  const AdminLoginAuditView({required this.items});

  factory AdminLoginAuditView.fromJson(Map<String, dynamic> json) {
    return AdminLoginAuditView(
      items: _list(json['items']).map(AdminLoginAuditItem.fromJson).toList(),
    );
  }

  final List<AdminLoginAuditItem> items;
}

class AdminLoginAuditItem {
  const AdminLoginAuditItem({
    required this.id,
    required this.username,
    required this.loginResult,
    required this.clientPlatform,
    required this.ipAddress,
    required this.createdAt,
    this.userId,
    this.userAgent,
    this.failureReason,
  });

  factory AdminLoginAuditItem.fromJson(Map<String, dynamic> json) {
    return AdminLoginAuditItem(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString(),
      username: json['username']?.toString() ?? '',
      loginResult: json['loginResult']?.toString() ?? '',
      clientPlatform: json['clientPlatform']?.toString() ?? '',
      ipAddress: json['ipAddress']?.toString() ?? '',
      userAgent: json['userAgent']?.toString(),
      failureReason: json['failureReason']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  final String id;
  final String? userId;
  final String username;
  final String loginResult;
  final String clientPlatform;
  final String ipAddress;
  final String? userAgent;
  final String? failureReason;
  final String createdAt;
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map<String, dynamic>>().toList();
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList();
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
