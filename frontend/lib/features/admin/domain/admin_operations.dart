part 'admin_operations_storage_models.dart';

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

/// 新建自定义角色入参。
class AdminCreateRoleInput {
  const AdminCreateRoleInput({
    required this.code,
    required this.name,
    required this.description,
    required this.baseTemplate,
  });

  final String code;
  final String name;
  final String description;

  /// none / member / admin；member 与 admin 克隆对应内置角色权限基线。
  final String baseTemplate;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'code': code,
      'name': name,
      'description': description,
      'baseTemplate': baseTemplate,
    };
  }
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

  /// 排队与等待重试的任务允许在执行前取消。
  bool get canCancel => status == 'QUEUED' || status == 'RETRY_WAIT';
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
    this.actorLabel,
    this.resourceId,
    this.payload = const <String, Object>{},
  });

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) {
    return AdminAuditLog(
      id: json['id']?.toString() ?? '',
      actorUserId: json['actorUserId']?.toString(),
      actorLabel: json['actorLabel']?.toString(),
      action: json['action']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      resourceType: json['resourceType']?.toString() ?? '',
      resourceId: json['resourceId']?.toString(),
      ipAddress: json['ipAddress']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      payload: _payloadMap(json['payload']),
    );
  }

  final String id;
  final String? actorUserId;

  /// 操作者显示名：优先昵称回退账号名；历史脏数据缺失时为空。
  final String? actorLabel;
  final String action;
  final String description;
  final String? resourceId;
  final String resourceType;
  final String ipAddress;
  final String createdAt;

  /// 扩展负载：变更前后值、原因、requestId 等已在服务端掩码的信息。
  /// 值为 null 的键不收录；旧数据没有 payload 时为空 Map。
  final Map<String, Object> payload;
}

/// 解析审计扩展负载；非对象或缺失时回退空 Map，值为 null 的键丢弃。
Map<String, Object> _payloadMap(Object? value) {
  if (value is! Map) {
    return const <String, Object>{};
  }
  final result = <String, Object>{};
  value.forEach((key, entryValue) {
    if (entryValue != null) {
      result[key.toString()] = entryValue;
    }
  });
  return result;
}
