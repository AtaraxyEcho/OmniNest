import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/video/application/movie_controller.dart';

final adminSearchProvider = NotifierProvider<AdminSearchNotifier, String>(
  AdminSearchNotifier.new,
);

class AdminSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void updateQuery(String value) => state = value;

  void clear() => state = '';
}

final adminOperationsApiProvider = Provider<AdminOperationsApi>((ref) {
  return AdminOperationsApi(ref.watch(apiClientProvider));
});

/// 提供管理模块的系统摘要只读视图。
final adminConsoleSummaryProvider = FutureProvider<AdminConsoleSummary>((ref) {
  return ref.watch(adminOperationsApiProvider).summary();
});

final adminRolesProvider = FutureProvider<AdminRoleManagementView>((ref) {
  return ref.watch(adminOperationsApiProvider).roles();
});

final adminConfigsProvider = FutureProvider<AdminConfigManagementView>((ref) {
  return ref.watch(adminOperationsApiProvider).configs();
});

/// 按配置键加载变更历史，并随弹窗生命周期自动释放。
final adminConfigHistoryProvider = FutureProvider.autoDispose
    .family<List<AdminConfigHistory>, String>((ref, configKey) {
      return ref.watch(adminOperationsApiProvider).configHistory(configKey);
    });

final adminTasksProvider = FutureProvider<AdminTaskManagementView>((ref) {
  return ref.watch(adminOperationsApiProvider).tasks();
});

final adminTaskPageProvider = FutureProvider.autoDispose
    .family<AdminPage<AdminTaskRecord>, AdminTaskPageQuery>((ref, query) {
      return ref
          .watch(adminOperationsApiProvider)
          .taskPage(
            page: query.page,
            size: query.size,
            status: query.status == 'ALL' ? '' : query.status,
            taskType: query.taskType == 'ALL' ? '' : query.taskType,
            query: query.query,
            sort: query.sort,
            dir: query.dir,
          );
    });

final adminDlqProvider = FutureProvider<List<AdminDlqTask>>((ref) {
  return ref.watch(adminOperationsApiProvider).listDlq();
});

final adminLogsProvider = FutureProvider<AdminLogManagementView>((ref) {
  return ref.watch(adminOperationsApiProvider).logs();
});

final adminLogPageProvider = FutureProvider.autoDispose
    .family<AdminPage<AdminAuditLog>, AdminLogPageQuery>((ref, query) {
      return ref
          .watch(adminOperationsApiProvider)
          .logPage(
            page: query.page,
            size: query.size,
            action: query.action == 'ALL' ? '' : query.action,
            query: query.query,
            sort: query.sort,
            dir: query.dir,
          );
    });

final adminMonitoringProvider = FutureProvider<AdminMonitoringView>((ref) {
  return ref.watch(adminOperationsApiProvider).monitoring();
});

final adminStorageProvider = FutureProvider<AdminStorageManagementView>((ref) {
  return ref.watch(adminOperationsApiProvider).storage();
});

typedef AdminMountDirectoryKey = ({String mountKey, String? parent});

final adminMountDirectoriesProvider = FutureProvider.autoDispose
    .family<List<AdminStorageDirectory>, AdminMountDirectoryKey>((ref, key) {
      return ref
          .watch(adminOperationsApiProvider)
          .trustedMountDirectories(mountKey: key.mountKey, parent: key.parent);
    });

final adminExternalStorageProvider = FutureProvider<AdminExternalStorageView>((
  ref,
) {
  return ref.watch(adminOperationsApiProvider).externalStorage();
});

final adminSessionsProvider = FutureProvider<AdminSessionManagementView>((ref) {
  return ref.watch(adminOperationsApiProvider).allSessions();
});

