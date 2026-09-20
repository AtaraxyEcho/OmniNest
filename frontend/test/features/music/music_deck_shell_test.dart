import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_shell.dart';

void main() {
  testWidgets('移动端查看全部页面提供返回首页控件', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MobileShellScope(hosted: true, child: MusicDeckShell()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
      findsNothing,
    );
    await tester.tap(find.text('View All').first);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('music-mobile-section-back')),
      findsNothing,
    );
    expect(find.text('View All'), findsNWidgets(2));
  });

  testWidgets('桌面壳层语义不因禁用态播放按钮整页合并失效', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
          musicPlaybackSessionProvider.overrideWith(
            _StubPlaybackSessionController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MusicDeckShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 不变量守卫：语义树根不得带按钮语义。实机 Web 上禁用态播放按钮的
    // 语义曾沿祖先链合并到树根致整页标记为 disabled 按钮（D-002）；
    // 该合并仅在引擎语义管线出现，VM 测试无法复现，此断言仅锁定守卫边界。
    final handle = tester.ensureSemantics();
    await tester.pump();

    // ignore: deprecated_member_use
    final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode;
    expect(root, isNotNull);
    expect(root!.flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('宽屏三张玻璃卡等高（导航/内容/正在播放）', (tester) async {
    tester.view.physicalSize = const Size(1900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = MusicCenterState(
      dashboard: MusicDashboard.empty(),
      tracks: const [],
      albums: const [],
      artists: const [],
      playlists: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicCenterControllerProvider.overrideWith(
            () => _FakeMusicCenterController(center),
          ),
          musicPlatformLibraryProvider.overrideWith(
            _FakeMusicPlatformLibraryController.new,
          ),
          musicPlaybackSessionProvider.overrideWith(
            _StubPlaybackSessionController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MusicDeckShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 左卡=含「首页」导航项的最近玻璃卡；右卡=含「正在播放」标题的最近玻璃卡
    // （内容区存在嵌套小玻璃卡，故按内容锚定左右两卡分别测量）。
    Size? sizeOf(Finder anchor) {
      final card =
          find
              .ancestor(of: anchor, matching: find.byType(MusicDeckGlass))
              .first;
      return (card.evaluate().single.findRenderObject() as RenderBox?)?.size;
    }

    final leftSize = sizeOf(find.text('首页'));
    final rightSize = sizeOf(find.text('正在播放'));
    expect(leftSize, isNotNull);
    expect(rightSize, isNotNull);
    expect(leftSize!.height, rightSize!.height, reason: '左右两张玻璃卡高度必须一致');
    expect(leftSize.width, rightSize.width, reason: '左右两张玻璃卡宽度必须一致');
  });
}

class _FakeMusicCenterController extends MusicCenterController {
  _FakeMusicCenterController(this.initialState);

  final MusicCenterState initialState;

  @override
  Future<MusicCenterState> build() async => initialState;
}

class _FakeMusicPlatformLibraryController
    extends MusicPlatformLibraryController {
  @override
  Future<MusicPlatformLibraryState> build() async {
    return const MusicPlatformLibraryState();
  }
}

class _StubPlaybackSessionController extends MusicPlaybackSessionController {
  static const _NoopAudioPlayback _player = _NoopAudioPlayback._();

  @override
  MusicPlaybackSession build() {
    return const MusicPlaybackSession(player: _player, lastError: null);
  }
}

class _NoopAudioPlayback implements MusicAudioPlayback {
  const _NoopAudioPlayback._();
  static const MusicAudioPlayerStreams _streams = MusicAudioPlayerStreams(
    position: Stream<Duration>.empty(),
    duration: Stream<Duration>.empty(),
    volume: Stream<double>.empty(),
    completed: Stream<bool>.empty(),
    log: Stream<MusicAudioLog>.empty(),
  );

  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState();

  @override
  MusicAudioPlayerStreams get stream => _streams;

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
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();
}
