import 'package:omninest/features/admin/domain/admin_console_summary.dart';

class AdminRoleManagementView {
  const AdminRoleManagementView({
    required this.roles,
    required this.permissions,
  });

  factory AdminRoleManagementView.fromJson(Map<String, dynamic> json) {
    return AdminRoleManagementView(
      roles: _list(json['roles']).map(AdminRoleDetail.fromJson).toList(),
      permissions:
          _list(
            json['permissions'],
          ).map(AdminPermissionDetail.fromJson).toList(),
    );
  }

  final List<AdminRoleDetail> roles;
  final List<AdminPermissionDetail> permissions;
}

class AdminRoleDetail {
  const AdminRoleDetail({
    required this.code,
    required this.name,
    required this.description,
    required this.builtIn,
    required this.enabled,
    required this.permissions,
  });

  factory AdminRoleDetail.fromJson(Map<String, dynamic> json) {
    return AdminRoleDetail(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      builtIn: json['builtIn'] == true,
      enabled: json['enabled'] != false,
      permissions: _strings(json['permissions']),
    );
  }

  final String code;
  final String name;
  final String description;
  final bool builtIn;
  final bool enabled;
  final List<String> permissions;
}

class AdminPermissionDetail {
  const AdminPermissionDetail({
    required this.code,
    required this.name,
    required this.module,
    required this.description,
    required this.enabled,
  });

  factory AdminPermissionDetail.fromJson(Map<String, dynamic> json) {
    return AdminPermissionDetail(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      module: json['module']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      enabled: json['enabled'] != false,
    );
  }

  final String code;
  final String name;
  final String module;
  final String description;
  final bool enabled;
}

class AdminConfigManagementView {
  const AdminConfigManagementView({required this.items});

  factory AdminConfigManagementView.fromJson(Map<String, dynamic> json) {
    return AdminConfigManagementView(
      items: _list(json['items']).map(AdminConfigEntry.fromJson).toList(),
    );
  }

  final List<AdminConfigEntry> items;
}

class AdminConfigEntry {
  const AdminConfigEntry({
    required this.key,
    required this.value,
    required this.valueType,
    required this.category,
    required this.refreshScope,
    required this.updatedAt,
    this.description = '',
    this.surface = 'GENERAL',
    this.displayCode = '',
    this.editable = true,
    this.sensitiveConfigured = false,
    this.allowedValues = const [],
  });

  factory AdminConfigEntry.fromJson(Map<String, dynamic> json) {
    return AdminConfigEntry(
      key: json['key']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      valueType: json['valueType']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      refreshScope: json['refreshScope']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      surface: json['surface']?.toString() ?? 'GENERAL',
      displayCode: json['displayCode']?.toString() ?? '',
      editable: json['editable'] != false,
      sensitiveConfigured: json['sensitiveConfigured'] == true,
      allowedValues: _strings(json['allowedValues']),
    );
  }

  final String key;
  final String value;
  final String valueType;
  final String category;
  final String refreshScope;
  final String updatedAt;
  final String description;
  final String surface;
  final String displayCode;
  final bool editable;
  final bool sensitiveConfigured;
  final List<String> allowedValues;
}

class AdminConfigHistory {
  const AdminConfigHistory({
    required this.id,
    required this.configKey,
    required this.changedBy,
    required this.createdAt,
    this.oldValue,
    this.newValue,
    this.changeReason,
  });

