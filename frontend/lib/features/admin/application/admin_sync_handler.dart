import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/application/admin_user_controller.dart';

/// 管理作用域实时失效刷新处理器。
class AdminSyncHandler implements RealtimeScopeHandler {
  AdminSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _auxiliaryRevisions = RealtimeRevisionTracker();

  @override
  RealtimeScope get scope => RealtimeScope.admin;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) {
    final session = ref.read(authSessionProvider);
    if (!session.hasValue) return true;
    final permissions = session.value?.user?.permissions ?? const <String>{};
    return permissions.any(
      (code) =>
          code.startsWith('system:') ||
          code == 'task:admin' ||
          code == 'media:library:manage' ||
          code == 'photo:admin',
    );
  }

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    final auxiliary = _auxiliaryRevisions.pending(invalidations);
    final refreshes = <Future<Object?>>[];
    if (auxiliary.isNotEmpty && ref.exists(adminConsoleSummaryProvider)) {
      refreshes.add(ref.refresh(adminConsoleSummaryProvider.future));
    }
    if (auxiliary.isNotEmpty) {
      _refreshMountedProviders(refreshes);
    }
    await Future.wait(refreshes);
    _auxiliaryRevisions.markCompleted(auxiliary);
    var refreshedMainModule = false;
    if (ref.exists(adminUserControllerProvider)) {
      await ref.read(adminUserControllerProvider.future);
      await ref.read(adminUserControllerProvider.notifier).refreshUsers();
      refreshedMainModule = true;
    }
    if (ref.exists(adminConsoleControllerProvider)) {
      ref.invalidate(adminConsoleControllerProvider);
      await ref.read(adminConsoleControllerProvider.future);
      refreshedMainModule = true;
    }
    if (!refreshedMainModule) return false;
    _auxiliaryRevisions.clear(invalidations);
    return true;
  }

  void _refreshMountedProviders(List<Future<Object?>> refreshes) {
    // 分页 Provider 按当前筛选条件创建，统一失效即可让活动实例按新条件重新请求。
    ref.invalidate(adminTaskPageProvider);
    ref.invalidate(adminLogPageProvider);
    ref.invalidate(adminSessionPageProvider);
    ref.invalidate(adminLoginAuditPageProvider);
    if (ref.exists(adminRolesProvider)) {
      refreshes.add(ref.refresh(adminRolesProvider.future));
    }
    if (ref.exists(adminConfigsProvider)) {
      refreshes.add(ref.refresh(adminConfigsProvider.future));
    }
    if (ref.exists(adminTasksProvider)) {
      refreshes.add(ref.refresh(adminTasksProvider.future));
    }
    if (ref.exists(adminDlqProvider)) {
      refreshes.add(ref.refresh(adminDlqProvider.future));
    }
    if (ref.exists(adminLogsProvider)) {
      refreshes.add(ref.refresh(adminLogsProvider.future));
    }
    if (ref.exists(adminMonitoringProvider)) {
      refreshes.add(ref.refresh(adminMonitoringProvider.future));
    }
    if (ref.exists(adminStorageProvider)) {
      refreshes.add(ref.refresh(adminStorageProvider.future));
    }
    if (ref.exists(adminExternalStorageProvider)) {
      refreshes.add(ref.refresh(adminExternalStorageProvider.future));
    }
    if (ref.exists(adminSessionsProvider)) {
      refreshes.add(ref.refresh(adminSessionsProvider.future));
    }
    if (ref.exists(adminLoginAuditProvider)) {
      refreshes.add(ref.refresh(adminLoginAuditProvider.future));
    }
    for (final days in ref.read(activeAdminAnalyticsDaysProvider)) {
      final analytics = adminAnalyticsProvider(days);
      if (ref.exists(analytics)) {
        refreshes.add(ref.refresh(analytics.future));
      }
    }
  }
}
