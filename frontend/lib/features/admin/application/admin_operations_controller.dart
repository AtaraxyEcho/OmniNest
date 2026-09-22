import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
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

/// Admin 分区切换进入即查的失效器。
///
/// 分区数据 provider 为常驻缓存且侧栏切换不失效，切回分区会一直显示旧
/// 数据。tasks/logs/sessions 为 autoDispose family，子树卸载即销毁、重进
/// 天然新查，无需处理。storage 分区复用合并刷新，避免与挂载创建流程
/// 同帧多次 rebuild。
final adminSectionRefreshProvider = Provider<AdminSectionRefresher>((ref) {
  return AdminSectionRefresher(ref);
});

class AdminSectionRefresher {
  AdminSectionRefresher(this._ref);

  final Ref _ref;

  /// 失效切入党区的常驻缓存 provider，下次挂载即重新请求。
  void invalidate(AdminSection section) {
    switch (section) {
      case AdminSection.overview:
        _ref.invalidate(adminConsoleControllerProvider);
      case AdminSection.users:
        _ref.invalidate(adminUserControllerProvider);
      case AdminSection.monitoring:
        _ref.invalidate(adminMonitoringProvider);
      case AdminSection.roles:
        _ref.invalidate(adminRolesProvider);
      case AdminSection.config:
        _ref.invalidate(adminConfigsProvider);
      case AdminSection.storage:
        _ref.invalidate(adminStorageProvider);
        _ref
            .read(adminOperationsActionsProvider)
            .scheduleStorageRelatedRefresh();
      case AdminSection.externalStorage:
        _ref.invalidate(adminExternalStorageProvider);
      case AdminSection.logs:
      case AdminSection.tasks:
      case AdminSection.sessions:
        break;
    }
  }
}

/// 提供管理模块的系统摘要只读视图。
///
/// 无管理台入口权限时不请求后端，直接返回空摘要，避免 MEMBER 在 Portal 产生 403。
final adminConsoleSummaryProvider = FutureProvider<AdminConsoleSummary>((ref) {
  ref.watch(sessionEpochProvider);

  if (!ref.watch(canAccessAdminConsoleProvider)) {
    return AdminConsoleSummary.empty();
  }
  return ref.watch(adminOperationsApiProvider).summary();
});

final adminRolesProvider = FutureProvider<AdminRoleManagementView>((ref) {
  ref.watch(sessionEpochProvider);

  return ref.watch(adminOperationsApiProvider).roles();
});

final adminConfigsProvider = FutureProvider<AdminConfigManagementView>((ref) {
  ref.watch(sessionEpochProvider);

  return ref.watch(adminOperationsApiProvider).configs();
});

/// 按配置键加载变更历史，并随弹窗生命周期自动释放。
final adminConfigHistoryProvider = FutureProvider.autoDispose
    .family<List<AdminConfigHistory>, String>((ref, configKey) {
      return ref.watch(adminOperationsApiProvider).configHistory(configKey);
    });

final adminTasksProvider = FutureProvider<AdminTaskManagementView>((ref) {
  ref.watch(sessionEpochProvider);

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
  ref.watch(sessionEpochProvider);

  return ref.watch(adminOperationsApiProvider).listDlq();
});

final adminLogsProvider = FutureProvider<AdminLogManagementView>((ref) {
  ref.watch(sessionEpochProvider);

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
  ref.watch(sessionEpochProvider);

  return ref.watch(adminOperationsApiProvider).monitoring();
});

/// 监控分区挂载期间的准实时轮询间隔；4C4G 自托管画像取保守端，可调。
const Duration adminMonitoringPollInterval = Duration(seconds: 10);