final adminSessionPageProvider = FutureProvider.autoDispose
    .family<AdminPage<AdminSessionItem>, AdminSessionPageQuery>((ref, query) {
      return ref
          .watch(adminOperationsApiProvider)
          .sessionPage(
            page: query.page,
            size: query.size,
            status: query.status == 'ALL' ? '' : query.status,
            platform: query.platform == 'ALL' ? '' : query.platform,
            query: query.query,
            sort: query.sort,
            dir: query.dir,
          );
    });

final adminLoginAuditProvider = FutureProvider<AdminLoginAuditView>((ref) {
  return ref.watch(adminOperationsApiProvider).loginAuditLogs();
});

final adminLoginAuditPageProvider = FutureProvider.autoDispose
    .family<AdminPage<AdminLoginAuditItem>, AdminLoginAuditPageQuery>((
      ref,
      query,
    ) {
      return ref
          .watch(adminOperationsApiProvider)
          .loginAuditPage(
            page: query.page,
            size: query.size,
            result: query.result == 'ALL' ? '' : query.result,
            platform: query.platform == 'ALL' ? '' : query.platform,
            query: query.query,
            sort: query.sort,
            dir: query.dir,
          );
    });

final activeAdminAnalyticsDaysProvider = Provider<Set<int>>((ref) => <int>{});

final adminAnalyticsProvider = FutureProvider.autoDispose
    .family<AdminAnalytics, int>((ref, days) async {
      final activeDays = ref.read(activeAdminAnalyticsDaysProvider);
      activeDays.add(days);
      ref.onDispose(() => activeDays.remove(days));
      return ref.read(adminOperationsApiProvider).getAnalytics(days: days);
    });

final adminOperationsActionsProvider = Provider<AdminOperationsActions>((ref) {
  return AdminOperationsActions(ref);
});

class AdminOperationsActions {
  const AdminOperationsActions(this.ref);

  final Ref ref;

  AdminOperationsApi get _api => ref.read(adminOperationsApiProvider);

  Future<void> updateRolePermissions(
    String roleCode,
    Set<String> permissions,
  ) async {
    await _api.updateRolePermissions(roleCode, permissions);
    ref.invalidate(adminRolesProvider);
    _refreshSessionIfAffectsCurrentUser(roleCode: roleCode);
  }

  /// 角色权限变更影响当前用户所属角色时轮换本地 JWT，使 claims 与服务端一致。
  void _refreshSessionIfAffectsCurrentUser({String? roleCode, String? userId}) {
    final user = ref.read(authSessionProvider).asData?.value.user;
    if (user == null) {
      return;
    }
    final affectsCurrentUser =
        (roleCode != null &&
            (user.roles.contains(roleCode) || user.role == roleCode)) ||
        (userId != null && userId == user.id);
    if (affectsCurrentUser) {
      unawaited(ref.read(authSessionProvider.notifier).refreshSession());
    }
  }

  Future<void> updateConfig(String key, String value, {String? reason}) async {
    await _api.updateConfig(key, value, reason);
    ref.invalidate(adminConfigsProvider);
    // 天气配置派生自配置中心，任何配置写入后强制重读（配置变更低频）。
    ref.invalidate(weatherConfigProvider);
  }

  Future<void> retryTask(String taskId) async {
    await _api.retryTask(taskId);
    ref.invalidate(adminTasksProvider);
    ref.invalidate(adminTaskPageProvider);
  }

  /// 逐条批量重试任务，失败项跳过，结束后统一刷新任务列表。
  Future<AdminBatchResult> batchRetryTasks(Iterable<String> taskIds) async {
    var successCount = 0;
    final failedIds = <String>[];
    for (final taskId in taskIds) {
      try {
        await _api.retryTask(taskId);
        successCount++;
      } on Object {
        failedIds.add(taskId);
      }
    }
    if (successCount > 0) {
      ref.invalidate(adminTasksProvider);
      ref.invalidate(adminTaskPageProvider);
    }
    return (successCount: successCount, failedIds: failedIds);
  }

