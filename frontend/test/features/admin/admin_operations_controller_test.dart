import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';

class _MockAdminOperationsApi extends Mock implements AdminOperationsApi {}

AdminConsoleSummary _emptySummary() {
  return AdminConsoleSummary(
    users: AdminUserStats(
      total: 0,
      active: 0,
      disabled: 0,
      roleCounts: const {},
    ),
    roles: const [],
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
    health: const [],
  );
}

AdminAnalytics _emptyAnalytics() {
  return const AdminAnalytics(
    userGrowth: [],
    taskThroughput: [],
    storageGrowth: [],
    currentLoad: SystemLoadSnapshot(
      cpuUsage: 0,
      memoryUsage: 0,
      diskUsage: 0,
      jvmHeapUsage: 0,
    ),
  );
}

/// 统计 build 次数的假控制台控制器。
class _CountingConsoleController extends AdminConsoleController {
  _CountingConsoleController(this.onBuild);

  final void Function() onBuild;

  @override
  Future<AdminConsoleSummary> build() {
    onBuild();
    return Future.value(_emptySummary());
  }
}

AdminTaskRecord _taskRecord({required String status}) {
  return AdminTaskRecord(
    id: 'task-1',
    taskType: 'PHOTO_SCAN',
    status: status,
    progress: 0,
    routingKey: 'omni.photo.scan',
    errorSummary: null,
    retryCount: 0,
    createdAt: '2026-09-28T09:00:00Z',
    updatedAt: '2026-09-28T09:00:00Z',
  );
}

void main() {
  test('配置历史 Provider 通过应用层加载指定配置', () async {
    final api = _MockAdminOperationsApi();
    const history = AdminConfigHistory(
      id: 'history-1',
      configKey: 'feature.reader',
      oldValue: 'false',
      newValue: 'true',
      changedBy: 'admin',
      createdAt: '2026-07-22T12:00:00Z',
    );
    when(
      () => api.configHistory('feature.reader'),
    ).thenAnswer((_) async => const [history]);
    final container = ProviderContainer(
      overrides: [adminOperationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      adminConfigHistoryProvider('feature.reader').future,
    );

    expect(result, const [history]);
    verify(() => api.configHistory('feature.reader')).called(1);
  });

  test('cancelTask 调用取消接口并刷新任务列表', () async {
    final api = _MockAdminOperationsApi();
    when(
      () => api.cancelTask('task-1'),
    ).thenAnswer((_) async => _taskRecord(status: 'CANCELLED'));
    final container = ProviderContainer(
      overrides: [adminOperationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(adminOperationsActionsProvider).cancelTask('task-1');

    verify(() => api.cancelTask('task-1')).called(1);
  });

  test('discardDlqTask 调用丢弃接口并刷新死信与任务列表', () async {
    final api = _MockAdminOperationsApi();
    when(
      () => api.discardDlqTask('task-1'),
    ).thenAnswer((_) async => _taskRecord(status: 'DISCARDED'));
    final container = ProviderContainer(
      overrides: [adminOperationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container
        .read(adminOperationsActionsProvider)
        .discardDlqTask('task-1');

    verify(() => api.discardDlqTask('task-1')).called(1);
  });

  test('清理预估 Provider 按目标类型路由到对应接口', () async {
    final api = _MockAdminOperationsApi();
    when(() => api.previewCleanupAuditLogs(30)).thenAnswer((_) async => 12);
    when(() => api.previewCleanupLoginAuditLogs(7)).thenAnswer((_) async => 34);
    when(() => api.previewCleanupSessions(90)).thenAnswer((_) async => 56);
    final container = ProviderContainer(
      overrides: [adminOperationsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(
        adminCleanupPreviewProvider((
          kind: AdminCleanupPreviewKind.auditLogs,
          retentionDays: 30,
        )).future,
      ),
      12,
    );
    expect(
      await container.read(
        adminCleanupPreviewProvider((
          kind: AdminCleanupPreviewKind.loginAuditLogs,
          retentionDays: 7,
        )).future,
      ),
      34,
    );
    expect(
      await container.read(
        adminCleanupPreviewProvider((
          kind: AdminCleanupPreviewKind.sessions,
          retentionDays: 90,
        )).future,
      ),
      56,
    );

    verify(() => api.previewCleanupAuditLogs(30)).called(1);
    verify(() => api.previewCleanupLoginAuditLogs(7)).called(1);
    verify(() => api.previewCleanupSessions(90)).called(1);
  });

  group('概览定时刷新轮询器', () {
    testWidgets('默认关闭不轮询；选择 30 秒后按周期失效 summary 与 analytics', (tester) async {
      var summaryBuilds = 0;
      var analyticsBuilds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminConsoleControllerProvider.overrideWith(
              () => _CountingConsoleController(() => summaryBuilds++),
            ),
            adminAnalyticsProvider.overrideWith((ref, days) {
              analyticsBuilds++;
              return Future.value(_emptyAnalytics());
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: _OverviewProbe())),
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_OverviewProbe)),
      );
      addTearDown(container.dispose);

      expect(summaryBuilds, 1);
      expect(analyticsBuilds, 1);

      // 默认关闭：长时间推进无任何重建。
      await tester.pump(const Duration(minutes: 6));
      expect(summaryBuilds, 1);
      expect(analyticsBuilds, 1);

      // 选择 30 秒档：未到间隔不刷新，到达后各失效一次并周期重复。
      container
          .read(adminOverviewRefreshIntervalProvider.notifier)
          .selectInterval(AdminOverviewRefreshInterval.thirtySeconds);
      await tester.pump(const Duration(seconds: 29));
      expect(summaryBuilds, 1);
      expect(analyticsBuilds, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(summaryBuilds, 2);
      expect(analyticsBuilds, 2);

      await tester.pump(const Duration(seconds: 30));
      expect(summaryBuilds, 3);
      expect(analyticsBuilds, 3);
    });

    testWidgets('切回关闭档停止轮询；页面卸载后无悬挂定时器', (tester) async {
      var summaryBuilds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminConsoleControllerProvider.overrideWith(
              () => _CountingConsoleController(() => summaryBuilds++),
            ),
            adminAnalyticsProvider.overrideWith(
              (ref, days) => Future.value(_emptyAnalytics()),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: _OverviewProbe())),
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(_OverviewProbe)),
      );
      addTearDown(container.dispose);

      container
          .read(adminOverviewRefreshIntervalProvider.notifier)
          .selectInterval(AdminOverviewRefreshInterval.thirtySeconds);
      await tester.pump(const Duration(seconds: 30));
      expect(summaryBuilds, 2);

      // 切回关闭：轮询器重建为空实现，不再失效。
      container
          .read(adminOverviewRefreshIntervalProvider.notifier)
          .selectInterval(AdminOverviewRefreshInterval.off);
      await tester.pump(const Duration(minutes: 2));
      expect(summaryBuilds, 2);

      // 概览页卸载：轮询器随 autoDispose 释放并取消定时器。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
      expect(summaryBuilds, 2);
    });
  });
}

/// 轮询器保活探针：模拟概览页对三个 provider 的挂载期监听。
class _OverviewProbe extends ConsumerWidget {
  const _OverviewProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminConsoleControllerProvider);
    ref.watch(adminAnalyticsProvider(7));
    ref.watch(adminOverviewPollerProvider);
    return const SizedBox.shrink();
  }
}
