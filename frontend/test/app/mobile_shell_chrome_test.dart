import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
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
/// - 壳层极性只由外观设置（根主题明暗）决定，壁纸在场也不参与判定。
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
    Brightness brightness = Brightness.dark,
    bool backdropActive = false,
    bool filesSubpageActive = false,
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
        mobileShellSubpageActiveProvider.overrideWith(
          (ref, branch) =>
              filesSubpageActive &&
              branch == MobileNavigationConfig.filesBranch,
        ),
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
    Brightness brightness = Brightness.dark,
    bool backdropActive = false,
    bool filesSubpageActive = false,
    Size surface = const Size(360, 860),
    double textScale = 1.0,
  }) async {
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      host(
        initialLocation: initialLocation,
        brightness: brightness,
        backdropActive: backdropActive,
        filesSubpageActive: filesSubpageActive,
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
            .where(
              (widget) =>
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color != null,
            )
            .toList();
    expect(matches, isNotEmpty);
    return matches.first;
  }

  /// 顶栏内容带（keyed 顶栏直上、唯一带定高的 SizedBox）。
  SizedBox topBarBandOf(WidgetTester tester) {
    final topBar = find.byKey(const ValueKey('omninest.mobile.top-bar'));
    expect(topBar, findsOneWidget);
    final bands =
        tester
            .widgetList<SizedBox>(
              find.ancestor(of: topBar, matching: find.byType(SizedBox)),
            )
            .where((widget) => widget.height != null)
            .toList();
    expect(bands, hasLength(1), reason: '顶栏只有一个定高内容带');
    return bands.single;
  }

  /// 底栏四枚空间舱位：48×30 的图标带（原型 `.bottom-nav button > span`）。
  /// 只认带图标的盒子，选中滑块层与舱位同尺寸但不在计数内。
  Finder bottomCapsules() {
    return find.descendant(
      of: find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
      matching: find.ancestor(
        of: find.byType(OmniIcon),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.width == 48 && widget.height == 30,
        ),
      ),
    );
  }

  /// 底栏的选中滑块层（单层胶囊，在四个舱位间滑过）。
  /// 键在承载对齐动画的 AnimatedAlign 上，它铺满整条带；胶囊本体是里面的
  /// DecoratedBox，几何断言必须量本体。
  Finder bottomNavPill() {
    return find.descendant(
      of: find.descendant(
        of: find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
        matching: find.byKey(const ValueKey('omninest.mobile.bottom-nav-pill')),
      ),
      matching: find.byType(DecoratedBox),
    );
  }

  Color? bottomNavPillColor(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(bottomNavPill());
    return (box.decoration as BoxDecoration).color;
  }

  OmniIcon navIconOfType(WidgetTester tester, OmniIconsData icon) {
    return tester.widget<OmniIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
        matching: find.byWidgetPredicate(
          (widget) => widget is OmniIcon && widget.icon == icon,
        ),
      ),
    );
  }

  Future<void> tapNav(WidgetTester tester, String label) async {
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    await tester.tap(find.descendant(of: nav, matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('横屏手机（844×390）不锁方向的前提：壳层仍是移动形态且不吃满高度', (tester) async {
    for (final location in const ['/portal', '/library', '/reader', '/files']) {
      await pumpShell(
        tester,
        initialLocation: location,
        surface: const Size(844, 390),
      );
      expect(tester.takeException(), isNull, reason: '$location 横屏渲染不应抛异常或溢出');
      final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
      final topBar = find.byKey(const ValueKey('omninest.mobile.top-bar'));
      expect(nav, findsOneWidget, reason: '$location 横屏仍走移动壳层');
      final navRect = tester.getRect(nav);
      final topRect = tester.getRect(topBar);
      expect(navRect.bottom, lessThanOrEqualTo(390));
      expect(
        390 - topRect.height - navRect.height,
        greaterThan(120),
        reason: '$location 横屏留给内容的高度不能薄到不可用',
      );
    }
  });

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

  testWidgets('顶栏无背景：首页只有搜索 + 头像，不设品牌位', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    // 图形标记是 512px 人物插画，压进 48px 顶栏后没有可读性，还会与右侧
    // 账户头像构成两个人像。品牌归启动、登录与关于，常驻外壳不再承载。
    expect(find.byType(BrandLogo), findsNothing);
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
    expect(searchIcon.color, MobileEnvPalette.dark.ink);
    // 顶栏内容行之上没有带颜色背景的装饰盒（透明呈现在环境上）。
    // 基准内容带 64，无障碍字号下由 scaleHeight 自撑，因此只断言下限。
    final topBar = find.byKey(const ValueKey('omninest.mobile.top-bar'));
    expect(topBarBandOf(tester).height, greaterThanOrEqualTo(64));
    final paintedAncestor =
        find
            .ancestor(of: topBar, matching: find.byType(DecoratedBox))
            .evaluate()
            .where((element) => element.widget is DecoratedBox)
            .where(
              (element) =>
                  (element.widget as DecoratedBox).decoration is BoxDecoration,
            )
            .toList();
    expect(paintedAncestor, isEmpty, reason: '顶栏不应绘制背景装饰');
  });

  testWidgets('1.6x 无障碍字号下顶栏自撑高度且无溢出', (tester) async {
    // 微型字号是签名密度不放大，标题/副题靠内容带自撑吸收。
    await pumpShell(tester, initialLocation: '/library', textScale: 1.6);
    expect(topBarBandOf(tester).height, greaterThan(64));
    expect(tester.takeException(), isNull, reason: '大字号下顶栏不得溢出');
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
    // 玻璃面板：0.78 烟熏 + 白 12% 描边 + 原型 blur(28)。
    final chrome = bottomChromeOf(tester);
    final decoration = chrome.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xC70E1413));
    expect(decoration.border?.top.color, const Color(0x1FFFFFFF));
    expect(
      find.descendant(of: nav, matching: find.byType(BackdropFilter)),
      findsOneWidget,
      reason: '底栏需真实模糊，不能只靠半透明底近似',
    );
  });

  testWidgets('选中胶囊为原型 lime，未选中为弱化前景', (tester) async {
    await pumpShell(tester, initialLocation: '/portal');
    // 原型 `.bottom-nav button > span` 为 min-width:48 + height:30：切换空间时
    // 只有滑块位置与配色变化，舱位尺寸不得参与补间（34→48 会让整排图标抖动）。
    expect(bottomCapsules(), findsNWidgets(4), reason: '四个空间各一枚舱位');
    for (var index = 0; index < 4; index++) {
      expect(
        tester.getSize(bottomCapsules().at(index)),
        const Size(48, 30),
        reason: '选中与未选中同尺寸',
      );
    }
    // 高亮是**单层滑块**，且与选中舱位同心（竖向按目的地列的居中公式折算）。
    expect(bottomNavPill(), findsOneWidget);
    expect(bottomNavPillColor(tester), MobileEnvPalette.dark.accent);
    expect(
      tester.getCenter(bottomNavPill()).dx,
      closeTo(tester.getCenter(bottomCapsules().at(0)).dx, 0.5),
    );
    expect(
      tester.getCenter(bottomNavPill()).dy,
      closeTo(tester.getCenter(bottomCapsules().at(0)).dy, 0.5),
      reason: '标签行高取整会带来 0.1px 级差，滑块仍应与图标带同心',
    );
    // 选中图标为强调色上的深前景，未选中仍是弱化前景。
    expect(
      navIconOfType(tester, OmniIcons.home).color,
      MobileEnvPalette.dark.onAccent,
    );
    expect(
      navIconOfType(tester, OmniIcons.folder).color,
      MobileEnvPalette.dark.white46,
    );

    // 切换空间：滑块滑过去，而不是瞬移到新舱位。
    final startCenter = tester.getCenter(bottomNavPill()).dx;
    final targetCenter = tester.getCenter(bottomCapsules().at(1)).dx;
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    await tester.tap(find.descendant(of: nav, matching: find.text('媒体库')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midwayCenter = tester.getCenter(bottomNavPill()).dx;
    expect(midwayCenter, greaterThan(startCenter + 1));
    expect(midwayCenter, lessThan(targetCenter - 1));

    await tester.pumpAndSettle();
    // 落位后仍是四枚等尺寸舱位，高亮唯一且与新舱位同心。
    expect(bottomCapsules(), findsNWidgets(4));
    for (var index = 0; index < 4; index++) {
      expect(
        tester.getSize(bottomCapsules().at(index)),
        const Size(48, 30),
        reason: '切换过程不改变舱位尺寸',
      );
    }
    expect(bottomNavPill(), findsOneWidget, reason: '高亮胶囊唯一');
    expect(
      tester.getCenter(bottomNavPill()).dx,
      closeTo(tester.getCenter(bottomCapsules().at(1)).dx, 0.5),
    );
    expect(
      tester.getCenter(bottomNavPill()).dy,
      closeTo(tester.getCenter(bottomCapsules().at(1)).dy, 0.5),
    );
    expect(
      navIconOfType(tester, OmniIcons.library).color,
      MobileEnvPalette.dark.onAccent,
    );
    expect(
      navIconOfType(tester, OmniIcons.home).color,
      MobileEnvPalette.dark.white46,
    );
  });

  testWidgets('壳层极性随根主题，无壁纸时壳底取对应舞台色', (tester) async {
    await pumpShell(tester, initialLocation: '/library');
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      MobileEnvPalette.dark.stage,
      reason: '暗根主题下壳层维持暗环境基底',
    );
    await pumpShell(
      tester,
      initialLocation: '/library',
      brightness: Brightness.light,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      MobileEnvPalette.light.stage,
      reason: '无壁纸的实底壳随根主题翻浅，不再强制暗栈',
    );
    // 壁纸在场时壳底透明，由环境层绘制底。
    await pumpShell(
      tester,
      initialLocation: '/library',
      brightness: Brightness.light,
      backdropActive: true,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      Colors.transparent,
    );
  });

  testWidgets('设了壁纸也必须照外观设置翻浅（采样不得再接管极性）', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/library',
      brightness: Brightness.light,
      backdropActive: true,
    );

    final navFill = find.descendant(
      of: find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration?)?.color ==
                MobileEnvPalette.light.navGlass,
      ),
    );
    expect(
      navFill,
      findsOneWidget,
      reason: '浅外观 + 有壁纸时底栏必须是浅纸实底；壁纸亮度不能把壳层留在暗档',
    );
  });

  testWidgets('非首页空间顶栏展示标题与副题', (tester) async {
    await pumpShell(tester, initialLocation: '/library');
    expect(find.text('媒体库'), findsAtLeastNWidgets(1));
    expect(find.text('你的媒体，都在这里'), findsOneWidget);
    await tapNav(tester, '文件');
    expect(find.text('你的数字工作区'), findsOneWidget);
  });

  // 样例 FeaturePage 是 `.module-overlay { inset: 0; z-index: 100 }`：整屏层
  // 自带 90 高页头与返回钮，壳层顶栏与 tab 组都要让位，否则四页读起来仍是
  // 「文件空间里的一块面板」而不是独立页面。照片/音乐/影视走根级路由，
  // 文件分区在 branch 内，只能由壳层显式收起。
  testWidgets('文件子页态：顶栏与底栏让位', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/files',
      filesSubpageActive: true,
    );
    // 分支页在场，证明是壳层收起了 chrome，而不是整棵树没挂上。
    expect(find.byKey(const Key('branch-files')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('omninest.mobile.top-bar')),
      findsNothing,
      reason: '子页态不叠壳层顶栏',
    );
    expect(
      find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
      findsNothing,
      reason: '子页态整屏接管，tab 组一并收起',
    );
  });

  testWidgets('文件模块首页仍用壳层 chrome', (tester) async {
    await pumpShell(tester, initialLocation: '/files');
    expect(
      find.byKey(const ValueKey('omninest.mobile.top-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('omninest.mobile.bottom-nav')),
      findsOneWidget,
    );
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
    // 宽档不切左侧 rail，顶栏必须与 tab 组同宽同边，否则顶行坐到内容列之外。
    final topBar = find.byKey(const ValueKey('omninest.mobile.top-bar'));
    expect(tester.getSize(topBar).width, 720);
    expect(tester.getRect(topBar).left, closeTo(navRect.left, 0.5));
    // 平板不切换左侧 rail。
    expect(find.byType(NavigationRail), findsNothing);
    await tapNav(tester, '媒体库');
    expect(find.byIcon(Icons.wallpaper_rounded), findsNothing);
    expect(find.byType(OmniIcon), findsAtLeastNWidgets(1));
  });

  testWidgets('600-979 档：tab 组收成 460 胶囊，顶栏保持 720 限宽', (tester) async {
    // 原型 600-979 档 `.bottom-nav` 为 min(460, 100%-24) 居中，三档边界同式。
    for (final width in <double>[600, 720, 979]) {
      await pumpShell(
        tester,
        initialLocation: '/portal',
        surface: Size(width, 900),
      );
      final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
      expect(
        tester.getSize(nav),
        const Size(460, 70),
        reason: '$width 视口下 tab 组收成 460',
      );
      expect(
        tester.getRect(nav).left,
        closeTo((width - 460) / 2, 0.5),
        reason: '$width 视口下 tab 组居中',
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('omninest.mobile.top-bar')))
            .width,
        width < 720 ? width : 720,
        reason: '$width 视口下顶栏按壳层上限 720 收拢，窄于此档时铺满视口',
      );
    }
  });

  testWidgets('980 起 tab 组回到壳层 720 上限并与顶栏同边', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/portal',
      surface: const Size(980, 900),
    );
    final nav = find.byKey(const ValueKey('omninest.mobile.bottom-nav'));
    expect(tester.getSize(nav), const Size(720, 70));
    final navRect = tester.getRect(nav);
    expect(navRect.left, closeTo((980 - 720) / 2, 0.5));
    final topBar = find.byKey(const ValueKey('omninest.mobile.top-bar'));
    expect(tester.getSize(topBar).width, 720);
    expect(tester.getRect(topBar).left, closeTo(navRect.left, 0.5));
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
