// 前置页（登录 / 首启 / 启动 / 分享）在样例里是 `.window` 之外的独立幕，
// 本身没有 `.titlebar`；但原生窗口是无边框的，缺了拖拽区与三键就无法移动、
// 最大化或关闭。这里断言壳层只给这些路由补窗口 chrome，工作区不重复画。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_shell.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_frame.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';

import 'desktop_test_harness.dart';

/// 中键字形只看 `WindowChromeState.isMaximized`；真实控制器要靠原生事件
/// 取这个值，测试里直接把状态种成「已最大化」，跳过平台通道。
class _MaximizedChrome extends WindowChromeController {
  @override
  WindowChromeState build() => const WindowChromeState(isMaximized: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAt(
    WidgetTester tester,
    String location, {
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        for (final path in const ['/portal', '/login'])
          GoRoute(
            path: path,
            builder:
                (context, state) => Center(
                  child: Text(
                    'route:${state.uri.path}',
                    key: const Key('page'),
                  ),
                ),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...desktopSeedOverrides(), ...overrides],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder:
              (context, child) => DesktopShellHost(
                router: router,
                child: child ?? const SizedBox.shrink(),
              ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  /// 缩放带由 8 个带 resize 光标的 MouseRegion 组成，与 `DesktopWindowFrame`
  /// 内的命中带一一对应。
  final resizeGrips = find.byWidgetPredicate(
    (widget) =>
        widget is MouseRegion &&
        (widget.cursor == SystemMouseCursors.resizeUpDown ||
            widget.cursor == SystemMouseCursors.resizeLeftRight ||
            widget.cursor == SystemMouseCursors.resizeUpLeftDownRight ||
            widget.cursor == SystemMouseCursors.resizeUpRightDownLeft),
  );

  testWidgets('无标题栏的前置页补上窗口三键与边缘缩放', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAt(tester, '/login');

      expect(find.byType(DesktopWindowFrame), findsOneWidget);
      expect(find.byType(DesktopWindowControls), findsOneWidget);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(resizeGrips, findsNWidgets(8));

      // 三键叠在 46px 的透明命中带里，不改页面自身布局：
      // 登录内容仍是整幅居中，页面文字没有被挤出视口。
      final page = tester.getRect(find.byKey(const Key('page')));
      expect(page.center.dx, closeTo(kDesktopViewport.width / 2, 1));
      expect(page.top, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('工作区只有标题栏那一套窗口三键', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAt(tester, '/portal');

      // 标题栏自带三键；工作区分支不得再叠一层 chrome，
      // 否则同一窗口会出现两套按钮与两条拖拽带。
      expect(find.byType(DesktopWindowControls), findsOneWidget);
      expect(find.byType(DesktopWindowFrame), findsOneWidget);
      expect(resizeGrips, findsNWidgets(8));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('最大化后中键换成还原字形', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAt(
        tester,
        '/login',
        overrides: [
          windowChromeControllerProvider.overrideWith(_MaximizedChrome.new),
        ],
      );

      // 样例 `Shell.tsx:64`：`win === "max" ? restore : maximize`。
      expect(find.byIcon(DesktopIcons.restore), findsOneWidget);
      expect(find.byIcon(DesktopIcons.maximize), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('移动形态不铺窗口 chrome', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpAt(tester, '/login');

      expect(find.byType(DesktopWindowControls), findsNothing);
      expect(find.byType(DesktopWindowFrame), findsNothing);
      expect(resizeGrips, findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
