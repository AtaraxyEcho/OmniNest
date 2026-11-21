import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

import 'desktop_test_harness.dart';

final AdminPage<AdminSessionItem> _page = AdminPage<AdminSessionItem>(
  items: [
    AdminSessionItem(
      id: 's-1',
      userId: 'u-2',
      username: 'jun',
      clientPlatform: 'windows',
      deviceId: 'd-123456789',
      deviceName: 'Studio PC',
      ipAddress: '192.168.1.24',
      issuedAt: '2026-11-14T08:00:00Z',
      expiresAt: '2026-12-14T08:00:00Z',
      lastActiveAt: '2026-11-14T12:30:00Z',
    ),
    AdminSessionItem(
      id: 's-2',
      userId: 'u-3',
      username: 'lea',
      clientPlatform: 'web',
      ipAddress: '10.0.0.8',
      issuedAt: '2026-11-10T08:00:00Z',
      expiresAt: '2026-12-10T08:00:00Z',
      lastActiveAt: '2026-11-11T09:00:00Z',
      revokedAt: '2026-11-11T10:00:00Z',
    ),
  ],
  page: 0,
  size: 10,
  totalElements: 2,
  totalPages: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('托管态会话分区画一张卡：筛选 chip + 会话行 + 翻页', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          adminSessionPageProvider.overrideWith((ref, query) async => _page),
        ],
        child: wrapDesktop(
          const DesktopShellScope(
            hosted: true,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: AdminSessionsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('jun'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Studio PC'), findsOneWidget);
    expect(find.text('windows'), findsWidgets);
    expect(find.text('Force-signed out'), findsOneWidget);
    expect(find.text('active: 1 / 2'), findsOneWidget);
    expect(find.byTooltip('First page'), findsOneWidget);
    // 保留期默认 30 天，chip 选中态来自 state。
    expect(find.text('Keep 30 days'), findsOneWidget);
  });
}
