// 托管首页（Spatial Home）首屏唯一加载线的落点与数量守卫。
//
// 槽位占位改成静态块之后，托管首页首屏一处动画都没有；补上的区级线必须
// 同时满足两件事：整屏只有它一处加载动画，且它排在时间块之上而不是压住
// 眉标或把大时钟推离原位（头部顶距按视口 5% 计算）。
//
// 「数据就绪后撤线」没有单列用例：判定是六个 provider 的 isLoading 短路或，
// 要让线消失得把六个 provider 全部喂成数据，构造成本高于它所能证明的东西。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/pages/portal_page.dart';
import 'package:omninest/features/reader/domain/reader_dashboard.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把 Provider 钉在 loading：返回一个永不完成的 Future。
Future<T> _pending<T>() => Completer<T>().future;

Future<void> _pumpPendingHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        presetAppEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
        realtimeWeatherProvider.overrideWith((ref) => _pending<WeatherData>()),
        fileRecentEntriesProvider.overrideWith(
          (ref) => _pending<List<FileNode>>(),
        ),
        portalReaderDashboardProvider.overrideWith(
          (ref) => _pending<ReaderDashboard>(),
        ),
        portalMovieDashboardProvider.overrideWith(
          (ref) => _pending<MovieDashboard>(),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        routerConfig: _homeRouter(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// 用真实路由拓扑挂载门户：侧滑返回要经 `popRoute → maybePop` 才走到
/// 页面自己的 PopScope，`MaterialApp(home:)` 走的是另一条链路。
GoRouter _homeRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder:
          (context, state) => MobileShellScope(
            hosted: true,
            child: const Scaffold(body: PortalPage()),
          ),
    ),
  ],
);

/// 首页大时钟：页内唯一带 -4 字距的文本（衬线 hero 口径）。
final Finder _clock = find.byWidgetPredicate(
  (widget) => widget is Text && widget.style?.letterSpacing == -4,
);

void main() {
  testWidgets('托管首页首屏只有一条加载线，且没有任何转圈', (tester) async {
    await _pumpPendingHome(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileLoadingLine), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('加载线排在眉标之上，不挤走大时钟的居中轴', (tester) async {
    await _pumpPendingHome(tester);

    final line = tester.getRect(find.byType(MobileLoadingLine));
    expect(_clock, findsOneWidget, reason: '应能定位首页大时钟');
    final clock = tester.getRect(_clock);
    final header =
        find.ancestor(of: _clock, matching: find.byType(Column)).first;
    final eyebrow = find.descendant(
      of: header,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.letterSpacing == 1.65,
      ),
    );
    expect(eyebrow, findsOneWidget);
    final eyebrowRect = tester.getRect(eyebrow);

    // 舞台页边距 16：线只能占内容宽，不许压到舞台外。
    expect(line.left, greaterThanOrEqualTo(16.0));
    expect(line.right, lessThanOrEqualTo(374.0));
    expect(
      (line.left + line.right) / 2,
      closeTo(195.0, 1.0),
      reason: '线与手机档舞台同轴居中',
    );
    // 线在眉标之上，两者不得重叠。
    expect(line.bottom, lessThanOrEqualTo(eyebrowRect.top));
    // 线只让出自身 2px：它顶到时钟顶之间应仍是头部原本的留白加一行眉标，
    // 不该多出成段空档（那说明线挤进了头部的行间距里）。
    expect(clock.top - line.bottom, lessThan(eyebrowRect.height + 70.0));
  });

  // 门户是返回阶梯的最底一级。托管态下这层确认此前挂在非托管分支之后，
  // 手机上永远不挂载：一次侧滑 → popRoute 返回 false → 引擎结束 Activity。
  testWidgets('托管门户：一次侧滑只提示，再按一次才退出', (tester) async {
    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpPendingHome(tester);

    // 第一次：只该给出「再按一次」提示。提示本体走 toastification（需要
    // wrapper，本 harness 未装），所以断言盯契约：不得结束 Activity。
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      platformCalls,
      contains('SystemNavigator.pop'),
      reason: '第二次确认才真的退出；分支根路由上没有可弹层',
    );

    // 提示自带 2 秒自动消失的 Timer，不排干会在 teardown 报「timer pending」。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });
}
