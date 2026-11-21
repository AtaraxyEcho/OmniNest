import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart';
import 'package:omninest/app/desktop/desktop_shell.dart';
import 'package:omninest/app/desktop/desktop_sidebar.dart';
import 'package:omninest/app/desktop/desktop_title_bar.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_test_harness.dart';

/// 还原真实 `appRouterProvider` 的 StatefulShellRoute + 顶层 push 结构。
///
/// 简单路由测试里 `currentConfiguration.uri.path` 会正常变成详情路径；
/// 真实结构下它仍停在 branch，只有 `matches.last` 是压入的详情。
GoRouter _router() => GoRouter(
  initialLocation: '/portal',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => navigationShell,
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/portal',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/photos/:photoId',
      builder: (context, state) => const SizedBox.shrink(),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('push 详情时 active route 取栈顶而不是 branch', (tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/portal');

    router.push<void>('/photos/p-1');
    await tester.pump();
    await tester.pump();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/portal');
    expect(desktopActiveRoutePath(router), '/photos/p-1');
    expect(
      desktopShellModeForPath(desktopActiveRoutePath(router)),
      DesktopShellMode.immersive,
    );
  });

  testWidgets('真实 shell 路由下 push 照片详情后隐藏全部工作区 chrome', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: MaterialApp.router(
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
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(find.byType(DesktopPlayerBar), findsOneWidget);

    router.push<void>('/photos/p-1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.byType(DesktopPlayerBar), findsNothing);
  });
}