  /// 重试死信队列任务
  Future<void> retryDlq(String taskId) async {
    await _api.retryDlq(taskId);
    ref.invalidate(adminDlqProvider);
  }

  Future<AdminConfigEntry> rollbackConfig(String historyId) async {
    final entry = await _api.rollbackConfig(historyId);
    ref.invalidate(adminConfigsProvider);
    ref.invalidate(adminConfigHistoryProvider(entry.key));
    ref.invalidate(weatherConfigProvider);
    return entry;
  }

  /// 重算所有用户的存储用量
  Future<int> recalculateStorage() async {
    final count = await _api.recalculateStorage();
    ref.invalidate(adminStorageProvider);
    return count;
  }

  /// 全量重建搜索索引
  Future<int> rebuildSearchIndex() async {
    final count = await _api.rebuildSearchIndex();
    ref.invalidate(adminTasksProvider);
    ref.invalidate(adminTaskPageProvider);
    ref.invalidate(adminConsoleSummaryProvider);
    return count;
  }

  Future<AdminStorageLocation> createStorageLocation({
    required String name,
    required String mountKey,
    required String relativeRoot,
  }) async {
    final location = await _api.createStorageLocation(
      name: name,
      mountKey: mountKey,
      relativeRoot: relativeRoot,
    );
    _invalidateStorageRelated();
    return location;
  }

  Future<void> updateStorageLocation({
    required AdminStorageLocation location,
    required bool enabled,
  }) async {
    await _api.updateStorageLocation(
      id: location.id,
      name: location.name,
      enabled: enabled,
    );
    _invalidateStorageRelated();
  }

  Future<void> deleteStorageLocation(String id) async {
    await _api.deleteStorageLocation(id);
    _invalidateStorageRelated();
  }

  void _invalidateStorageRelated() {
    ref.invalidate(adminStorageProvider);
    // 同页库源区依赖位置列表与库源列表，挂载变更后必须同步失效。
    ref.invalidate(videoStorageLocationsProvider);
    ref.invalidate(videoLibrarySourcesProvider);
  }

  Future<void> updateExternalStorageStatus(String id, String status) async {
    await _api.updateExternalStorageStatus(id, status);
    ref.invalidate(adminExternalStorageProvider);
  }

  Future<void> revokeSession(String sessionId) async {
    await _api.revokeSession(sessionId);
    ref.invalidate(adminSessionsProvider);
    ref.invalidate(adminSessionPageProvider);
  }

  /// 逐条批量强制下线会话，失败项跳过，结束后统一刷新会话列表。
  Future<AdminBatchResult> batchRevokeSessions(
    Iterable<String> sessionIds,
  ) async {
    var successCount = 0;
    final failedIds = <String>[];
    for (final sessionId in sessionIds) {
      try {
        await _api.revokeSession(sessionId);
        successCount++;
      } on Object {
        failedIds.add(sessionId);
      }
    }
    if (successCount > 0) {
      ref.invalidate(adminSessionsProvider);
      ref.invalidate(adminSessionPageProvider);
    }
    return (successCount: successCount, failedIds: failedIds);
  }

  Future<int> cleanupSessions(int retentionDays) async {
    final count = await _api.cleanupSessions(retentionDays);
    ref.invalidate(adminSessionsProvider);
    ref.invalidate(adminSessionPageProvider);
    return count;
  }

  Future<int> cleanupAuditLogs(int retentionDays) async {
    final count = await _api.cleanupAuditLogs(retentionDays);
    ref.invalidate(adminLogsProvider);
    ref.invalidate(adminLogPageProvider);
    ref.invalidate(adminMonitoringProvider);
    return count;
  }

  Future<int> cleanupLoginAuditLogs(int retentionDays) async {
    final count = await _api.cleanupLoginAuditLogs(retentionDays);
    ref.invalidate(adminLoginAuditProvider);
    ref.invalidate(adminLoginAuditPageProvider);
    return count;
  }
}