/// 监控分区准实时轮询器：autoDispose，分区页面挂载期间保持 watch 即存活，
/// 卸载（AnimatedSwitcher 切走）即停。错误时退避（连续错误数 ×2，封顶
/// 6 个间隔），恢复成功即回到基础间隔；配合分区渲染的保数据刷新，
/// 轮询期间不闪 loading。
final adminMonitoringPollerProvider = Provider.autoDispose<void>((ref) {
  Timer? timer;
  var consecutiveErrors = 0;
  ref.listen<AsyncValue<AdminMonitoringView>>(adminMonitoringProvider, (
    previous,
    next,
  ) {
    consecutiveErrors = next.hasError ? consecutiveErrors + 1 : 0;
  });

  void tick() {
    ref.invalidate(adminMonitoringProvider);
    final backoffMultiplier =
        consecutiveErrors == 0 ? 1 : math.min(consecutiveErrors * 2, 6);
    timer = Timer(adminMonitoringPollInterval * backoffMultiplier, tick);
  }

  timer = Timer(adminMonitoringPollInterval, tick);
  ref.onDispose(() => timer?.cancel());
});

final adminStorageProvider = FutureProvider<AdminStorageManagementView>((ref) {
  ref.watch(sessionEpochProvider);

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
  ref.watch(sessionEpochProvider);
  return ref.watch(adminOperationsApiProvider).externalStorage();
});

final adminConnectorOAuthAppsProvider =
    FutureProvider<List<AdminConnectorOAuthApp>>((ref) {
      ref.watch(sessionEpochProvider);
      return ref.watch(adminOperationsApiProvider).listConnectorOAuthApps();
    });

final adminSessionsProvider = FutureProvider<AdminSessionManagementView>((ref) {
  ref.watch(sessionEpochProvider);

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
  AdminOperationsActions(this.ref);

  final Ref ref;

  /// 同一批次内只允许一次存储相关 Provider 重建（Riverpod 3 禁止同帧重复 rebuild）。
  static int _storageRelatedEpoch = 0;

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
    // 天气由后端代理读取配置中心；配置写入后强制重读实时天气。
    ref.invalidate(realtimeWeatherProvider);
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
    ref.invalidate(realtimeWeatherProvider);
    return entry;
  }

  /// 重算所有用户的存储用量
  Future<int> recalculateStorage() async {
    final count = await _api.recalculateStorage();
    scheduleStorageRelatedRefresh();
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
    scheduleStorageRelatedRefresh();
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
    scheduleStorageRelatedRefresh();
  }

  Future<void> deleteStorageLocation(String id) async {
    await _api.deleteStorageLocation(id);
    scheduleStorageRelatedRefresh();
  }

  /// 合并失效存储相关 Provider。
  ///
  /// 创建挂载位置可能同时触发：控制器动作、向导回写、库源 Provider 的
  /// ref.listen 级联。Riverpod 3 下同帧多次 invalidate FutureProvider 会抛
  /// "rebuild multiple times in the same frame"。此处用 epoch + microtask
  /// 把整批失效压成一次。
  void scheduleStorageRelatedRefresh() {
    final epoch = ++_storageRelatedEpoch;
    scheduleMicrotask(() {
      if (!ref.mounted || epoch != _storageRelatedEpoch) {
        return;
      }
      ref.invalidate(adminStorageProvider);
      ref.invalidate(videoStorageLocationsProvider);
      ref.invalidate(videoLibrarySourcesProvider);
    });
  }

  Future<void> updateExternalStorageStatus(String id, String status) async {
    await _api.updateExternalStorageStatus(id, status);
    ref.invalidate(adminExternalStorageProvider);
  }

  Future<List<AdminConnectorOAuthApp>> listConnectorOAuthApps() {
    return _api.listConnectorOAuthApps();
  }

  Future<void> saveConnectorOAuthApp({
    required String connectorCode,
    required String clientId,
    String? clientSecret,
    required String redirectUri,
    required bool enabled,
  }) async {
    await _api.saveConnectorOAuthApp(
      connectorCode: connectorCode,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      enabled: enabled,
    );
    ref.invalidate(adminConnectorOAuthAppsProvider);
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
