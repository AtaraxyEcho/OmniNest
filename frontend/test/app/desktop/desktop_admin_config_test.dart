import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

import 'desktop_test_harness.dart';

const AdminConfigManagementView _view = AdminConfigManagementView(
  items: [
    AdminConfigEntry(
      key: 'media.transcode.enabled',
      value: 'true',
      valueType: 'BOOLEAN',
      category: 'MEDIA',
      refreshScope: 'NONE',
      updatedAt: '2026-11-14T09:00:00Z',
      description: 'Enable transcoding for new uploads.',
    ),
    AdminConfigEntry(
      key: 'storage.defaultQuotaGb',
      value: '50',
      valueType: 'NUMBER',
      category: 'STORAGE',
      refreshScope: 'RESTART_REQUIRED',
      updatedAt: '2026-11-14T09:00:00Z',
      description: 'Storage assigned to newly created users.',
    ),
  ],
);

Future<void> _pumpConfig(WidgetTester tester) async {
  tester.view.physicalSize = kDesktopViewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: desktopSeedOverrides(),
      child: wrapDesktop(
        const DesktopShellScope(
          hosted: true,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: AdminConfigPage(view: _view),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('托管态配置分区画控制台：分组轨 + 行式编辑 + 保存条', (tester) async {
    await _pumpConfig(tester);

    expect(tester.takeException(), isNull);
    // 两行配置的键都出现在副标题里。
    expect(find.textContaining('media.transcode.enabled'), findsOneWidget);
    expect(find.textContaining('storage.defaultQuotaGb'), findsOneWidget);
    // 布尔项用开关；输入框两枚：顶部搜索 + 数值项。
    expect(find.byType(DesktopToggle), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    // 需重启的配置带标签；会话历史此时为空。
    expect(find.text('Restart Required'), findsOneWidget);
    expect(find.text('No changes this session.'), findsOneWidget);

    // 改一个值后出现浮动保存条；放弃后消失。
    await tester.tap(find.byType(DesktopToggle));
    await tester.pump();
    expect(find.textContaining('unsaved'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(find.textContaining('unsaved'), findsNothing);
  });

  testWidgets('复核弹窗列出旧值与新值，取消后草稿仍在', (tester) async {
    await _pumpConfig(tester);

    await tester.tap(find.byType(DesktopToggle));
    await tester.pump();

    await tester.tap(find.widgetWithText(DesktopButton, 'Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.takeException(), isNull);
    expect(find.text('1 change(s) to apply'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
    expect(find.text('false'), findsOneWidget);

    await tester.tap(find.widgetWithText(DesktopButton, 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 取消不丢草稿：保存条仍在。
    expect(find.textContaining('unsaved'), findsOneWidget);
  });
}
