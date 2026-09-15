import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/desktop_close_confirm_dialog.dart';
import 'package:omninest/core/window/desktop_close_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesktopCloseFlow.instance.reset();
  });

  Widget buildHostApp() {
    return MaterialApp(
      navigatorKey: desktopCloseNavigatorKey,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OmniNestTheme.light(),
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }

  test('关闭动作偏好支持记忆、覆盖与清除', () async {
    expect(await DesktopCloseFlow.instance.readRememberedAction(), isNull);

    await DesktopCloseFlow.instance.rememberAction(DesktopCloseAction.exitApp);
    expect(
      await DesktopCloseFlow.instance.readRememberedAction(),
      DesktopCloseAction.exitApp,
    );

    await DesktopCloseFlow.instance.rememberAction(
      DesktopCloseAction.minimizeToTray,
    );
    expect(
      await DesktopCloseFlow.instance.readRememberedAction(),
      DesktopCloseAction.minimizeToTray,
    );

    await DesktopCloseFlow.instance.rememberAction(null);
    expect(await DesktopCloseFlow.instance.readRememberedAction(), isNull);
  });

  test('导航未就绪时关闭回退为隐藏到托盘', () async {
    var hidden = false;
    var quit = false;
    DesktopCloseFlow.instance.bind(
      hideWindow: () async => hidden = true,
      quitApp: () async => quit = true,
    );

    await DesktopCloseFlow.instance.handleWindowCloseRequest();

    expect(hidden, isTrue);
    expect(quit, isFalse);
  });

  testWidgets('未记住偏好时弹出确认窗，取消则保持窗口现状', (tester) async {
    var hidden = false;
    var quit = false;
    DesktopCloseFlow.instance.bind(
      hideWindow: () async => hidden = true,
      quitApp: () async => quit = true,
    );
    await tester.pumpWidget(buildHostApp());

    final flowFuture = DesktopCloseFlow.instance.handleWindowCloseRequest();
    await tester.pumpAndSettle();

    expect(find.byType(DesktopCloseConfirmDialog), findsOneWidget);

    await tester.tap(find.text('取消'));
    await flowFuture;

    expect(hidden, isFalse);
    expect(quit, isFalse);
    expect(await DesktopCloseFlow.instance.readRememberedAction(), isNull);
  });

  testWidgets('选择最小化到托盘并勾选记住后写回偏好', (tester) async {
    var hidden = false;
    var quit = false;
    DesktopCloseFlow.instance.bind(
      hideWindow: () async => hidden = true,
      quitApp: () async => quit = true,
    );
    await tester.pumpWidget(buildHostApp());

    final flowFuture = DesktopCloseFlow.instance.handleWindowCloseRequest();
    await tester.pumpAndSettle();

    await tester.tap(find.text('记住我的选择，下次不再询问'));
    await tester.pump();
    await tester.tap(find.text('最小化到托盘'));
    await flowFuture;

    expect(hidden, isTrue);
    expect(quit, isFalse);
    expect(
      await DesktopCloseFlow.instance.readRememberedAction(),
      DesktopCloseAction.minimizeToTray,
    );
  });

  testWidgets('选择退出程序后执行退出回调', (tester) async {
    var hidden = false;
    var quit = false;
    DesktopCloseFlow.instance.bind(
      hideWindow: () async => hidden = true,
      quitApp: () async => quit = true,
    );
    await tester.pumpWidget(buildHostApp());

    final flowFuture = DesktopCloseFlow.instance.handleWindowCloseRequest();
    await tester.pumpAndSettle();

    await tester.tap(find.text('退出程序'));
    await flowFuture;

    expect(quit, isTrue);
    expect(hidden, isFalse);
    expect(await DesktopCloseFlow.instance.readRememberedAction(), isNull);
  });

  testWidgets('弹窗展示期间重复关闭请求被忽略', (tester) async {
    DesktopCloseFlow.instance.bind(
      hideWindow: () async {},
      quitApp: () async {},
    );
    await tester.pumpWidget(buildHostApp());

    final flowFuture = DesktopCloseFlow.instance.handleWindowCloseRequest();
    await tester.pumpAndSettle();
    unawaited(DesktopCloseFlow.instance.handleWindowCloseRequest());
    await tester.pumpAndSettle();

    expect(find.byType(DesktopCloseConfirmDialog), findsOneWidget);

    await tester.tap(find.text('取消'));
    await flowFuture;
  });
}
