import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

import 'desktop_test_harness.dart';

final AdminPage<AdminTaskRecord> _tasks = AdminPage<AdminTaskRecord>(
  items: [
    AdminTaskRecord(
      id: 'k-1',
      taskType: 'THUMBNAIL_SCAN',
      description: 'Scanning the photo library',
      status: 'RUNNING',
      progress: 64,
      routingKey: 'media',
      errorSummary: null,
      retryCount: 0,
      createdAt: '2026-11-14T09:00:00Z',
      updatedAt: '2026-11-14T09:04:00Z',
      ownerLabel: 'mira',
    ),
    AdminTaskRecord(
      id: 'k-2',
      taskType: 'TRANSCODE',
      description: 'Aperture · 4K HDR',
      status: 'FAILED',
      progress: 0,
      routingKey: 'video',
      errorSummary: 'Encoder exited with code 1',
      retryCount: 1,
      createdAt: '2026-11-14T08:00:00Z',
      updatedAt: '2026-11-14T08:20:00Z',
    ),
  ],
  page: 0,
  size: 10,
  totalElements: 2,
  totalPages: 1,
);

final AdminPage<AdminAuditLog> _audits = AdminPage<AdminAuditLog>(
  items: [
    AdminAuditLog(
      id: 'a-1',
      actorLabel: 'Mira Han',
      action: 'ADMIN_CONFIG_UPDATE',
      description: 'Changed the default quota',
      resourceType: 'CONFIG',
      ipAddress: '192.168.1.10',
      createdAt: '2026-11-14T09:12:00Z',
    ),
  ],
  page: 0,
  size: 10,
  totalElements: 1,
  totalPages: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHosted(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(
          DesktopShellScope(
            hosted: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('托管态任务分区画一张卡：分段页签 + 状态/类型 chips + 任务行', (tester) async {
    await pumpHosted(
      tester,
      ProviderScope(
        overrides: [
          adminTaskPageProvider.overrideWith((ref, query) async => _tasks),
          adminDlqProvider.overrideWith((ref) async => const <AdminDlqTask>[]),
        ],
        child: const AdminTasksPage(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Scanning the photo library'), findsOneWidget);
    expect(find.text('Aperture · 4K HDR'), findsOneWidget);
    expect(find.text('Running'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Task List'), findsOneWidget);
    expect(find.text('Dead Letter Queue'), findsOneWidget);
    // 翻页条换成首/前/页码/后/末，单页时只有一颗页码按钮。
    expect(find.byTooltip('Jump to'), findsOneWidget);
  });

  testWidgets('托管态日志分区画一张卡：页签 + 动作 chips + 审计行', (tester) async {
    await pumpHosted(
      tester,
      ProviderScope(
        overrides: [
          adminLogPageProvider.overrideWith((ref, query) async => _audits),
          adminLoginAuditPageProvider.overrideWith(
            (ref, query) async => AdminPage<AdminLoginAuditItem>(
              items: const [],
              page: 0,
              size: 10,
              totalElements: 0,
              totalPages: 1,
            ),
          ),
        ],
        child: const AdminLogsPage(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Changed the default quota'), findsOneWidget);
    expect(find.textContaining('Mira Han'), findsWidgets);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.textContaining('Operation Audit'), findsWidgets);
  });
}
