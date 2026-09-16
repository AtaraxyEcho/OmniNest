import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/admin/data/admin_api_response.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';

class AdminOperationsApi {
  const AdminOperationsApi(this.apiClient);

  final ApiClient apiClient;

  Future<AdminRoleManagementView> roles() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/roles/detail',
    );
    return parseRoleManagementResponse(response.data);
  }

  Future<AdminRoleDetail> updateRolePermissions(
    String roleCode,
    Set<String> permissions,
  ) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/roles/$roleCode/permissions',
      data: {'permissions': permissions.toList()},
    );
    return AdminRoleDetail.fromJson(parseData(response.data));
  }

  Future<AdminConfigManagementView> configs() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/configs/detail',
    );
    return parseConfigResponse(response.data);
  }

  Future<AdminConfigEntry> updateConfig(
    String key,
    String value,
    String? reason,
  ) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/configs/detail/$key',
      data: {'value': value, 'reason': reason},
    );
    return AdminConfigEntry.fromJson(parseData(response.data));
  }

  Future<List<AdminConfigHistory>> configHistory(String key) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/configs/$key/history',
    );
    final envelope = parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(AdminConfigHistory.fromJson)
        .toList();
  }

  Future<AdminConfigEntry> rollbackConfig(String historyId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/configs/history/$historyId/rollback',
    );
    return AdminConfigEntry.fromJson(parseData(response.data));
  }

  Future<AdminTaskManagementView> tasks() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/tasks',
    );
    return parseTaskResponse(response.data);
  }

  Future<AdminPage<AdminTaskRecord>> taskPage({
    required int page,
    required int size,
    String status = '',
    String taskType = '',
    String query = '',
    String sort = 'updatedAt',
    String dir = 'desc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/tasks/page',
      queryParameters: {
        'page': page,
        'size': size,
        'status': status,
        'taskType': taskType,
        'query': query,
        'sort': sort,
        'dir': dir,
      },
    );
    return AdminPage.fromJson(
      parseData(response.data),
      AdminTaskRecord.fromJson,
    );
  }

  Future<AdminTaskRecord> retryTask(String taskId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/tasks/$taskId/retry',
    );
    return AdminTaskRecord.fromJson(parseData(response.data));
  }

  /// 获取死信队列任务列表
  Future<List<AdminDlqTask>> listDlq({int limit = 20}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/tasks/dlq',
      queryParameters: {'limit': limit},
    );
    final envelope = parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(AdminDlqTask.fromJson)
        .toList();
  }

  /// 重试死信队列任务
  Future<void> retryDlq(String taskId) async {
    await apiClient.dio.post<Map<String, dynamic>>('/tasks/dlq/$taskId/retry');
  }

  Future<AdminLogManagementView> logs() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/logs',
    );
    return parseLogResponse(response.data);
  }

  Future<AdminPage<AdminAuditLog>> logPage({
    required int page,
    required int size,
    String action = '',
    String query = '',
    String sort = 'createdAt',
    String dir = 'desc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/logs/page',
      queryParameters: {
        'page': page,
        'size': size,
        'action': action,
        'query': query,
        'sort': sort,
        'dir': dir,
      },
    );
    return AdminPage.fromJson(parseData(response.data), AdminAuditLog.fromJson);
  }

  Future<AdminMonitoringView> monitoring() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/monitoring',
    );
    return parseMonitoringResponse(response.data);
  }

  Future<AdminStorageManagementView> storage() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/storage',
    );
    final storageView = parseStorageResponse(response.data);
    final locationsResponse = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/storage/locations',
    );
    final data = parseEnvelope(locationsResponse.data)['data'];
    final locations =
        data is List
            ? data
                .whereType<Map<String, dynamic>>()
                .map(AdminStorageLocation.fromJson)
                .toList()
            : <AdminStorageLocation>[];
    final mountsResponse = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/storage/mounts',
    );
    final mountsData = parseEnvelope(mountsResponse.data)['data'];
    final trustedMounts =
        mountsData is List
            ? mountsData
                .whereType<Map<String, dynamic>>()
                .map(AdminTrustedMount.fromJson)
                .toList()
            : <AdminTrustedMount>[];
    return AdminStorageManagementView(
      buckets: storageView.buckets,
      locations: locations,
      trustedMounts: trustedMounts,
    );
  }

  Future<List<AdminStorageDirectory>> trustedMountDirectories({
    required String mountKey,
    String? parent,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/storage/mounts/$mountKey/directories',
      queryParameters: {if (parent != null) 'parent': parent, 'size': 200},
    );
    final data = parseData(response.data);
    final items = data['items'];
    return items is List
        ? items
            .whereType<Map<String, dynamic>>()
            .map(AdminStorageDirectory.fromJson)
            .toList()
        : const <AdminStorageDirectory>[];
  }

  Future<AdminStorageLocation> createStorageLocation({
    required String name,
    required String mountKey,
    required String relativeRoot,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/storage/locations',
      data: {
        'name': name,
        'mountKey': mountKey,
        'relativeRoot': relativeRoot,
        'scopeType': 'SYSTEM',
        'enabled': true,
      },
    );
    return AdminStorageLocation.fromJson(parseData(response.data));
  }

  Future<AdminStorageLocation> updateStorageLocation({
    required String id,
    required String name,
    required bool enabled,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/storage/locations/$id',
      data: {'name': name, 'enabled': enabled},
    );
    return AdminStorageLocation.fromJson(parseData(response.data));
  }

  Future<void> deleteStorageLocation(String id) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/admin/storage/locations/$id',
    );
  }

  /// 重算所有用户的存储用量，返回受影响的用户数
  Future<int> recalculateStorage() async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/storage/recalculate',
    );
    final envelope = parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is int) return data;
    if (data is num) return data.toInt();
    return 0;
  }

  /// 全量重建搜索索引，返回清除的文档数
  Future<int> rebuildSearchIndex() async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/search/rebuild',
    );
    final envelope = parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is Map<String, dynamic> && data['clearedDocuments'] is int) {
      return data['clearedDocuments'] as int;
    }
    return 0;
  }

  Future<AdminExternalStorageView> externalStorage() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/external-storage',
    );
    return parseExternalStorageResponse(response.data);
  }

  Future<AdminExternalStorageItem> updateExternalStorageStatus(
    String id,
    String status,
  ) async {
    final response = await apiClient.dio.patch<Map<String, dynamic>>(
      '/admin/external-storage/$id/status',
      data: {'status': status},
    );
    return AdminExternalStorageItem.fromJson(parseData(response.data));
  }

  // ── 总览汇总 ──────────────────────────────────────────────────────────

  Future<AdminConsoleSummary> summary() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/summary',
    );
    return AdminConsoleSummary.fromJson(parseData(response.data));
  }

  Future<AdminAnalytics> getAnalytics({int days = 7}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/analytics',
      queryParameters: {'days': days},
    );
    return AdminAnalytics.fromJson(parseData(response.data));
  }

  // ── 会话管理 ──────────────────────────────────────────────────────────

  Future<AdminSessionManagementView> allSessions() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/sessions',
    );
    return AdminSessionManagementView.fromJson(parseData(response.data));
  }

  Future<AdminPage<AdminSessionItem>> sessionPage({
    required int page,
    required int size,
    String status = '',
    String platform = '',
    String query = '',
    String sort = 'lastActiveAt',
    String dir = 'desc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/sessions/page',
      queryParameters: {
        'page': page,
        'size': size,
        'status': status,
        'platform': platform,
        'query': query,
        'sort': sort,
        'dir': dir,
      },
    );
    return AdminPage.fromJson(
      parseData(response.data),
      AdminSessionItem.fromJson,
    );
  }

  Future<void> revokeSession(String sessionId) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/sessions/$sessionId/revoke',
    );
  }

  Future<int> cleanupSessions(int retentionDays) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/admin/sessions/cleanup',
      queryParameters: {'retentionDays': retentionDays},
    );
    return _parseCount(response.data);
  }

  // ── 登录日志 ──────────────────────────────────────────────────────────

  Future<AdminLoginAuditView> loginAuditLogs() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/login-audit',
    );
    return AdminLoginAuditView.fromJson(parseData(response.data));
  }

  Future<AdminPage<AdminLoginAuditItem>> loginAuditPage({
    required int page,
    required int size,
    String result = '',
    String platform = '',
    String query = '',
    String sort = 'createdAt',
    String dir = 'desc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/login-audit/page',
      queryParameters: {
        'page': page,
        'size': size,
        'result': result,
        'platform': platform,
        'query': query,
        'sort': sort,
        'dir': dir,
      },
    );
    return AdminPage.fromJson(
      parseData(response.data),
      AdminLoginAuditItem.fromJson,
    );
  }

  Future<int> cleanupAuditLogs(int retentionDays) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/admin/logs/audit/cleanup',
      queryParameters: {'retentionDays': retentionDays},
    );
    return _parseCount(response.data);
  }

  Future<int> cleanupLoginAuditLogs(int retentionDays) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/admin/login-audit/cleanup',
      queryParameters: {'retentionDays': retentionDays},
    );
    return _parseCount(response.data);
  }

  int _parseCount(Map<String, dynamic>? body) {
    final data = parseEnvelope(body)['data'];
    return data is num ? data.toInt() : 0;
  }

  AdminRoleManagementView parseRoleManagementResponse(
    Map<String, dynamic>? body,
  ) {
    return AdminRoleManagementView.fromJson(parseData(body));
  }

  AdminConfigManagementView parseConfigResponse(Map<String, dynamic>? body) {
    return AdminConfigManagementView.fromJson(parseData(body));
  }

  AdminTaskManagementView parseTaskResponse(Map<String, dynamic>? body) {
    return AdminTaskManagementView.fromJson(parseData(body));
  }

  AdminLogManagementView parseLogResponse(Map<String, dynamic>? body) {
    return AdminLogManagementView.fromJson(parseData(body));
  }

  AdminMonitoringView parseMonitoringResponse(Map<String, dynamic>? body) {
    return AdminMonitoringView.fromJson(parseData(body));
  }

  AdminStorageManagementView parseStorageResponse(Map<String, dynamic>? body) {
    return AdminStorageManagementView.fromJson(parseData(body));
  }

  AdminExternalStorageView parseExternalStorageResponse(
    Map<String, dynamic>? body,
  ) {
    return AdminExternalStorageView.fromJson(parseData(body));
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    return parseAdminData(
      body,
      defaultErrorCode: 'ADMIN_OPERATION_ERROR',
      defaultMessage: 'Admin 操作失败',
      invalidDataMessage: 'Admin 响应格式不正确',
    );
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    return parseAdminEnvelope(
      body,
      defaultErrorCode: 'ADMIN_OPERATION_ERROR',
      defaultMessage: 'Admin 操作失败',
    );
  }
}
