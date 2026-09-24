import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端壳层 chrome 规范测试（360×860 视口）：
/// - 六个一级导航的顺序为 首页·音乐·照片·媒体·阅读·文件；
/// - 实底模块（照片/影视/阅读/文件）顶/底栏为不透明主题表面，
///   阅读分支取纸感表面，选中态统一墨色前景；
/// - 首页/音乐在动态背景激活时保持半透明玻璃 chrome。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const branchKeys = <String, Key>{
    '/portal': Key('branch-portal'),
    '/music': Key('branch-music'),
    '/photos': Key('branch-photos'),
    '/video': Key('branch-video'),
    '/reader': Key('branch-reader'),
    '/files': Key('branch-files'),
  };

  Widget host({
    required String initialLocation,
    Brightness brightness = Brightness.light,
    bool backdropActive = false,
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute.indexedStack(
          builder:
              (context, state, navigationShell) =>
                  MobileAppShell(navigationShell: navigationShell),
          branches: [
            for (final entry in branchKeys.entries)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: entry.key,
                    builder: (context, state) => Scaffold(key: entry.value),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        presetAppEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
        mobileShellLocalBackdropActiveProvider.overrideWithValue(
          backdropActive,
        ),
        unreadCountProvider.overrideWith(_ZeroUnreadCount.new),
        mobileShellSelectionActiveProvider.overrideWith((ref, branch) => false),
        musicAudioPlaybackProvider.overrideWith(
          (ref) => const _SilentMusicAudioPlayback(),
        ),
      ],
      child: MaterialApp.router(
        theme:
            brightness == Brightness.light
                ? OmniNestTheme.light()
                : OmniNestTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    );
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    required String initialLocation,
    Brightness brightness = Brightness.light,
    bool backdropActive = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 860));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      host(
        initialLocation: initialLocation,
        brightness: brightness,
        backdropActive: backdropActive,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 顶栏 = DecoratedBox(child: SafeArea(bottom: false))；
  /// 底栏 = DecoratedBox(child: SafeArea(top: false))。
  DecoratedBox chromeOf(WidgetTester tester, {required bool top}) {
    final matches =
        tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where(
              (widget) =>
                  widget.child is SafeArea &&
                  (top
                      ? (widget.child as SafeArea).bottom == false
                      : (widget.child as SafeArea).top == false),
            )
            .toList();
    expect(matches, hasLength(1), reason: top ? '顶栏唯一' : '底栏唯一');
    return matches.single;
  }

  Finder bottomNavigation() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.child is SafeArea &&
          (widget.child as SafeArea).top == false,
    );
  }

  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: bottomNavigation(), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  Color chromeColor(DecoratedBox chrome) {
    final decoration = chrome.decoration as BoxDecoration;
    return decoration.color!;
  }

  testWidgets('顶栏表面覆盖状态栏区域，内容避让系统插图', (tester) async {
    // FakeViewPadding 以物理像素计，dpr 固定 1 使插图与逻辑坐标一致。
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpShell(tester, initialLocation: '/portal');

    final topBar = chromeOf(tester, top: true);
    final barRect = tester.getRect(
      find.byWidgetPredicate((widget) => widget == topBar),
    );
    // 表面自屏幕顶端画起，状态栏区域不再露出透明底。
    expect(barRect.top, 0);
    final contentRow = find.descendant(
      of: find.byWidgetPredicate((widget) => widget == topBar),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 56,
      ),
    );
    expect(contentRow, findsOneWidget);
    // 内容行自状态栏下沿开始（44 插图 + 56 栏高）。
    expect(tester.getTopLeft(contentRow).dy, 44);
    expect(barRect.height, 100);
  });

  testWidgets('一级导航顺序为 首页·音乐·照片·媒体·阅读·文件', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    final labels = <String>['首页', '音乐', '照片', '媒体', '阅读', '文件'];
    final bottomNav = bottomNavigation();
    var previousDx = -1.0;
    for (final label in labels) {
      final item = find.descendant(of: bottomNav, matching: find.text(label));
      expect(item, findsOneWidget, reason: '底栏应包含 $label');
      final dx = tester.getTopLeft(item).dx;
      expect(dx, greaterThan(previousDx), reason: '$label 应位于前一项右侧');
      previousDx = dx;
    }
  });

  testWidgets('照片分支 chrome 跟随 Frame 暖纸面，选中态为 Frame 墨色', (tester) async {
    await pumpShell(tester, initialLocation: '/photos');

    expect(chromeColor(chromeOf(tester, top: true)), const Color(0xFFFAFAF8));
    expect(chromeColor(chromeOf(tester, top: false)), const Color(0xFFFAFAF8));
    expect(chromeColor(chromeOf(tester, top: true)).a, 1.0);
    expect(chromeColor(chromeOf(tester, top: false)).a, 1.0);

    final selectedIcon = tester.widget<Icon>(
      find.byIcon(Icons.photo_library_rounded),
    );
    expect(selectedIcon.color, const Color(0xFF1A1917));
    final unselectedIcon = tester.widget<Icon>(
      find.byIcon(Icons.home_outlined),
    );
    expect(unselectedIcon.color, const Color(0xFF8A8680));
  });

  testWidgets('阅读分支 chrome 取纸感表面与纸感墨色选中态', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/reader',
      brightness: Brightness.dark,
    );

    expect(chromeColor(chromeOf(tester, top: true)), const Color(0xFF0F0E0C));
    expect(chromeColor(chromeOf(tester, top: false)), const Color(0xFF0F0E0C));

    final selectedIcon = tester.widget<Icon>(
      find.byIcon(Icons.menu_book_rounded),
    );
    expect(selectedIcon.color, const Color(0xFFEEEDE9));
  });

  testWidgets('首页与音乐在动态背景激活时保持半透明玻璃 chrome', (tester) async {
    await pumpShell(tester, initialLocation: '/portal', backdropActive: true);
    expect(chromeColor(chromeOf(tester, top: true)).a, lessThan(1.0));
    expect(chromeColor(chromeOf(tester, top: false)).a, lessThan(1.0));

    await tapNav(tester, '音乐');
    expect(chromeColor(chromeOf(tester, top: true)).a, lessThan(1.0));
    expect(chromeColor(chromeOf(tester, top: false)).a, lessThan(1.0));
  });

  testWidgets('玻璃分支统一烟熏配方：浅色+壁纸顶栏 0.72 / 底栏 0.80', (tester) async {
    await pumpShell(tester, initialLocation: '/portal', backdropActive: true);
    final portalTop = chromeColor(chromeOf(tester, top: true));
    final portalBottom = chromeColor(chromeOf(tester, top: false));
    expect(portalTop.a, closeTo(0.72, 0.001));
    expect(portalBottom.a, closeTo(0.80, 0.001));
    // 烟熏基色：浅色+壁纸下为暗色玻璃底。
    expect(portalTop.r, lessThan(0.2));

    await tapNav(tester, '音乐');
    final musicTop = chromeColor(chromeOf(tester, top: true));
    final musicBottom = chromeColor(chromeOf(tester, top: false));
    expect(musicTop.a, closeTo(0.72, 0.001), reason: '音乐与首页共用同一玻璃配方');
    expect(musicBottom.a, closeTo(0.80, 0.001));
    expect(musicTop.r, lessThan(0.2));
  });

  testWidgets('玻璃分支无壁纸浅色为近实底浅玻璃 0.90', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    expect(chromeColor(chromeOf(tester, top: true)).a, closeTo(0.90, 0.001));

    await tapNav(tester, '音乐');
    expect(
      chromeColor(chromeOf(tester, top: true)).a,
      closeTo(0.90, 0.001),
      reason: '音乐无壁纸浅色不再 0.42 失衡',
    );
  });

  testWidgets('深色无壁纸上下栏统一近实底 0.92', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/portal',
      brightness: Brightness.dark,
    );
    // 半透明烟熏会在近黑内容上拼出明暗/冷暖断裂色带：无壁纸时上下栏
    // 同档近实底，与浅色 0.90 对称。
    expect(chromeColor(chromeOf(tester, top: true)).a, closeTo(0.92, 0.001));
    expect(chromeColor(chromeOf(tester, top: false)).a, closeTo(0.92, 0.001));
  });

  testWidgets('深色下照片 chrome 跟随 Frame 暖炭面，文件保持全局暗面', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/photos',
      brightness: Brightness.dark,
    );
    expect(chromeColor(chromeOf(tester, top: true)), const Color(0xFF191817));
    expect(chromeColor(chromeOf(tester, top: false)), const Color(0xFF191817));
    // 底栏选中墨色为 Frame 暗版反色的米白。
    final selectedIcon = tester.widget<Icon>(
      find.byIcon(Icons.photo_library_rounded),
    );
    expect(selectedIcon.color, const Color(0xFFF2EFE9));

    await tapNav(tester, '文件');
    expect(chromeColor(chromeOf(tester, top: true)), const Color(0xFF101311));
    expect(chromeColor(chromeOf(tester, top: false)), const Color(0xFF101311));
  });

  testWidgets('六分支循环切换不触发壳层断言', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    for (final label in <String>['音乐', '照片', '媒体', '阅读', '文件', '首页']) {
      await tapNav(tester, label);
    }
    expect(find.byKey(const Key('branch-portal')), findsOneWidget);
    expect(find.byKey(const Key('branch-files')), findsNothing);
  });

  testWidgets('点击文件页签进入末位分支', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    await tapNav(tester, '文件');
    expect(find.byKey(const Key('branch-files')), findsOneWidget);
    expect(chromeColor(chromeOf(tester, top: true)), const Color(0xFFF7F8F6));
  });

  testWidgets('实底分支壳层自绘面板底色，玻璃分支保持透明', (tester) async {
    Future<Color?> shellBackground() async {
      final scaffold = tester.widget<Scaffold>(
        find
            .ancestor(of: bottomNavigation(), matching: find.byType(Scaffold))
            .first,
      );
      return scaffold.backgroundColor;
    }

    // 照片：Frame 暖纸底（hosted 页面透明，壳层不绘制会露出窗口黑底）。
    await pumpShell(tester, initialLocation: '/photos');
    expect(await shellBackground(), const Color(0xFFFAFAF8));

    // 文件：全局浅色表面。
    await tapNav(tester, '文件');
    expect(await shellBackground(), const Color(0xFFF7F8F6));

    // 首页（玻璃）：透明，由壁纸绘制底。
    await tapNav(tester, '首页');
    expect(await shellBackground(), Colors.transparent);
  });

  testWidgets('玻璃分支 chrome 不绘制描边（浅色白线移除）', (tester) async {
    await pumpShell(tester, initialLocation: '/portal', backdropActive: true);
    final decoration = chromeOf(tester, top: true).decoration as BoxDecoration;
    expect(decoration.border?.bottom.color, Colors.transparent);

    await tapNav(tester, '音乐');
    final bottomDecoration =
        chromeOf(tester, top: false).decoration as BoxDecoration;
    expect(bottomDecoration.border?.top.color, Colors.transparent);

    // 实底分支描边保留。
    await tapNav(tester, '文件');
    final solidDecoration =
        chromeOf(tester, top: true).decoration as BoxDecoration;
    expect(solidDecoration.border?.bottom.color, isNot(Colors.transparent));
  });

  testWidgets('平板宽度统一底部导航：无左侧 rail 且 tab 组限宽居中', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(host(initialLocation: '/portal'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 平板不再切换左侧导航 rail。
    expect(find.byType(NavigationRail), findsNothing);
    // tab 组限宽 720 且水平居中，间距不被整屏拉伸。
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    expect(nav, findsOneWidget);
    expect(tester.getSize(nav).width, 720);
    // 平板宽度收紧栏高（手机保持 68），横屏竖向空间不被底栏挤占。
    expect(tester.getSize(nav).height, 56);
    final navRect = tester.getRect(nav);
    expect(navRect.left, closeTo((1280 - 720) / 2, 0.5));
    // 三端统一品牌入口：顶栏以 logo 领起，Portal 首页展示品牌字标。
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('OmniNest'), findsOneWidget);
    // 全局搜索框只在 Portal 首页展示：限宽 460 且紧随品牌居左排布。
    final search = find.byKey(const ValueKey('omninest.mobile.top-bar-search'));
    expect(search, findsOneWidget);
    expect(tester.getSize(search).width, 460);
    final searchRect = tester.getRect(search);
    expect(searchRect.left, greaterThan(140));
    expect(searchRect.left, lessThan(320));
    // 右缘远离右侧操作区，确认整体居左而非居中/拉满。
    expect(searchRect.right, lessThan(800));
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    // 平板 hosted 桌面视觉不再绘制自身顶栏，背景库入口由壳层顶栏接管。
    expect(find.byIcon(Icons.wallpaper_rounded), findsOneWidget);

    // Music/Video/Reader 平板宽度走模块自带搜索，顶栏不再重复展示。
    await tapNav(tester, '音乐');
    expect(
      find.byKey(const ValueKey('omninest.mobile.top-bar-search')),
      findsNothing,
    );
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    // Files/Photos 的搜索图标是页内搜索条唯一触发，保留为图标形态。
    await tapNav(tester, '文件');
    expect(
      find.byKey(const ValueKey('omninest.mobile.top-bar-search')),
      findsNothing,
    );
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });

  testWidgets('手机宽度底栏铺满且顶栏保持搜索图标', (tester) async {
    await pumpShell(tester, initialLocation: '/reader');
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    expect(nav, findsOneWidget);
    expect(tester.getSize(nav).width, 360);
    // 手机宽度保持拇指友好的 68 栏高。
    expect(tester.getSize(nav).height, 68);
    // 品牌入口同样覆盖手机：logo 领起 + 分支名提供上下文。
    expect(find.byType(BrandLogo), findsOneWidget);
    // 顶栏标题与底栏选中页签都会出现「阅读」。
    expect(find.text('阅读'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('omninest.mobile.top-bar-search')),
      findsNothing,
    );
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    // 背景库入口仅在平板宽度接管到壳层顶栏；手机走移动 Portal 自身入口。
    await tapNav(tester, '首页');
    expect(find.byIcon(Icons.wallpaper_rounded), findsNothing);
    // Portal 首页在手机上以品牌字标替代「首页」分支名。
    expect(find.text('OmniNest'), findsOneWidget);
  });
}

/// 壳层测试使用的静音播放器，避免测试环境加载 soloud 原生库。
class _SilentMusicAudioPlayback implements MusicAudioPlayback {
  const _SilentMusicAudioPlayback();

  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState();

  @override
  MusicAudioPlayerStreams get stream => const MusicAudioPlayerStreams(
    position: Stream<Duration>.empty(),
    duration: Stream<Duration>.empty(),
    volume: Stream<double>.empty(),
    completed: Stream<bool>.empty(),
    log: Stream<MusicAudioLog>.empty(),
  );

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  void setVolume(double volume) {}
  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> dispose() async {}
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// 壳层铃铛只需要未读计数；给零值避免真实请求。
class _ZeroUnreadCount extends UnreadCountNotifier {
  @override
  int build() => 0;
}
