// 账户面板 → 系统页的跳转编排守卫。
//
// 面板是 modal 路由，页面是按策略透明的推入路由。同帧 pop + push 会让两条
// 动画并发（整屏玻璃模糊与两层内容同帧重绘），并且下滑中的面板与遮罩会从
// 新页面底下透出来。这里判三件事：跳转确实被推迟到面板退场之后、减弱动效下
// 跳转照常发生、以及不会重复入栈。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_account_sheet.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _profileMarker = 'PROFILE_PAGE';

/// 面板内容封顶 85% 视口且可滚动，'设置' 落在折叠线以下。
/// `dragUntilVisible` 的 finder 本来就能命中离屏节点，所以要靠 ensureVisible
/// 真正把它滚进视口再点。
Future<void> _tapSettingsRow(WidgetTester tester) async {
  await tester.ensureVisible(find.text('设置'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('设置'));
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          // 覆盖必须发生在 MaterialApp 之内、且在打开面板所用的 context 之上：
          // 外层 MediaQuery 会被应用自己的 MediaQuery 顶掉，
          // 而同级的 context 又读不到刚插入的覆盖。
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: disableAnimations),
            child: Builder(
              builder:
                  (inner) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showOmniAccountSheet(inner),
                        child: const Text('open'),
                      ),
                    ),
                  ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/profile',
        builder:
            (context, state) =>
                Scaffold(body: Center(child: Text(_profileMarker))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        unreadCountProvider.overrideWith(_ZeroUnread.new),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('面板还在退场时不发起跳转，退场完成后才入栈', (tester) async {
    final router = await _pump(tester);

    await _tapSettingsRow(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.text(_profileMarker),
      findsNothing,
      reason: '跳转被提前发起，面板与新页面动画并发，透明页会透出面板',
    );
    expect(
      router.routerDelegate.currentConfiguration.matches.length,
      1,
      reason: '退场未完成前不应有新的路由条目',
    );

    await tester.pumpAndSettle();

    expect(find.text(_profileMarker), findsOneWidget);
    expect(find.text('设置'), findsNothing, reason: '面板必须已关闭');
  });

  testWidgets('减弱动效下跳转照常发生，且不依赖看门狗兜底', (tester) async {
    await _pump(tester, disableAnimations: true);

    await _tapSettingsRow(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(_profileMarker),
      findsOneWidget,
      reason: 'noAnimation 的退场若不派发 dismissed，跳转就只能等 400ms 兜底',
    );
  });

  testWidgets('退场事件与兜底定时器都触发时也只入栈一次', (tester) async {
    final router = await _pump(tester);

    await _tapSettingsRow(tester);
    await tester.pumpAndSettle();
    // 兜底定时器在退场之后仍会到点，dispatch 必须被幂等拦住。
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(_profileMarker), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.matches.length,
      2,
      reason: '/ 与 /profile 各一枚，重复入栈会让返回键失灵',
    );
  });
}

class _ZeroUnread extends UnreadCountNotifier {
  @override
  int build() => 0;
}