  factory AdminConfigHistory.fromJson(Map<String, dynamic> json) {
    return AdminConfigHistory(
      id: json['id']?.toString() ?? '',
      configKey: json['configKey']?.toString() ?? '',
      oldValue: json['oldValue']?.toString(),
      newValue: json['newValue']?.toString(),
      changedBy: json['changedBy']?.toString() ?? '',
      changeReason: json['changeReason']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  final String id;
  final String configKey;
  final String? oldValue;
  final String? newValue;
  final String changedBy;
  final String? changeReason;
  final String createdAt;
}

class AdminTaskManagementView {
  const AdminTaskManagementView({required this.items});

  factory AdminTaskManagementView.fromJson(Map<String, dynamic> json) {
    return AdminTaskManagementView(
      items: _list(json['items']).map(AdminTaskRecord.fromJson).toList(),
    );
  }

  final List<AdminTaskRecord> items;
}

class AdminTaskRecord {
  const AdminTaskRecord({
    required this.id,
    required this.taskType,
    this.description = '',
    required this.status,
    required this.progress,
    required this.routingKey,
    required this.errorSummary,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.ownerLabel,
  });

  factory AdminTaskRecord.fromJson(Map<String, dynamic> json) {
    return AdminTaskRecord(
      id: json['id']?.toString() ?? '',
      taskType: json['taskType']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: _int(json['progress']),
      routingKey: json['routingKey']?.toString(),
      errorSummary: json['errorSummary']?.toString(),
      retryCount: _int(json['retryCount']),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      ownerUserId: json['ownerUserId']?.toString(),
      ownerLabel: json['ownerLabel']?.toString(),
    );
  }

  final String id;
  final String taskType;
  final String description;
  final String status;
  final int progress;
  final String? routingKey;
  final String? errorSummary;
  final int retryCount;
  final String createdAt;
  final String updatedAt;

  /// 任务归属用户。普通用户不再查看任务队列，管理端要靠它把失败任务归到人。
  /// 系统自身发起的任务没有归属，两项为空。
  final String? ownerUserId;
  final String? ownerLabel;

  bool get canRetry =>
      status == 'FAILED' || status == 'CANCELLED' || status == 'DLQ';
}

/// 死信队列任务
class AdminDlqTask {
  const AdminDlqTask({
    required this.id,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.updatedAt,
    this.errorSummary,
    this.stackSummary,
  });

  factory AdminDlqTask.fromJson(Map<String, dynamic> json) {
    return AdminDlqTask(
      id: json['id']?.toString() ?? '',
      taskType: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: _int(json['progress']),
      errorSummary: json['errorSummary']?.toString(),
      stackSummary: json['stackSummary']?.toString(),
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  final String id;
  final String taskType;
  final String status;
  final int progress;
  final String? errorSummary;
  final String? stackSummary;
  final String updatedAt;
}

class AdminLogManagementView {
  const AdminLogManagementView({required this.items});

  factory AdminLogManagementView.fromJson(Map<String, dynamic> json) {
    return AdminLogManagementView(
      items: _list(json['items']).map(AdminAuditLog.fromJson).toList(),
    );
  }

  final List<AdminAuditLog> items;
}

class AdminAuditLog {
  const AdminAuditLog({
    required this.id,
    required this.action,
    this.description = '',
    required this.resourceType,
    required this.ipAddress,
    required this.createdAt,
    this.actorUserId,
    this.resourceId,
  });

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) {
    return AdminAuditLog(
      id: json['id']?.toString() ?? '',
      actorUserId: json['actorUserId']?.toString(),
      action: json['action']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      resourceType: json['resourceType']?.toString() ?? '',
      resourceId: json['resourceId']?.toString(),
      ipAddress: json['ipAddress']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  final String id;
  final String? actorUserId;
  final String action;
  final String description;
  final String resourceType;
  final String? resourceId;
  final String ipAddress;
  final String createdAt;
}

class AdminMonitoringView {
  const AdminMonitoringView({
    this.overview = const AdminMonitoringOverview.empty(),
    this.components = const [],
    this.alerts = const [],
    this.auditRecent = const [],
    this.series = const [],
    this.health = const [],
    this.metrics = const [],
  });

  factory AdminMonitoringView.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringView(
      overview: AdminMonitoringOverview.fromJson(_map(json['overview'])),
      components:
          _list(
            json['components'],
          ).map(AdminMonitoringComponent.fromJson).toList(),
      alerts: _list(json['alerts']).map(AdminMonitoringAlert.fromJson).toList(),
      auditRecent:
          _list(json['auditRecent']).map(AdminAuditLog.fromJson).toList(),
      series:
          _list(json['series']).map(AdminMonitoringSeries.fromJson).toList(),
      health: _list(json['health']).map(AdminHealthItem.fromJson).toList(),
      metrics:
          _list(json['metrics']).map(AdminMonitoringMetric.fromJson).toList(),
    );
  }

  final AdminMonitoringOverview overview;
  final List<AdminMonitoringComponent> components;
  final List<AdminMonitoringAlert> alerts;
  final List<AdminAuditLog> auditRecent;
  final List<AdminMonitoringSeries> series;
  final List<AdminHealthItem> health;
  final List<AdminMonitoringMetric> metrics;
}

class AdminMonitoringOverview {
  const AdminMonitoringOverview({
    required this.status,
    required this.uptime,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskUsage,
    required this.jvmHeapUsage,
    required this.activeTasks,
    required this.queueDepth,
    required this.todayRequests,
  });

  const AdminMonitoringOverview.empty()
    : status = 'UNKNOWN',
      uptime = '-',
      cpuUsage = 0,
      memoryUsage = 0,
      diskUsage = 0,
      jvmHeapUsage = 0,
      activeTasks = 0,
      queueDepth = 0,
      todayRequests = 0;

  factory AdminMonitoringOverview.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringOverview(
      status: json['status']?.toString() ?? 'UNKNOWN',
      uptime: json['uptime']?.toString() ?? '-',
      cpuUsage: _double(json['cpuUsage']),
      memoryUsage: _double(json['memoryUsage']),
      diskUsage: _double(json['diskUsage']),
      jvmHeapUsage: _double(json['jvmHeapUsage']),
      activeTasks: _int(json['activeTasks']),
      queueDepth: _int(json['queueDepth']),
      todayRequests: _int(json['todayRequests']),
    );
  }

  final String status;
  final String uptime;
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final double jvmHeapUsage;
  final int activeTasks;
  final int queueDepth;
  final int todayRequests;
}

class AdminMonitoringComponent {
  const AdminMonitoringComponent({
    required this.name,
    required this.status,
    required this.detail,
  });

  factory AdminMonitoringComponent.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringComponent(
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      detail: _dynamicMap(json['detail']),
    );
  }

  final String name;
  final String status;
  final Map<String, dynamic> detail;
}

class AdminMonitoringAlert {
  const AdminMonitoringAlert({
    required this.severity,
    required this.message,
    required this.timestamp,
  });

  factory AdminMonitoringAlert.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringAlert(
      severity: json['severity']?.toString() ?? 'INFO',
      message: json['message']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
    );
  }

  final String severity;
  final String message;
  final String timestamp;
}

class AdminMonitoringSeries {
  const AdminMonitoringSeries({
    required this.metric,
    required this.label,
    required this.unit,
    required this.points,
  });

