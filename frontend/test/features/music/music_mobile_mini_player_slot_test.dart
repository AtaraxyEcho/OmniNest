import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/presentation/widgets/music_mobile_mini_player_slot.dart';

/// 壳层迷你播放插槽的浮起卡片规范测试：
/// 左右 10 留边 + 圆角 12 + 高 48（不再与底栏同宽贴边）；
/// 下滑收起后同曲保持隐藏、切歌自动回归。
void main() {
  late ProviderContainer container;

  Widget host() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MusicMobileMiniPlayerSlot(onOpenPlayer: _openPlayerStub),
          ),
        ),
      ),
    );
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [
        musicCenterControllerProvider.overrideWith(
          () => _MutableFakeCenterController(_centerOf(_trackA)),
        ),
        musicPlaybackSessionProvider.overrideWith(
          () => _FakeSessionController(),
        ),
      ],
    );
    addTearDown(() => container.dispose());
  });

  testWidgets('渲染为浮起卡片：左右留边、圆角 12、高 52', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MusicMobileMiniPlayerSlot), findsOneWidget);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding == const EdgeInsets.fromLTRB(10, 0, 10, 6),
      ),
      findsOneWidget,
      reason: '浮起卡片与底栏之间留出间隙，不与底栏同宽贴边',
    );

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
    expect(clip.borderRadius, BorderRadius.circular(12));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 52,
      ),
      findsOneWidget,
    );

    // 玻璃模糊保留（BackdropFilter 在圆角裁剪内）。
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下滑收起后同曲保持隐藏，切歌自动回归', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Track A'), findsOneWidget);

    await tester.fling(find.text('Track A'), const Offset(0, 160), 800);
    await tester.pumpAndSettle();
    expect(find.text('Track A'), findsNothing, reason: '下滑收起');

    final controller =
        container.read(musicCenterControllerProvider.notifier)
            as _MutableFakeCenterController;

    // 同一曲（状态刷新）保持隐藏。
    controller.emit(_centerOf(_trackA));
    await tester.pump();
    expect(find.text('Track A'), findsNothing);

    // 切歌后回归。
    controller.emit(_centerOf(_trackB));
    await tester.pump();
    expect(find.text('Track B'), findsOneWidget);
  });
}

void _openPlayerStub() {}

MusicCenterState _centerOf(MusicTrack track) {
  final item = MusicPlayableItem.local(track);
  return MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: [track],
    albums: const [],
    artists: const [],
    playlists: const [],
    currentItem: item,
    isPlaying: true,
    playbackItems: [item],
    playbackIndex: 0,
  );
}

const MusicTrack _trackA = MusicTrack(
  id: 'track-a',
  fileNodeId: 'file-a',
  title: 'Track A',
  artistName: 'Artist A',
  albumTitle: 'Album A',
  format: 'FLAC',
  favorite: false,
);

const MusicTrack _trackB = MusicTrack(
  id: 'track-b',
  fileNodeId: 'file-b',
  title: 'Track B',
  artistName: 'Artist B',
  albumTitle: 'Album B',
  format: 'FLAC',
  favorite: false,
);

class _MutableFakeCenterController extends MusicCenterController {
  _MutableFakeCenterController(this.initialState);

  final MusicCenterState initialState;

  @override
  Future<MusicCenterState> build() async => initialState;

  void emit(MusicCenterState next) {
    state = AsyncData(next);
  }
}

class _FakeSessionController extends MusicPlaybackSessionController {
  @override
  MusicPlaybackSession build() {
    return MusicPlaybackSession(player: _IdlePlayback(), lastError: null);
  }

  @override
  Future<void> syncFromCenterState() async {
    // 测试假体：不触碰真实同步链路（其 late 字段依赖完整 build 生命周期）。
  }
}

class _IdlePlayback implements MusicAudioPlayback {
  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState(
    playing: true,
    position: Duration(seconds: 12),
    duration: Duration(minutes: 3),
  );

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum => const _SilentSpectrum();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: const Stream<Duration>.empty(),
    duration: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    completed: const Stream<bool>.empty(),
    log: const Stream<MusicAudioLog>.empty(),
  );

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

class _SilentSpectrum implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrum();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
