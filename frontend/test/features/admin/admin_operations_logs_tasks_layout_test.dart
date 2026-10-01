import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';

class _MockAdminOperationsApi extends Mock implements AdminOperationsApi {}

void main() {
  testWidgets('任务页在短桌面窗口中使用滚动布局', (tester) async {
    tester.view.physicalSize = const Size(1280, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => AdminPage<AdminTaskRecord>(
              items: [
                AdminTaskRecord(
                  id: 'task-1',
                  taskType: 'PHOTO_SCAN',
                  status: 'RUNNING',
                  progress: 40,
                  routingKey: 'omni.photo.scan',
                  errorSummary: null,
                  retryCount: 0,
                  createdAt: '2026-08-17T12:00:00Z',
                  updatedAt: '2026-08-17T12:00:00Z',
                ),
              ],
              page: 0,
              size: 10,
              totalElements: 1,
              totalPages: 1,
            ),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));
  });

  testWidgets('任务页勾选可重试任务出现批量操作条且禁用已完成行', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => AdminPage<AdminTaskRecord>(
              items: [
                AdminTaskRecord(
                  id: 'task-retryable',
                  taskType: 'PHOTO_SCAN',
                  status: 'FAILED',
                  progress: 40,
                  routingKey: 'omni.photo.scan',
                  errorSummary: null,
                  retryCount: 0,
                  createdAt: '2026-08-17T12:00:00Z',
                  updatedAt: '2026-08-17T12:00:00Z',
                ),
                AdminTaskRecord(
                  id: 'task-done',
                  taskType: 'PHOTO_SCAN',
                  status: 'COMPLETED',
                  progress: 100,
                  routingKey: 'omni.photo.scan',
                  errorSummary: null,
                  retryCount: 0,
                  createdAt: '2026-08-17T12:00:00Z',
                  updatedAt: '2026-08-17T12:00:00Z',
                ),
              ],
              page: 0,
              size: 10,
              totalElements: 2,
              totalPages: 1,
            ),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('批量重试'), findsNothing);
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(3));
    // 进度列已改为直角细槽：页面不再出现圆角 LinearProgressIndicator。
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final scrollable =
        find
            .ancestor(of: checkboxes.at(1), matching: find.byType(Scrollable))
            .first;
    await tester.scrollUntilVisible(
      checkboxes.at(1),
      -200,
      scrollable: scrollable,
    );

    await tester.tap(checkboxes.at(2));
    await tester.pump();
    expect(find.text('批量重试'), findsNothing, reason: '已完成任务不可勾选');

    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('批量重试'), findsOneWidget);
  });

  testWidgets('日志页在短桌面窗口中使用滚动布局', (tester) async {
    tester.view.physicalSize = const Size(1280, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminLogPageProvider((
            page: 0,
            size: 10,
            action: 'ALL',
            query: '',
            sort: 'createdAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminAuditLog>(
              items: [],
              page: 0,
              size: 10,
              totalElements: 0,
              totalPages: 0,
            ),
          ),
          adminLoginAuditPageProvider((
            page: 0,
            size: 10,
            result: 'ALL',
            platform: 'ALL',
            query: '',
            sort: 'createdAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminLoginAuditItem>(
              items: [],
              page: 0,
              size: 10,
              totalElements: 0,
              totalPages: 0,
            ),
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminLogsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));
    // 页头统计 Pill 已移除：计数由 Tab 徽章承载，页头不再重复。
    expect(find.byType(AdminStatusPill), findsNothing);
  });

  testWidgets('审计行详情按钮打开工位详情弹窗并渲染变更快照与负载', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminLogPageProvider((
            page: 0,
            size: 10,
            action: 'ALL',
            query: '',
            sort: 'createdAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminAuditLog>(
              items: [
                AdminAuditLog(
                  id: 'audit-1',
                  actorUserId: 'user-1',
                  action: 'ADMIN_CONFIG_UPDATE',
                  resourceType: 'config',
                  ipAddress: '127.0.0.1',
                  createdAt: '2026-09-28T10:00:00Z',
                  payload: {
                    'oldValue': 'false',
                    'newValue': 'true',
                    'reason': '启用功能',
                  },
                ),
              ],
              page: 0,
              size: 10,
              totalElements: 1,
              totalPages: 1,
            ),
          ),
          adminLoginAuditPageProvider((
            page: 0,
            size: 10,
            result: 'ALL',
            platform: 'ALL',
            query: '',
            sort: 'createdAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminLoginAuditItem>(
              items: [],
              page: 0,
              size: 10,
              totalElements: 0,
              totalPages: 0,
            ),
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminLogsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 双 Tab 徽章各自展示 totalElements：操作审计 1、登录日志 0。
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.info_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(find.text('操作审计详情'), findsOneWidget);
    expect(find.text('变更快照比对'), findsOneWidget);
    expect(find.text('旧值'), findsOneWidget);
    expect(find.text('新值'), findsOneWidget);
    expect(find.text('false'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
    expect(find.textContaining('"reason"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排队任务提供取消操作并在工位确认后调用接口', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockAdminOperationsApi();
    when(() => api.cancelTask('task-queued')).thenAnswer(
      (_) async => const AdminTaskRecord(
        id: 'task-queued',
        taskType: 'PHOTO_SCAN',
        status: 'CANCELLED',
        progress: 0,
        routingKey: 'omni.photo.scan',
        errorSummary: null,
        retryCount: 0,
        createdAt: '2026-09-28T09:00:00Z',
        updatedAt: '2026-09-28T09:00:00Z',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOperationsApiProvider.overrideWithValue(api),
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminTaskRecord>(
              items: [
                AdminTaskRecord(
                  id: 'task-queued',
                  taskType: 'PHOTO_SCAN',
                  status: 'QUEUED',
                  progress: 0,
                  routingKey: 'omni.photo.scan',
                  errorSummary: null,
                  retryCount: 0,
                  createdAt: '2026-09-28T09:00:00Z',
                  updatedAt: '2026-09-28T09:00:00Z',
                ),
              ],
              page: 0,
              size: 10,
              totalElements: 1,
              totalPages: 1,
            ),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 四张指标卡随队列态就绪。
    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('排队 / 就绪'), findsOneWidget);
    expect(find.text('死信'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.block_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);

    await tester.tap(find.text('取消任务'));
    await tester.pumpAndSettle();
    verify(() => api.cancelTask('task-queued')).called(1);
    expect(tester.takeException(), isNull);

    // 死信 Tab 空态为健康语义文案，与通用“无匹配”区分。
    await tester.tap(find.text('死信队列'));
    await tester.pumpAndSettle();
    expect(find.textContaining('队列运行健康'), findsOneWidget);
    expect(find.textContaining('未找到匹配数据'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('任务详情按钮打开处理器与队列信息弹窗', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminTaskRecord>(
              items: [
                AdminTaskRecord(
                  id: 'task-failed',
                  taskType: 'PHOTO_SCAN',
                  status: 'FAILED',
                  progress: 40,
                  routingKey: 'omni.photo.scan',
                  errorSummary: '扫描中断',
                  retryCount: 2,
                  createdAt: '2026-09-28T09:00:00Z',
                  updatedAt: '2026-09-28T09:05:00Z',
                ),
              ],
              page: 0,
              size: 10,
              totalElements: 1,
              totalPages: 1,
            ),
          ),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('处理器'), findsOneWidget);
    expect(find.text('队列'), findsOneWidget);
    expect(find.text('omni.photo.scan'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('扫描中断'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('死信任务丢弃需键入 ID 短码确认', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const dlqTaskId = '11111111-2222-3333-4444-555555555555';
    final api = _MockAdminOperationsApi();
    when(() => api.discardDlqTask(dlqTaskId)).thenAnswer(
      (_) async => const AdminTaskRecord(
        id: dlqTaskId,
        taskType: 'PHOTO_SCAN',
        status: 'DISCARDED',
        progress: 0,
        routingKey: 'omni.photo.scan',
        errorSummary: null,
        retryCount: 3,
        createdAt: '2026-09-28T09:00:00Z',
        updatedAt: '2026-09-28T09:00:00Z',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOperationsApiProvider.overrideWithValue(api),
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminTaskRecord>(
              items: [],
              page: 0,
              size: 10,
              totalElements: 0,
              totalPages: 0,
            ),
          ),
          adminDlqProvider.overrideWith(
            (ref) async => const [
              AdminDlqTask(
                id: dlqTaskId,
                taskType: 'PHOTO_SCAN',
                status: 'DLQ',
                progress: 0,
                errorSummary: '重试耗尽',
                updatedAt: '2026-09-28T09:00:00Z',
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('死信队列'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);

    // 未键入短码时确认不可用；键入 ID 前 8 位后放行。
    final confirmButton = find.widgetWithText(FilledButton, '丢弃');
    await tester.enterText(find.byType(TextField), '11111111');
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    verify(() => api.discardDlqTask(dlqTaskId)).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('任务页排队任务可勾选且批量栏同时提供取消与重试', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockAdminOperationsApi();
    const cancelledRecord = AdminTaskRecord(
      id: 'task-queued',
      taskType: 'VIDEO_SCAN',
      status: 'CANCELLED',
      progress: 0,
      routingKey: 'omni.video.scan',
      errorSummary: null,
      retryCount: 0,
      createdAt: '2026-09-30T08:00:00Z',
      updatedAt: '2026-09-30T08:00:00Z',
    );
    when(
      () => api.cancelTask('task-queued'),
    ).thenAnswer((_) async => cancelledRecord);
    // 批量取消后控制器会刷新任务页，重置为空列表避免无限循环。
    var cancelled = false;
    AdminPage<AdminTaskRecord> seedPage() => AdminPage<AdminTaskRecord>(
      items: [
        const AdminTaskRecord(
          id: 'task-queued',
          taskType: 'VIDEO_SCAN',
          status: 'QUEUED',
          progress: 0,
          routingKey: 'omni.video.scan',
          errorSummary: null,
          retryCount: 0,
          createdAt: '2026-09-30T08:00:00Z',
          updatedAt: '2026-09-30T08:00:00Z',
        ),
        const AdminTaskRecord(
          id: 'task-done',
          taskType: 'VIDEO_SCAN',
          status: 'COMPLETED',
          progress: 100,
          routingKey: 'omni.video.scan',
          errorSummary: null,
          retryCount: 0,
          createdAt: '2026-09-30T08:00:00Z',
          updatedAt: '2026-09-30T08:00:00Z',
        ),
      ],
      page: 0,
      size: 10,
      totalElements: 2,
      totalPages: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOperationsApiProvider.overrideWithValue(api),
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith((ref) async {
            // 取消成功后列表清空，模拟终态。
            return cancelled
                ? const AdminPage<AdminTaskRecord>(
                  items: [],
                  page: 0,
                  size: 10,
                  totalElements: 0,
                  totalPages: 0,
                )
                : seedPage();
          }),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 表头全选：仅排队行可勾（QUEUED 可取消，COMPLETED 既不可重试也不可取消）。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('批量重试'), findsOneWidget);
    expect(find.text('批量取消'), findsOneWidget);

    await tester.tap(find.text('批量取消'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '取消任务'));
    cancelled = true;
    await tester.pumpAndSettle();
    // 完成反馈 toast 持有定时器：冲刷时段后再校验，避免悬挂 Timer 断言。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    verify(() => api.cancelTask('task-queued')).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('死信队列勾选任务出现批量重试与丢弃操作条', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTaskPageProvider((
            page: 0,
            size: 10,
            status: 'ALL',
            taskType: 'ALL',
            query: '',
            sort: 'updatedAt',
            dir: 'desc',
          )).overrideWith(
            (ref) async => const AdminPage<AdminTaskRecord>(
              items: [],
              page: 0,
              size: 10,
              totalElements: 0,
              totalPages: 0,
            ),
          ),
          adminDlqProvider.overrideWith(
            (ref) async => const [
              AdminDlqTask(
                id: '11111111-2222-3333-4444-555555555555',
                taskType: 'PHOTO_SCAN',
                status: 'DLQ',
                progress: 0,
                errorSummary: '重试耗尽',
                updatedAt: '2026-09-28T09:00:00Z',
              ),
              AdminDlqTask(
                id: '99999999-8888-7777-6666-555555555555',
                taskType: 'VIDEO_SCAN',
                status: 'DLQ',
                progress: 20,
                errorSummary: '处理器异常',
                updatedAt: '2026-09-28T09:30:00Z',
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: const AdminTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('死信队列'));
    await tester.pumpAndSettle();

    // 死信行全部可勾：表头全选后批量条同时提供批量重试与丢弃。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('批量重试'), findsOneWidget);
    expect(find.text('丢弃'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });
}
