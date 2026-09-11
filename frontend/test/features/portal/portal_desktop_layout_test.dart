import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/portal/presentation/pages/portal_page.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_visual_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpPortal(WidgetTester tester, {bool hosted = false}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 覆盖 session 存储以避免 FlutterSecureStorage 插件依赖
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          musicAudioPlaybackProvider.overrideWith(
            (ref) => const _FakeMusicAudioPlayback(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: MobileShellScope(hosted: hosted, child: const PortalPage()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('超宽窗口内容封顶 1560 居中且保持三栏', (tester) async {
    // 逻辑宽 2000：内容区 1936，超过 1560 上限。
    tester.view.physicalSize = const Size(4000, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPortal(tester);

    expect(tester.takeException(), isNull);
    final cap = find.byKey(const ValueKey('omninest.portal.content-cap'));
    expect(cap, findsOneWidget);
    expect(tester.getSize(cap).width, 1560);
    // 封顶宽度小于可用宽度即形成真实居中留白。
    final capRect = tester.getRect(cap);
    final windowWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final sideMargin = (windowWidth - 64 - capRect.width) / 2;
    expect(sideMargin, closeTo((1936 - 1560) / 2, 0.5));
    // 三栏结构：合并右栏不应出现在宽布局。
    expect(
      find.byKey(const ValueKey('omninest.portal.side-column')),
      findsNothing,
    );
    // Hero 封面卡宽高受 400×540 上限约束。
    final cover = find.byKey(const ValueKey('omninest.portal.hero-cover'));
    expect(cover, findsOneWidget);
    final coverSize = tester.getSize(cover);
    expect(coverSize.width, lessThanOrEqualTo(400));
    expect(coverSize.height, lessThanOrEqualTo(540));
  });

  testWidgets('高屏全屏内容块在顶栏与窗口底之间垂直居中', (tester) async {
    // 逻辑 2000×1600：内容区高度约 1514，内容块封顶 980，
    // 垂直居中后上下留白各约 267。
    tester.view.physicalSize = const Size(4000, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPortal(tester);

    expect(tester.takeException(), isNull);
    final cap = find.byKey(const ValueKey('omninest.portal.content-cap'));
    expect(cap, findsOneWidget);
    final capRect = tester.getRect(cap);
    final topBarRect = tester.getRect(find.byType(PortalVisualTopBar));
    // 宿主底部留白 28（Padding fromLTRB(32,0,32,28)）。
    final bottomLimit =
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 28;
    final topGap = capRect.top - topBarRect.bottom;
    final bottomGap = bottomLimit - capRect.bottom;
    expect(topGap, greaterThan(40));
    expect((topGap - bottomGap).abs(), lessThan(4));
  });

  testWidgets('桌面最小宽度 1024 进入两栏中间档且无溢出', (tester) async {
    // 逻辑宽 1024：内容区 960，落在 900-1279 两栏档。
    tester.view.physicalSize = const Size(2048, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPortal(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('omninest.portal.side-column')),
      findsOneWidget,
    );
    final cap = find.byKey(const ValueKey('omninest.portal.content-cap'));
    expect(cap, findsOneWidget);
    // 960 未触及上限，内容帽应铺满可用宽度。
    expect(tester.getSize(cap).width, 960);
    // 两栏档封面卡同样受限宽约束。
    final cover = find.byKey(const ValueKey('omninest.portal.hero-cover'));
    expect(cover, findsOneWidget);
    final coverSize = tester.getSize(cover);
    expect(coverSize.width, lessThanOrEqualTo(400));
    expect(coverSize.height, lessThanOrEqualTo(540));
  });

  testWidgets('平板宽度 1280 直接进入桌面三栏布局且无溢出', (tester) async {
    // 逻辑宽 1280（Pixel Tablet 横屏级别）：内容区 1216，
    // 不走两栏中间档，直接桌面三栏（紧凑边栏变体）。
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPortal(tester);

    expect(tester.takeException(), isNull);
    // 三栏结构：合并右栏不应出现。
    expect(
      find.byKey(const ValueKey('omninest.portal.side-column')),
      findsNothing,
    );
    // hero 封面在紧凑边栏份额内不越界。
    final cover = find.byKey(const ValueKey('omninest.portal.hero-cover'));
    expect(cover, findsOneWidget);
    final coverSize = tester.getSize(cover);
    expect(coverSize.width, lessThanOrEqualTo(400));
    expect(coverSize.height, lessThanOrEqualTo(540));
    final coverRect = tester.getRect(cover);
    final windowWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      coverRect.right,
      lessThanOrEqualTo(windowWidth - 32 - 300 - 12 - 20),
    );
  });
  testWidgets('hosted 平板复用桌面视觉但不绘制自身顶栏', (tester) async {
    // 移动壳层内的平板：壳层顶栏已提供标题/搜索/通知/头像，
    // 桌面 Portal 视觉不得再绘制第二条约含同功能入口的顶栏。
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPortal(tester, hosted: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(PortalVisualTopBar), findsNothing);
    expect(
      find.byKey(const ValueKey('omninest.portal.content-cap')),
      findsOneWidget,
    );
    // 垂直空间按壳层扣除后仍应进入桌面三栏（紧凑边栏）布局。
    expect(
      find.byKey(const ValueKey('omninest.portal.side-column')),
      findsNothing,
    );
  });
}

class _FakeMusicAudioPlayback implements MusicAudioPlayback {
  const _FakeMusicAudioPlayback();

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
