class AdminConsoleSummary {
  const AdminConsoleSummary({
    required this.users,
    required this.roles,
    required this.configs,
    required this.tasks,
    required this.storage,
    required this.health,
  });

  /// 无管理台权限时的空摘要，避免前端发起管理端请求。
  factory AdminConsoleSummary.empty() {
    return const AdminConsoleSummary(
      users: AdminUserStats(total: 0, active: 0, disabled: 0, roleCounts: {}),
      roles: <AdminRoleSummary>[],
      configs: AdminConfigStats(
        total: 0,
        hot: 0,
        nextTask: 0,
        restartRequired: 0,
      ),
      tasks: AdminTaskStats(
        total: 0,
        queued: 0,
        running: 0,
        completed: 0,
        failed: 0,
        cancelled: 0,
        dlq: 0,
      ),
      storage: AdminStorageStats(
        fileCount: 0,
        folderCount: 0,
        objectCount: 0,
        usedBytes: 0,
        externalAccountCount: 0,
      ),
      health: <AdminHealthItem>[],
    );
  }

  factory AdminConsoleSummary.fromJson(Map<String, dynamic> json) {
    return AdminConsoleSummary(
      users: AdminUserStats.fromJson(_map(json['users'])),
      roles: _list(json['roles']).map(AdminRoleSummary.fromJson).toList(),
      configs: AdminConfigStats.fromJson(_map(json['configs'])),
      tasks: AdminTaskStats.fromJson(_map(json['tasks'])),
      storage: AdminStorageStats.fromJson(_map(json['storage'])),
      health: _list(json['health']).map(AdminHealthItem.fromJson).toList(),
    );
  }

  final AdminUserStats users;
  final List<AdminRoleSummary> roles;
  final AdminConfigStats configs;
  final AdminTaskStats tasks;
  final AdminStorageStats storage;
  final List<AdminHealthItem> health;
}

class AdminUserStats {
  const AdminUserStats({
    required this.total,
    required this.active,
    required this.disabled,
    required this.roleCounts,
  });

  factory AdminUserStats.fromJson(Map<String, dynamic> json) {
    return AdminUserStats(
      total: _intValue(json['total']),
      active: _intValue(json['active']),
      disabled: _intValue(json['disabled']),
      roleCounts: _intMap(json['roleCounts']),
    );
  }

  final int total;
  final int active;
  final int disabled;
  final Map<String, int> roleCounts;

  int roleCount(String role) {
    return roleCounts[role] ?? 0;
  }
}

class AdminRoleSummary {
  const AdminRoleSummary({
    required this.code,
    required this.name,
    required this.description,
    required this.builtIn,
    required this.enabled,
    required this.permissionCount,
    required this.permissions,
  });

  factory AdminRoleSummary.fromJson(Map<String, dynamic> json) {
    return AdminRoleSummary(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      builtIn: json['builtIn'] == true,
      enabled: json['enabled'] != false,
      permissionCount: _intValue(json['permissionCount']),
      permissions:
          (json['permissions'] is List)
              ? (json['permissions'] as List)
                  .map((value) => value.toString())
                  .toList()
              : const [],
    );
  }

  final String code;
  final String name;
  final String description;
  final bool builtIn;
  final bool enabled;
  final int permissionCount;
  final List<String> permissions;
}

class AdminConfigStats {
  const AdminConfigStats({
    required this.total,
    required this.hot,
    required this.nextTask,
    required this.restartRequired,
  });

  factory AdminConfigStats.fromJson(Map<String, dynamic> json) {
    return AdminConfigStats(
      total: _intValue(json['total']),
      hot: _intValue(json['hot']),
      nextTask: _intValue(json['nextTask']),
      restartRequired: _intValue(json['restartRequired']),
    );
  }

  final int total;
  final int hot;
  final int nextTask;
  final int restartRequired;
}

class AdminTaskStats {
  const AdminTaskStats({
    required this.total,
    required this.queued,
    required this.running,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.dlq,
  });

  factory AdminTaskStats.fromJson(Map<String, dynamic> json) {
    return AdminTaskStats(
      total: _intValue(json['total']),
      queued: _intValue(json['queued']),
      running: _intValue(json['running']),
      completed: _intValue(json['completed']),
      failed: _intValue(json['failed']),
      cancelled: _intValue(json['cancelled']),
      dlq: _intValue(json['dlq']),
    );
  }

  final int total;
  final int queued;
  final int running;
  final int completed;
  final int failed;
  final int cancelled;
  final int dlq;
}

class AdminStorageStats {
  const AdminStorageStats({
    required this.fileCount,
    required this.folderCount,
    required this.objectCount,
    required this.usedBytes,
    required this.externalAccountCount,
  });

  factory AdminStorageStats.fromJson(Map<String, dynamic> json) {
    return AdminStorageStats(
      fileCount: _intValue(json['fileCount']),
      folderCount: _intValue(json['folderCount']),
      objectCount: _intValue(json['objectCount']),
      usedBytes: _intValue(json['usedBytes']),
      externalAccountCount: _intValue(json['externalAccountCount']),
    );
  }

  final int fileCount;
  final int folderCount;
  final int objectCount;
  final int usedBytes;
  final int externalAccountCount;
}

class AdminHealthItem {
  const AdminHealthItem({
    required this.name,
    required this.status,
    required this.detail,
  });

  factory AdminHealthItem.fromJson(Map<String, dynamic> json) {
    return AdminHealthItem(
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      detail: json['detail']?.toString() ?? '',
    );
  }

  final String name;
  final String status;
  final String detail;
}

Map<String, dynamic> _map(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map<String, dynamic>>().toList();
}

Map<String, int> _intMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map((key, value) => MapEntry(key.toString(), _intValue(value)));
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
