import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_analytics.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/presentation/pages/admin_overview_page.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_trend_charts.dart';

AdminConsoleSummary _fakeSummary() {
  return AdminConsoleSummary(
    users: AdminUserStats(
      total: 12,
      active: 10,
      disabled: 2,
      roleCounts: const {'SUPER_ADMIN': 1, 'ADMIN': 2},
    ),
    roles: const [],
    configs: AdminConfigStats(
      total: 48,
      hot: 12,
      nextTask: 0,
      restartRequired: 0,
    ),
    tasks: AdminTaskStats(
      total: 1428,
      queued: 3,
      running: 2,
      completed: 1360,
      failed: 5,
      cancelled: 2,
      dlq: 1,
    ),
    storage: AdminStorageStats(
      fileCount: 4280,
      folderCount: 120,
      objectCount: 5400,
      usedBytes: 842500000000,
      externalAccountCount: 0,
    ),
    health: const [
      AdminHealthItem(name: 'PostgreSQL', status: 'UP', detail: '2ms'),
      AdminHealthItem(name: 'Redis', status: 'UP', detail: '1ms'),
    ],
  );
}

/// 近 7 日分析数据：用户/存储逐日增长、任务吞吐含失败堆叠、负载快照。
AdminAnalytics _fakeAnalytics() {
  return AdminAnalytics(
    userGrowth: [
      for (var i = 0; i < 7; i++)
        DailyMetric(
          date: '2026-09-${(23 + i).toString().padLeft(2, '0')}',
          value: 8 + i,
        ),
    ],
    taskThroughput: [
      for (var i = 0; i < 7; i++)
        DailyTaskMetric(
          date: '2026-09-${(23 + i).toString().padLeft(2, '0')}',
          completed: 40 + i * 6,
          failed: i % 3,
          running: 2,
        ),
    ],
    storageGrowth: [
      for (var i = 0; i < 7; i++)
        DailyMetric(
          date: '2026-09-${(23 + i).toString().padLeft(2, '0')}',
          value: 800000000000 + i * 7000000000,
        ),
    ],
    currentLoad: const SystemLoadSnapshot(
      cpuUsage: 18,
      memoryUsage: 26,
      diskUsage: 41,
      jvmHeapUsage: 36,
    ),
  );
}

Future<void> _pumpOverview(
  WidgetTester tester, {
  AdminAnalytics? analytics,
  Size viewport = const Size(1440, 900),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAnalyticsProvider.overrideWith(
          (ref, days) async =>
              analytics ??
              const AdminAnalytics(
                userGrowth: [],
                taskThroughput: [],
                storageGrowth: [],
                currentLoad: SystemLoadSnapshot(
                  cpuUsage: 0,
                  memoryUsage: 0,
                  diskUsage: 0,
                  jvmHeapUsage: 0,
                ),
              ),
        ),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminOverviewPage(summary: _fakeSummary()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('概览页三行式：KPI 卡 + 趋势双图 + 服务健康通栏表同时渲染', (tester) async {
    await _pumpOverview(tester, analytics: _fakeAnalytics());

    // 行 1：4 张紧凑指标卡；趋势徽标取用户/吞吐/存储三个末两点对比。
    expect(find.byType(AdminMetricCard), findsNWidgets(4));
    expect(find.byType(AdminTrendBadge), findsNWidgets(3));
    // 行 2：1 张吞吐柱状图 + 用户/存储 2 条细线折线。
    expect(find.byType(AdminThroughputBarChart), findsOneWidget);
    expect(find.byType(AdminHairlineLineChart), findsNWidgets(2));
    // 行 3：服务健康通栏表渲染健康条目与状态标签，不再保留下钻操作列。
    expect(find.text('PostgreSQL'), findsOneWidget);
    expect(find.byType(AdminStatusTag), findsNWidgets(2));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AdminOverviewPage)),
    );
    expect(find.text(l10n.adminServiceInspect), findsNothing);
    // 概览不消费审计流，不渲染审计入口。
    expect(find.text(l10n.adminRecentAudit), findsNothing);
    expect(find.text('USER_AUTH'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('概览页空 analytics 时趋势面板降级为空文案且不阻塞', (tester) async {
    await _pumpOverview(tester);

    // 吞吐面板 1 处 + 增长面板 2 处空文案。
    expect(find.byType(AdminThroughputBarChart), findsNothing);
    expect(find.byType(AdminHairlineLineChart), findsNothing);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AdminOverviewPage)),
    );
    expect(find.text(l10n.adminNoTrendData), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏趋势行堆叠为两块面板且无布局异常', (tester) async {
    await _pumpOverview(
      tester,
      analytics: _fakeAnalytics(),
      viewport: const Size(900, 900),
    );

    expect(find.byType(AdminThroughputBarChart), findsOneWidget);
    expect(find.byType(AdminHairlineLineChart), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('页头刷新控制：默认关闭档 + 手动刷新按钮，可切换 30 秒档', (tester) async {
    await _pumpOverview(tester, analytics: _fakeAnalytics());
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AdminOverviewPage)),
    );

    // 三档分段（默认关闭）与手动刷新按钮同时渲染。
    expect(find.text(l10n.adminOverviewRefreshOff), findsOneWidget);
    expect(find.text(l10n.adminOverviewRefresh30s), findsOneWidget);
    expect(find.text(l10n.adminOverviewRefresh5m), findsOneWidget);
    expect(find.byTooltip(l10n.adminOverviewAutoRefresh), findsOneWidget);
    expect(find.byTooltip(l10n.adminRefresh), findsOneWidget);

    // 切换 30 秒档：轮询器随之保活重建，手动刷新可用，无异常。
    await tester.tap(find.text(l10n.adminOverviewRefresh30s));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.adminRefresh));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 切回关闭档收起轮询，不抛定时器悬挂。
    await tester.tap(find.text(l10n.adminOverviewRefreshOff));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