  factory AdminMonitoringSeries.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringSeries(
      metric: json['metric']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      points:
          _list(
            json['points'],
          ).map(AdminMonitoringSeriesPoint.fromJson).toList(),
    );
  }

  final String metric;
  final String label;
  final String unit;
  final List<AdminMonitoringSeriesPoint> points;
}

class AdminMonitoringSeriesPoint {
  const AdminMonitoringSeriesPoint({
    required this.timestamp,
    required this.value,
  });

  factory AdminMonitoringSeriesPoint.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringSeriesPoint(
      timestamp: json['timestamp']?.toString() ?? '',
      value: _double(json['value']),
    );
  }

  final String timestamp;
  final double value;
}

class AdminMonitoringMetric {
  const AdminMonitoringMetric({
    required this.name,
    required this.value,
    required this.unit,
    required this.status,
  });

  factory AdminMonitoringMetric.fromJson(Map<String, dynamic> json) {
    return AdminMonitoringMetric(
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
    );
  }

  final String name;
  final String value;
  final String unit;
  final String status;
}

/// 存储管理聚合视图。
///
/// [fromJson] 只解析 `/admin/storage` 返回的桶清单；[locations] 与
/// [trustedMounts] 来自独立端点，由 AdminOperationsApi.storage() 组装填充。
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
    required this.provider,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AdminExternalStorageItem.fromJson(Map<String, dynamic> json) {
    return AdminExternalStorageItem(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  final String id;
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

Map<String, dynamic> _map(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

Map<String, dynamic> _dynamicMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList();
}

double _double(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
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
