import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/theme/app_theme.dart';
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
        mobileShellLocalBackdropActiveProvider.overrideWithValue(
          backdropActive,
        ),
        mobileShellActivityProvider.overrideWithValue(
          const MobileShellActivityState(
            unreadCount: 0,
            activeTaskCount: 0,
            failedTaskCount: 0,
          ),
        ),
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

  /// 顶栏 = DecoratedBox(height 56)；底栏 = DecoratedBox(child: SafeArea)。
  DecoratedBox chromeOf(WidgetTester tester, {required bool top}) {
    final matches =
        tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where(
              (widget) =>
                  top
                      ? widget.child is SizedBox &&
                          (widget.child as SizedBox).height == 56
                      : widget.child is SafeArea,
            )
            .toList();
    expect(matches, hasLength(1), reason: top ? '顶栏唯一' : '底栏唯一');
    return matches.single;
  }

  Finder bottomNavigation() {
    return find.byWidgetPredicate(
      (widget) => widget is DecoratedBox && widget.child is SafeArea,
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

  testWidgets('深色下玻璃分支统一 0.78/0.82 档', (tester) async {
    await pumpShell(
      tester,
      initialLocation: '/portal',
      brightness: Brightness.dark,
    );
    expect(chromeColor(chromeOf(tester, top: true)).a, closeTo(0.78, 0.001));
    expect(chromeColor(chromeOf(tester, top: false)).a, closeTo(0.82, 0.001));
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
