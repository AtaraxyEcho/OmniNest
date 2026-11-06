import 'package:omninest/core/errors/app_exception.dart';
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
      '/admin/roles/${Uri.encodeComponent(roleCode)}/permissions',
      data: {'permissions': permissions.toList()},
    );
    return AdminRoleDetail.fromJson(parseData(response.data));
  }

  /// 创建自定义角色：code 须以 ROLE_ 开头（大写字母/数字/下划线），
  /// baseTemplate 为 none/member/admin 时克隆对应内置角色权限。
  Future<AdminRoleDetail> createRole(AdminCreateRoleInput input) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/roles',
      data: input.toJson(),
    );
    return AdminRoleDetail.fromJson(parseData(response.data));
  }

  /// 删除自定义角色：内置角色或仍有用户绑定时后端返回业务错误。
  Future<void> deleteRole(String roleCode) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/admin/roles/${Uri.encodeComponent(roleCode)}',
    );
    parseData(response.data);
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
      '/admin/configs/detail/${Uri.encodeComponent(key)}',
      data: {'value': value, 'reason': reason},
    );
    return AdminConfigEntry.fromJson(parseData(response.data));
  }

  Future<List<AdminConfigHistory>> configHistory(String key) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/configs/${Uri.encodeComponent(key)}/history',
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
      '/admin/configs/history/${Uri.encodeComponent(historyId)}/rollback',
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
      '/admin/tasks/${Uri.encodeComponent(taskId)}/retry',
    );
    return AdminTaskRecord.fromJson(parseData(response.data));
  }

  /// 取消排队或等待重试的任务；非法状态下后端返回业务错误。
  Future<AdminTaskRecord> cancelTask(String taskId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/tasks/${Uri.encodeComponent(taskId)}/cancel',
    );
    return AdminTaskRecord.fromJson(parseData(response.data));
  }

  /// 丢弃死信任务；丢弃后任务进入 DISCARDED 终态，不可再重试。
  Future<AdminTaskRecord> discardDlqTask(String taskId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/tasks/dlq/${Uri.encodeComponent(taskId)}/discard',
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
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/tasks/dlq/${Uri.encodeComponent(taskId)}/retry',
    );
    parseAdminEnvelope(
      response.data,
      defaultErrorCode: 'DLQ_RETRY_FAILED',
      defaultMessage: '重试死信任务失败',
    );
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

  /// 审计日志出现过的操作类型；筛选下拉以它为准，避免前端手抄清单漂移。
  Future<List<String>> auditActions() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/logs/actions',
    );
    return parseAuditActions(response.data);
  }

  /// 全站分享链接审计：按创建时间倒序分页。
  Future<AdminPage<AdminFileShareLink>> shareLinksPage({
    required int page,
    required int size,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/files/shares',
      queryParameters: {'page': page, 'size': size},
    );
    return AdminPage.fromJson(
      parseData(response.data),
      AdminFileShareLink.fromJson,
    );
  }

  /// 共享空间角色能力矩阵。
  Future<List<AdminSharedSpacePermission>> sharedSpacePermissions() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/shared-space/permissions',
    );
    final data = parseEnvelope(response.data)['data'];
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map>()
        .map(
          (item) => AdminSharedSpacePermission.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  /// 保存单个角色的共享空间能力。
  Future<void> updateSharedSpacePermission(
    AdminSharedSpacePermission permission,
  ) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/shared-space/permissions/${Uri.encodeComponent(permission.roleId)}',
      data: {
        'canBrowse': permission.canBrowse,
        'canUpload': permission.canUpload,
        'canDownload': permission.canDownload,
        'canDeleteOwn': permission.canDeleteOwn,
        'canDeleteAny': permission.canDeleteAny,
        'canMoveTo': permission.canMoveTo,
        'canMoveFrom': permission.canMoveFrom,
        'canCreateFolder': permission.canCreateFolder,
      },
    );
    parseEnvelope(response.data);
  }

  /// 创建 GeoNames 数据集导入任务。
  Future<AdminGeoImportResult> importGeoDataset({
    required String dumpDate,
    String? sourceHash,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/photos/geo/import',
      data: {
        'dumpDate': dumpDate,
        if (sourceHash != null && sourceHash.isNotEmpty)
          'sourceHash': sourceHash,
      },
    );
    return AdminGeoImportResult.fromJson(parseData(response.data));
  }

  /// 将本实例内存索引重载到当前已发布数据集。
  Future<String?> reloadGeoIndex() async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/photos/geo/reload',
    );
    final data = parseData(response.data);
    final version = data['datasetVersion']?.toString();
    return version == null || version.isEmpty ? null : version;
  }

  /// 创建存量照片位置回填任务。
  Future<AdminGeoBackfillResult> backfillGeo({int? batchSize}) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/photos/geo/backfill',
      queryParameters: {if (batchSize != null) 'batchSize': batchSize},
    );
    return AdminGeoBackfillResult.fromJson(parseData(response.data));
  }

  /// 回扫动态照片，返回任务 ID。
  Future<String> reanalyzeMotionPhotos() async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/photos/motion/reanalyze',
    );
    return parseData(response.data)['taskId']?.toString() ?? '';
  }

  /// 本地媒体库中已不可用的视频条目。
  Future<AdminPage<AdminUnavailableMedia>> unavailableMediaPage({
    required int page,
    required int size,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library-sources/unavailable',
      queryParameters: {'page': page, 'size': size},
    );
    return AdminPage.fromJson(
      parseData(response.data),
      AdminUnavailableMedia.fromJson,
    );
  }

  Future<AdminStorageManagementView> storage() async {
    final responses = await Future.wait([
      apiClient.dio.get<Map<String, dynamic>>('/admin/storage'),
      apiClient.dio.get<Map<String, dynamic>>('/admin/storage/locations'),
      apiClient.dio.get<Map<String, dynamic>>('/admin/storage/mounts'),
    ]);
    final storageView = parseStorageResponse(responses[0].data);
    final locationsData = parseEnvelope(responses[1].data)['data'];
    final locations =
        locationsData is List
            ? locationsData
                .whereType<Map<String, dynamic>>()
                .map(AdminStorageLocation.fromJson)
                .toList()
            : <AdminStorageLocation>[];
    final mountsData = parseEnvelope(responses[2].data)['data'];
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
      '/admin/storage/mounts/${Uri.encodeComponent(mountKey)}/directories',
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
      '/admin/storage/locations/${Uri.encodeComponent(id)}',
      data: {'name': name, 'enabled': enabled},
    );
    return AdminStorageLocation.fromJson(parseData(response.data));
  }

  Future<void> deleteStorageLocation(String id) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/admin/storage/locations/${Uri.encodeComponent(id)}',
    );
    parseAdminEnvelope(
      response.data,
      defaultErrorCode: 'STORAGE_LOCATION_DELETE_FAILED',
      defaultMessage: '删除存储位置失败',
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
      '/admin/external-storage/${Uri.encodeComponent(id)}/status',
      data: {'status': status},
    );
    return AdminExternalStorageItem.fromJson(parseData(response.data));
  }

  Future<List<AdminConnectorOAuthApp>> listConnectorOAuthApps() async {
    final response = await apiClient.dio.get<dynamic>(
      '/admin/external-connectors/oauth-apps',
    );
    final envelope = parseEnvelope(
      response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : null,
    );
    final data = envelope['data'];
    final items = data is List ? data : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(AdminConnectorOAuthApp.fromJson)
        .toList();
  }

  Future<AdminConnectorOAuthApp> saveConnectorOAuthApp({
    required String connectorCode,
    required String clientId,
    String? clientSecret,
    required String redirectUri,
    required bool enabled,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/external-connectors/oauth-apps',
      data: {
        'connectorCode': connectorCode,
        'clientId': clientId,
        if (clientSecret != null && clientSecret.isNotEmpty)
          'clientSecret': clientSecret,
        'redirectUri': redirectUri,
        'enabled': enabled,
      },
    );
    return AdminConnectorOAuthApp.fromJson(parseData(response.data));
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
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/sessions/${Uri.encodeComponent(sessionId)}/revoke',
    );
    parseAdminEnvelope(
      response.data,
      defaultErrorCode: 'SESSION_REVOKE_FAILED',
      defaultMessage: '撤销会话失败',
    );
  }

  /// 预估会话清理条数：保留期之外的过期与已吊销会话数量。
  Future<int> previewCleanupSessions(int retentionDays) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/sessions/cleanup/preview',
      queryParameters: {'retentionDays': retentionDays},
    );
    return _parseCount(response.data);
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

  /// 预估操作审计清理条数：保留期之外的审计记录数量。
  Future<int> previewCleanupAuditLogs(int retentionDays) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/logs/audit/cleanup/preview',
      queryParameters: {'retentionDays': retentionDays},
    );
    return _parseCount(response.data);
  }

  /// 预估登录日志清理条数：保留期之外的登录记录数量。
  Future<int> previewCleanupLoginAuditLogs(int retentionDays) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/login-audit/cleanup/preview',
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

  AdminStorageManagementView parseStorageResponse(Map<String, dynamic>? body) {
    return AdminStorageManagementView.fromJson(parseData(body));
  }

  AdminExternalStorageView parseExternalStorageResponse(
    Map<String, dynamic>? body,
  ) {
    return AdminExternalStorageView.fromJson(parseData(body));
  }

  List<String> parseAuditActions(Map<String, dynamic>? body) {
    final data = parseEnvelope(body)['data'];
    if (data is! List) {
      throw const AppException(
        code: 'INVALID_RESPONSE',
        message: 'Admin 响应格式不正确',
      );
    }
    return data.whereType<String>().toList(growable: false);
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
