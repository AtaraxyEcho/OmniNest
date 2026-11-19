import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/desktop_shell.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart';
import 'package:omninest/app/desktop/desktop_sidebar.dart';
import 'package:omninest/app/desktop/desktop_title_bar.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_boundary.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_test_harness.dart';

/// 记录全局播放键是否真的打到播放器上。
class _CountingActions implements MusicPortalActions {
  int toggles = 0;
  int syncCalls = 0;

  @override
  Future<void> togglePlayback() async {
    toggles++;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> previousTrack() async {}
  @override
  Future<void> nextTrack() async {}
  @override
  Future<void> playRecentTrack(String trackId) async {}
  @override
  Future<void> playTrackById(String trackId) async {}
  @override
  Future<void> playQueueAt(int index) async {}
  @override
  Future<void> playAlbum(MusicAlbum album) async {}
  @override
  Future<void> syncPlayback() async {
    syncCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  GoRouter buildRouter() => GoRouter(
    initialLocation: '/portal',
    routes: [
      for (final path in const [
        '/portal',
        '/video',
        '/photos',
        '/music',
        '/reader',
        '/files',
        '/admin',
        '/profile',
        '/notifications',
        '/music/now-playing',
        '/photos/p-1',
        '/reader/items/book-1',
        '/video/v-1',
        '/video/v-1/play',
      ])
        GoRoute(
          path: path,
          builder:
              (context, state) =>
                  Center(child: Text('route:${state.uri.path}')),
        ),
    ],
  );

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    Size viewport = kDesktopViewport,
    GoRouter? customRouter,
    MusicPortalActions? musicActions,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = customRouter ?? buildRouter();
    if (customRouter == null) {
      addTearDown(router.dispose);
    }
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(musicActions: musicActions),
        child: Builder(
          builder: (context) {
            return MaterialApp.router(
              debugShowCheckedModeBanner: false,
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              builder: (context, child) {
                container = ProviderScope.containerOf(context);
                return MediaQuery(
                  data: MediaQueryData(size: viewport, devicePixelRatio: 1),
                  child: DesktopShellHost(
                    router: router,
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
    return container;
  }

  double sidebarWidth(WidgetTester tester) =>
      tester.getSize(find.byType(DesktopSidebar)).width;

  testWidgets('工作区常驻标题栏 / 侧栏 / 播放条，内容区只放当前路由', (tester) async {
    await pumpShell(tester);

    expect(find.text('OmniNest'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Music'), findsWidgets);
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('route:/portal'), findsOneWidget);
    // 播放条读的是真实曲目，不是占位；侧栏 PINNED 演示条目与曲目同名，
    // 所以曲目断言限定在播放条子树内。
    expect(
      find.descendant(
        of: find.byType(DesktopPlayerBar),
        matching: find.text('Evening Drift'),
      ),
      findsOneWidget,
    );
    expect(find.text('Aoi Trio'), findsOneWidget);
  });

  testWidgets('账户菜单按样例提供背景库入口，不显示额外 Appearance 项', (tester) async {
    await pumpShell(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-account-button')),
    );
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Backdrop library'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
  });

  testWidgets('宽屏标题栏搜索胶囊按样例三栏网格保持窗口居中', (tester) async {
    await pumpShell(tester);

    final search = find.byKey(
      const ValueKey<String>('desktop-titlebar-search'),
    );
    final rect = tester.getRect(search);
    expect(rect.width, 520);
    // `.titlebar` 的内容盒从 14px 左内距开始，CSS grid 的中心因此是
    // `(14 + viewportWidth) / 2`，而不是窗口几何中心。
    expect(rect.center.dx, closeTo((14 + kDesktopViewport.width) / 2, 1));
  });

  testWidgets('播放条只有一层玻璃：描边面板与模糊背板同宽同高', (tester) async {
    await pumpShell(tester);

    final player = find.byType(DesktopPlayerBar);
    final glass = find.byKey(const ValueKey('desktop-player-bar-glass'));
    final panel = find.byKey(const ValueKey('desktop-player-bar-panel'));
    expect(
      find.descendant(of: player, matching: find.byType(DesktopGlassSurface)),
      findsOneWidget,
      reason: 'playerbar 自己就是一层玻璃，不能再垫第二层',
    );
    expect(glass, findsOneWidget);
    expect(panel, findsOneWidget);
    expect(tester.getSize(glass), const Size(1080, 66));
    expect(tester.getRect(panel), tester.getRect(glass));
    expect(tester.getRect(glass).left, 260);
    expect(tester.getRect(glass).bottom, 986);
  });

  testWidgets('窄屏播放条按 more.css 收成 860px 并保留 14px 外边距', (tester) async {
    await pumpShell(tester, viewport: const Size(1100, 800));

    final glass = find.byKey(const ValueKey('desktop-player-bar-glass'));
    expect(tester.getSize(glass), const Size(860, 66));
    expect(tester.getRect(glass).left, 120);
    expect(tester.getRect(glass).right, 980);
  });

  testWidgets('播放条保留样例的完整控件组，队列键可再次收起坞', (tester) async {
    final container = await pumpShell(tester);
    final player = find.byType(DesktopPlayerBar);

    for (final key in const <String>[
      'desktop-player-favorite',
      'desktop-player-mode',
      'desktop-player-previous',
      'desktop-player-play',
      'desktop-player-next',
      'desktop-player-queue',
      'desktop-player-mute',
      'desktop-player-volume',
      'desktop-player-expand',
    ]) {
      expect(
        find.descendant(of: player, matching: find.byKey(ValueKey(key))),
        findsOneWidget,
        reason: key,
      );
    }
    expect(
      find.descendant(of: player, matching: find.byTooltip('Open Now Playing')),
      findsOneWidget,
      reason: '样例 .pb-track 的 title 挂在整个按钮上',
    );

    final queue = find.byKey(const ValueKey('desktop-player-queue'));
    expect(container.read(desktopShellProvider).dockOpen, isFalse);
    await tester.tap(queue);
    await tester.pump();
    expect(container.read(desktopShellProvider).dockOpen, isTrue);
    expect(container.read(desktopShellProvider).dockTab, DesktopDockTab.queue);
    await tester.tap(queue);
    await tester.pump();
    expect(container.read(desktopShellProvider).dockOpen, isFalse);
  });

  testWidgets('壳层为路由内容提供 Material 祖先：TextField 不再报 No Material', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder:
              (context, state) => Padding(
                padding: const EdgeInsets.all(24),
                child: DesktopTextField(
                  controller: controller,
                  hint: 'Search all files',
                ),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpShell(tester, customRouter: router);

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    // 最近的 Material 祖先必须存在，否则 TextField 的断言会再次触发。
    expect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Material),
      ),
      findsWidgets,
    );
  });

  testWidgets('侧栏条目是键盘可达的按钮：Enter 打开对应页面', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester);

    // 样例侧栏条目是 `<button class="nav-item">`：Tab 能停、Enter/Space 能激活。
    // 命令面板按样例不再收录管理台/外观，键盘路径因此只能靠这里。
    final admin = find.text('Admin');
    expect(admin, findsOneWidget);
    expect(
      find.ancestor(of: admin, matching: find.byType(FocusableActionDetector)),
      findsWidgets,
    );
    expect(
      tester.getSemantics(admin).getSemanticsData().flagsCollection.isButton,
      isTrue,
    );
    // 外显 label 与行内文字合并后只能是一份，不能重复播报。
    expect(tester.getSemantics(admin).getSemanticsData().label, 'Admin');

    Focus.of(tester.element(admin)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('route:/admin'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Ctrl+B 折叠侧栏，再按一次展开', (tester) async {
    final container = await pumpShell(tester);
    expect(sidebarWidth(tester), DesktopMetrics.sidebarWidth);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(container.read(desktopShellProvider).sidebarExpanded, isFalse);
    expect(sidebarWidth(tester), DesktopMetrics.sidebarSlimWidth);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(sidebarWidth(tester), DesktopMetrics.sidebarWidth);
  });

  testWidgets('Ctrl+. 打开详情坞，Esc 逐层收束', (tester) async {
    final container = await pumpShell(tester);
    expect(container.read(desktopShellProvider).dockOpen, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 320));
    expect(container.read(desktopShellProvider).dockOpen, isTrue);
    expect(
      find.text('Select a title, track, or file to see its details here.'),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 320));
    expect(container.read(desktopShellProvider).dockOpen, isFalse);
  });

  testWidgets('Alt+2 切到影视空间，壳层不重建', (tester) async {
    await pumpShell(tester);
    final shellElement = tester.element(find.byType(DesktopShellHost));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('route:/video'), findsOneWidget);
    expect(tester.element(find.byType(DesktopShellHost)), same(shellElement));
    expect(find.text('OmniNest'), findsOneWidget);
  });

  testWidgets('通知面板列出真实通知并可全部已读', (tester) async {
    final container = await pumpShell(tester);
    container
        .read(desktopShellProvider.notifier)
        .setPanel(DesktopPanel.notifications);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Import finished'), findsOneWidget);
    expect(find.text('Transcode ready'), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('点通知行只标已读，不关面板也不跳转', (tester) async {
    final container = await pumpShell(tester);
    container
        .read(desktopShellProvider.notifier)
        .setPanel(DesktopPanel.notifications);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(find.text('Import finished'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 样例 `Shell.tsx:129`：行点击只 markNotifRead，面板保持打开，
    // 跳转属于行内那条独立动作链接。
    expect(find.text('1 unread'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(find.text('Transcode ready'), findsOneWidget);
  });

  testWidgets('Clear all 是全部标已读，不删记录', (tester) async {
    final container = await pumpShell(tester);
    container
        .read(desktopShellProvider.notifier)
        .setPanel(DesktopPanel.notifications);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('0 unread'), findsOneWidget);
    // 伪清空：行还在，只是没有未读了。
    expect(find.text('Import finished'), findsOneWidget);
  });

  testWidgets('命令面板跨模块聚合内容并支持范围筛选', (tester) async {
    final container = await pumpShell(tester);
    container.read(desktopShellProvider.notifier).setCommandPalette(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 结果列表是懒加载的，视口外的分组头不会被构建。
    expect(find.text('GO TO'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Aperture');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Aperture'), findsWidgets);
  });

  testWidgets('沉浸路由里全局键仍然生效：Alt+2 能切回来', (tester) async {
    await pumpShell(tester);
    final router = GoRouter.of(tester.element(find.text('route:/portal')));
    router.go('/video/v-1/play');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('route:/video/v-1/play'), findsOneWidget);

    // 样例只有一处 window keydown，导航键在任何页面都要能用。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('route:/video'), findsOneWidget);

    // Ctrl+B 同样不受沉浸页限制。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopShellHost)),
    );
    expect(container.read(desktopShellProvider).sidebarExpanded, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(container.read(desktopShellProvider).sidebarExpanded, isFalse);
  });

  testWidgets('桌面壳把音乐中心状态同步到播放会话', (tester) async {
    final actions = _CountingActions();
    final container = await pumpShell(tester, musicActions: actions);
    await container.read(musicCenterControllerProvider.future);
    await tester.pump();
    final before = actions.syncCalls;

    await container
        .read(musicCenterControllerProvider.notifier)
        .setPlaying(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // 桌面没有移动 MiniPlayerSlot 的常驻监听；壳层必须补上这一段，
    // 否则播放条只翻图标，音频引擎不会收到 play/pause。
    expect(actions.syncCalls, greaterThan(before));
  });

  testWidgets('Space 在常规页切播放，在沉浸页让位给页面', (tester) async {
    final actions = _CountingActions();
    await pumpShell(tester, musicActions: actions);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(actions.toggles, 1);

    final router = GoRouter.of(tester.element(find.text('route:/portal')));
    router.go('/video/v-1/play');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    // 播放页自己吃 Space（暂停/继续），全局通道不再抢。
    expect(actions.toggles, 1);
  });

  testWidgets('命令面板 scope 行是互斥 tab，选中态交给语义', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pumpShell(tester);
    container.read(desktopShellProvider.notifier).setCommandPalette(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final all = tester.getSemantics(find.text('All')).getSemanticsData();
    expect(all.flagsCollection.isSelected, Tristate.isTrue);
    expect(all.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    handle.dispose();
  });

  testWidgets('右键菜单按实测尺寸钳进视口，滚动与失焦都会收起', (tester) async {
    final container = await pumpShell(tester);
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;

    void openAt(Offset position) {
      container.read(desktopShellProvider.notifier).openMenu(position, const [
        DesktopMenuItem(label: 'Open'),
        DesktopMenuItem(label: 'Rename'),
        DesktopMenuItem.separator(),
        DesktopMenuItem(label: 'Download'),
        DesktopMenuItem(label: 'Share'),
        DesktopMenuItem(label: 'Delete', danger: true),
      ]);
    }

    // 靠右下角弹出：按 34px/行估算会低估分隔线与内边距，实测尺寸才不会越界。
    openAt(Offset(viewport.width - 12, viewport.height - 12));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final menu = tester.getRect(find.text('Delete'));
    expect(menu.right, lessThanOrEqualTo(viewport.width));
    expect(menu.bottom, lessThanOrEqualTo(viewport.height));

    // 样例 `Shell.tsx:299`：滚动（capture）收起菜单。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 24)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Delete'), findsNothing);

    // 窗口失焦同样收起。
    openAt(const Offset(300, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Delete'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('路由切换时顶部扫 2px 进度条，切换结束即收起', (tester) async {
    await pumpShell(tester);
    final router = GoRouter.of(tester.element(find.text('route:/portal')));

    router.go('/video');
    // 壳层把 location 变化放到帧后记录，这里两帧才走完一次 path 更新。
    await tester.pump();
    await tester.pump();
    // 入场动画进行中 = 路由正在切换（样例 `.route-load` 的窗口）。
    expect(find.byType(DesktopRouteProgressBar), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(DesktopRouteProgressBar), findsNothing);
    expect(find.text('route:/video'), findsOneWidget);
  });

  testWidgets('沉浸路由全屏覆盖：隐藏标题栏、侧栏、播放条和窗口控件', (tester) async {
    await pumpShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopShellHost)),
    );
    expect(container.read(desktopShellProvider).sidebarExpanded, isTrue);

    final router = GoRouter.of(tester.element(find.text('route:/portal')));
    for (final path in const [
      '/video/v-1/play',
      '/photos/p-1',
      '/reader/items/book-1',
      '/music/now-playing',
      '/video/v-1',
    ]) {
      router.go(path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.text('route:$path'), findsOneWidget, reason: path);
      expect(find.byType(DesktopTitleBar), findsNothing, reason: path);
      expect(find.byType(DesktopSidebar), findsNothing, reason: path);
      expect(find.byType(DesktopPlayerBar), findsNothing, reason: path);
      expect(find.text('OmniNest'), findsNothing, reason: path);
    }
  });

  test('路由 → 壳层姿态的判定覆盖公开页、沉浸页与常规页', () {
    expect(desktopShellModeForPath('/portal'), DesktopShellMode.chrome);
    expect(desktopShellModeForPath('/files'), DesktopShellMode.chrome);
    expect(desktopShellModeForPath('/admin/users'), DesktopShellMode.chrome);
    expect(desktopShellModeForPath('/login'), DesktopShellMode.standalone);
    expect(desktopShellModeForPath('/setup'), DesktopShellMode.standalone);
    expect(
      desktopShellModeForPath('/shared/photos/abc'),
      DesktopShellMode.standalone,
    );
    expect(desktopShellModeForPath('/s/token'), DesktopShellMode.standalone);
    expect(
      desktopShellModeForPath('/music/now-playing'),
      DesktopShellMode.immersive,
    );
    expect(
      desktopShellModeForPath('/reader/items/book-1'),
      DesktopShellMode.immersive,
    );
    expect(
      desktopShellModeForPath('/reader/items/book-1/chapters/chapter-1'),
      DesktopShellMode.immersive,
    );
    expect(
      desktopShellModeForPath('/video/v-1/play'),
      DesktopShellMode.immersive,
    );
    expect(
      desktopShellModeForPath('/reader/items/b-1/chapters/c-1'),
      DesktopShellMode.immersive,
    );
    expect(
      desktopShellModeForPath('/reader/comics/b-1/read'),
      DesktopShellMode.immersive,
    );
    expect(
      desktopShellModeForPath('/photos/p-1/edit'),
      DesktopShellMode.immersive,
    );
  });

  test('历史栈支持前进后退，且程序化导航不重复入栈', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final history = container.read(desktopHistoryProvider.notifier);

    history.record('/portal');
    history.record('/video');
    history.record('/photos');
    expect(container.read(desktopHistoryProvider).canGoForward, isFalse);

    expect(history.back(), '/video');
    // 模拟 go 触发的路由回调：不得把回退目标再追加一次。
    history.record('/video');
    expect(container.read(desktopHistoryProvider).entries, [
      '/portal',
      '/video',
      '/photos',
    ]);
    expect(history.forward(), '/photos');
    history.record('/photos');
    expect(history.back(), '/video');
    expect(history.back(), '/portal');
    expect(history.back(), isNull);
  });
}
