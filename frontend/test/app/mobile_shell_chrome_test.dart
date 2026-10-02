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
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端壳层 chrome 规范测试（360×860 视口，配色取自设计原型）：
/// - 一级导航为四个空间：首页·媒体库·阅读·文件（浮动胶囊底栏）；
/// - 顶栏无背景：元素直接呈现在环境上，仅搜索 + 头像两个动作；
/// - 底栏为 0.78 烟熏玻璃胶囊（70 高、左右 12 留边、max(12, inset) 底距），
///   选中胶囊为原型 lime 强调色；
/// - 浅色根主题下壳层强制暗色基底，无壁纸时壳底为环境舞台色。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const branchKeys = <String, Key>{
    '/portal': Key('branch-portal'),
    '/library': Key('branch-library'),
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
        GoRoute(
          path: '/search',
          builder: (context, state) => const Scaffold(key: Key('page-search')),
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
    Size surface = const Size(360, 860),
  }) async {
    await tester.binding.setSurfaceSize(surface);
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

  /// 浮动底栏玻璃面板（nav key 直下的 DecoratedBox）。
  DecoratedBox bottomChromeOf(WidgetTester tester) {
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    expect(nav, findsOneWidget);
    final matches =
        tester
            .widgetList<DecoratedBox>(
              find.descendant(of: nav, matching: find.byType(DecoratedBox)),
            )
            .toList();
    expect(matches, isNotEmpty);
    return matches.first;
  }

  Future<void> tapNav(WidgetTester tester, String label) async {
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    await tester.tap(find.descendant(of: nav, matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('一级导航顺序为 首页·媒体库·阅读·文件', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    final labels = <String>['首页', '媒体库', '阅读', '文件'];
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    var previousDx = -1.0;
    for (final label in labels) {
      final item = find.descendant(of: nav, matching: find.text(label));
      expect(item, findsOneWidget, reason: '底栏应包含 $label');
      final dx = tester.getTopLeft(item).dx;
      expect(dx, greaterThan(previousDx), reason: '$label 应位于前一项右侧');
      previousDx = dx;
    }
  });

  testWidgets('顶栏无背景：仅品牌/标题 + 搜索 + 头像，无铃铛与壁纸按钮', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/portal',
      brightness: Brightness.light,
    );
    // 首页顶栏只保留品牌标记，不出现品牌字标与多余动作。
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('OmniNest'), findsNothing);
    expect(find.byIcon(Icons.wallpaper_rounded), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    // 搜索为样例玻璃圆钮：描边图标取环境墨色。
    final searchIcon = tester.widget<OmniIcon>(
      find.descendant(
        of: find.byType(Tooltip),
        matching: find.byWidgetPredicate(
          (widget) => widget is OmniIcon && widget.icon == OmniIcons.search,
        ),
      ),
    );
    expect(searchIcon.color, MobileEnvColors.ink);
    // 顶栏内容行之上没有带颜色背景的装饰盒（透明呈现在环境上）。
    final topRow = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 56,
    );
    expect(topRow, findsOneWidget);
    final paintedAncestor =
        find
            .ancestor(of: topRow, matching: find.byType(DecoratedBox))
            .evaluate()
            .where((element) => element.widget is DecoratedBox)
            .where(
              (element) =>
                  (element.widget as DecoratedBox).decoration is BoxDecoration,
            )
            .toList();
    expect(paintedAncestor, isEmpty, reason: '顶栏不应绘制背景装饰');
  });

  testWidgets('手机宽度浮动胶囊底栏：几何与原型一致', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    final size = tester.getSize(nav);
    expect(size.width, 336);
    expect(size.height, 70);
    final rect = tester.getRect(nav);
    expect(rect.left, 12);
    expect(rect.bottom, 848, reason: '底边距 max(12, safe inset) = 12');
    // 玻璃面板：0.78 烟熏 + 白 12% 描边。
    final chrome = bottomChromeOf(tester);
    final decoration = chrome.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xC70E1413));
    expect(decoration.border?.top.color, const Color(0x1FFFFFFF));
  });

  testWidgets('选中胶囊为原型 lime，未选中为弱化前景', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    final pills =
        tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .toList();
    expect(pills, isNotEmpty);
    final selected =
        pills
            .where(
              (container) =>
                  (container.decoration as BoxDecoration?)?.color ==
                  MobileEnvColors.accent,
            )
            .toList();
    expect(selected, hasLength(1), reason: '仅当前空间胶囊高亮');
    // 选中图标为强调色上的深前景。
    final homeIcon = tester.widget<OmniIcon>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedContainer &&
              (widget.decoration as BoxDecoration?)?.color ==
                  MobileEnvColors.accent,
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is OmniIcon && widget.icon == OmniIcons.home,
        ),
      ),
    );
    expect(homeIcon.color, MobileEnvColors.onAccent);
  });

  testWidgets('浅色根主题下壳层强制暗色基底，无壁纸时壳底为舞台色', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/library',
      brightness: Brightness.light,
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, MobileEnvColors.stage);
    // 壁纸激活时壳底透明，由环境层绘制底。
    await pumpShell(
      tester,
      initialLocation: '/library',
      brightness: Brightness.light,
      backdropActive: true,
    );
    final active = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(active.backgroundColor, Colors.transparent);
  });

  testWidgets('非首页空间顶栏展示标题与副题', (tester) async {
    await pumpShell(tester, initialLocation: '/library');
    expect(find.text('媒体库'), findsAtLeastNWidgets(1));
    expect(find.text('你的媒体，都在这里'), findsOneWidget);
    await tapNav(tester, '文件');
    expect(find.text('你的数字工作区'), findsOneWidget);
  });

  testWidgets('搜索入口进入全局搜索覆盖层而非第二条导航', (tester) async {
    await pumpShell(tester, initialLocation: '/library');
    await tester.tap(find.byType(OmniIcon).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-search')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
      findsNothing,
    );
  });

  testWidgets('头像入口打开账户面板承载系统能力', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    expect(find.text('管理账户'), findsNothing);
    await tester.tap(find.byTooltip('账户'));
    await tester.pumpAndSettle();
    expect(find.text('通知中心'), findsOneWidget);
    expect(find.text('设备与会话'), findsOneWidget);
    expect(find.text('背景库'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('管理账户'), findsOneWidget);
  });

  testWidgets('账户面板视觉环境行只关一次面板并打开背景库', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    await tester.tap(find.byTooltip('账户'));
    await tester.pumpAndSettle();
    expect(find.text('背景库'), findsOneWidget);

    await tester.tap(find.text('背景库'));
    // 背景库对话框内有常驻动画（加载指示），全量 settle 会超时：推进
    // 固定时长覆盖面板退场与对话框入场即可。
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    // 回归：曾因 _closeAnd 与 _openBackdrop 双 pop 弹掉根导航最后一页
    // （GoRouter currentConfiguration.isNotEmpty 断言崩溃）。
    expect(tester.takeException(), isNull);
    expect(find.text('管理账户'), findsNothing);
    // 移动端视觉环境现为全覆盖贴底抽屉（非 Dialog）：断言抽屉标题在场。
    expect(find.text('背景库'), findsOneWidget);
  });

  testWidgets('四空间循环切换不触发壳层断言', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    for (final label in <String>['媒体库', '阅读', '文件', '首页']) {
      await tapNav(tester, label);
    }
    expect(find.byKey(const Key('branch-portal')), findsOneWidget);
    expect(find.byKey(const Key('branch-library')), findsNothing);
  });

  testWidgets('平板宽度：tab 组限宽 720 居中，各空间保持搜索图标', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/portal',
      surface: const Size(1280, 800),
    );
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    expect(tester.getSize(nav).width, 720);
    expect(tester.getSize(nav).height, 70);
    final navRect = tester.getRect(nav);
    expect(navRect.left, closeTo((1280 - 720) / 2, 0.5));
    // 平板不切换左侧 rail。
    expect(find.byType(NavigationRail), findsNothing);
    await tapNav(tester, '媒体库');
    expect(find.byIcon(Icons.wallpaper_rounded), findsNothing);
    expect(find.byType(OmniIcon), findsAtLeastNWidgets(1));
  });
}

class _ZeroUnreadCount extends UnreadCountNotifier {
  @override
  int build() => 0;
}

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
