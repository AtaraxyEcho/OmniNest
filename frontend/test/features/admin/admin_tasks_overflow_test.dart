import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/application/admin_console_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';

AdminPage<AdminTaskRecord> _fakePage(int count) {
  return AdminPage<AdminTaskRecord>(
    items: [
      for (var i = 0; i < count; i++)
        AdminTaskRecord(
          id: 'task-$i',
          taskType: 'PHOTO_SCAN',
          status: i % 2 == 0 ? 'RUNNING' : 'FAILED',
          progress: 40,
          routingKey: 'omni.photo.scan',
          errorSummary: null,
          retryCount: 0,
          createdAt: '2026-09-01T12:00:00Z',
          updatedAt: '2026-09-01T12:00:00Z',
          ownerUserId: 'user-$i',
          ownerLabel: 'member-$i',
        ),
    ],
    page: 0,
    size: 10,
    totalElements: count,
    totalPages: 1,
  );
}

AdminConsoleSummary _fakeSummary() {
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

class _FakeAdminConsoleController extends AdminConsoleController {
  @override
  Future<AdminConsoleSummary> build() => Future.value(_fakeSummary());
}

void main() {
  // AdminShell 的侧栏存储卡会消费 summary，测试内用固定值避免真实请求。
  final consoleOverride = adminConsoleControllerProvider.overrideWith(
    _FakeAdminConsoleController.new,
  );

  for (final size in [
    const Size(1280, 800),
    const Size(1366, 768),
    const Size(1536, 864),
    const Size(1600, 900),
    const Size(1100, 700),
    const Size(950, 650),
    const Size(1440, 620),
    const Size(1280, 500),
    const Size(1920, 1080),
    const Size(2560, 1440),
    const Size(3840, 2160),
  ]) {
    testWidgets('任务页 ${size.width}x${size.height} 无布局异常', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const query = (
        page: 0,
        size: 10,
        status: 'ALL',
        taskType: 'ALL',
        query: '',
        sort: 'updatedAt',
        dir: 'desc',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            consoleOverride,
            adminTaskPageProvider(
              query,
            ).overrideWith((ref) async => _fakePage(10)),
            adminDlqProvider.overrideWith(
              (ref) async => const <AdminDlqTask>[],
            ),
          ],
          child: MaterialApp(
            theme: OmniNestTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const AdminDashboardPage(),
          ),
        ),
      );
      final exception = tester.takeException();
      // ignore: avoid_print
      print('SIZE ${size.width}x${size.height} -> ${exception ?? 'OK'}');
      expect(exception, isNull);
    });
  }

  testWidgets('任务分区渲染归属人列', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consoleOverride,
          authSessionProvider.overrideWith(_AdminSessionNotifier.new),
          // 覆盖整个 family：分区内的查询记录由内部状态拼装，逐键覆盖易失配。
          adminTaskPageProvider.overrideWith(
            (ref, argument) async => _fakePage(3),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const AdminDashboardPage(initialSectionSegment: 'tasks'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 普通用户不再查看任务队列，管理员要靠归属人把失败任务对到人。
    expect(find.text('归属人'), findsOneWidget);
    expect(find.text('member-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 窄屏批量操作条：两操作并存时单行会挤出 360-390 视口，改用 Wrap 换行。
  testWidgets('360 宽任务页批量条操作簇落在 Wrap 内且不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTaskPageProvider.overrideWith(
            (ref, argument) async => _fakePage(6),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 表头全选：一次勾满可勾选行，批量条出现并进入两操作形态。
    final headerCheck = find.byType(Checkbox).first;
    await tester.ensureVisible(headerCheck);
    await tester.pumpAndSettle();
    await tester.tap(headerCheck);
    await tester.pumpAndSettle();

    final selectedLabel = find.textContaining('已选');
    expect(selectedLabel, findsWidgets);
    final cancel = find.text('取消选择');
    expect(cancel, findsOneWidget);
    expect(find.text('批量取消'), findsOneWidget);
    expect(find.text('批量重试'), findsOneWidget);
    final wrapFinder = find.ancestor(of: cancel, matching: find.byType(Wrap));
    expect(wrapFinder, findsOneWidget, reason: '操作簇必须由 Wrap 承载才会换行');
    // 已选数量始终在操作簇之前（同一行首列），换行只发生在操作簇内部。
    final batchRow = tester.widget<Row>(
      find.ancestor(of: wrapFinder, matching: find.byType(Row)).first,
    );
    expect((batchRow.children.first as Text).data, contains('已选'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏任务分区不再被外壳套第二层同轴滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consoleOverride,
          authSessionProvider.overrideWith(_AdminSessionNotifier.new),
          adminTaskPageProvider.overrideWith(
            (ref, argument) async => _fakePage(3),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const AdminDashboardPage(initialSectionSegment: 'tasks'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 外壳内容键的祖先链上不得再出现滚动容器；页内自带滚动是唯一一层。
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey(AdminSection.tasks)),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    // 页内滚动仍在。
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

/// 管理端外壳按权限挑选分区，会话里必须带 task:admin 才会渲染任务分区。
class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(
        id: 'admin-1',
        username: 'admin-it',
        role: 'ADMIN',
        permissions: const {'task:read', 'task:admin'},
      ),
    );
  }
}
