import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_overlay.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_preset_editor.dart';
import 'package:omninest/features/music/presentation/widgets/music_playing_bars.dart';

void main() {
  testWidgets('移动端播放详情默认封面页，横滑到整屏歌词（含短横屏适配）', (tester) async {
    final player = _FakeMusicAudioPlayback();
    addTearDown(player.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);

    await tester.pumpWidget(_testApp(player));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // 样例第一页：封面 + 曲名 + 进度 + 五控制行 + 底部工具行，歌词页未构建。
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(MusicDeckArtwork), findsAtLeastNWidgets(1));
    expect(find.text('Mobile Track'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey<String>('music-lyric-active')),
      findsNothing,
    );
    expect(find.text('Current lyric'), findsNothing);

    // 五控制行：随机与循环各一枚开关钮，不再共用桌面 Dock 的轮换单钮。
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // 头部只剩 返回/标题/⋯：队列只在底部工具行出现一枚，歌词没有第二入口钮，
    // 页码点与封面频谱条、歌词预览块都已删除。
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
    expect(find.byType(MusicPlayingBars), findsNothing);
    expect(find.text('实时歌词'), findsNothing);

    // 封面黑带（样例已删除的 0 25px 65px 重投影）不得回到封面子树里。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('mobile-cover-track-1')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              ((widget.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                  false),
        ),
      ),
      findsNothing,
    );

    // 背景改为动态壁纸透出：不再有专辑图模糊底图与重遮罩色层
    // （aurora 光晕层是唯一的 ImageFiltered，允许恰好一层）。
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xB8050B0F),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xC9050B0F),
      ),
      findsNothing,
    );

    // 横滑到第二页：整屏歌词在场，LIVE LYRICS 眉标只随歌词页出现。
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('music-lyric-active')),
      findsOneWidget,
    );
    expect(find.text('Current lyric'), findsOneWidget);
    expect(find.text('实时歌词'), findsOneWidget);

    // 歌词样式入口收敛进头部 ⋯ 动作面板：面板只含歌词分区，
    // 不暴露封面/播放器视觉编辑。
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    final panel = tester.widget<MusicVisualEditorPanel>(
      find.byKey(const ValueKey('music-mobile-lyric-style')),
    );
    expect(panel.sections, const <MusicVisualEditorSection>{
      MusicVisualEditorSection.mobileLyrics,
    });
    expect(find.text('歌词显示模式'), findsOneWidget);
    expect(find.text('原始封面'), findsNothing);
    expect(find.text('显示底部播放器'), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('歌词显示模式'), findsNothing);

    // 滑回封面页（歌词页只有歌名艺人行，曲名标题在封面页）后切短横屏不抛异常。
    await tester.drag(find.byType(PageView), const Offset(320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MusicDeckArtwork), findsAtLeastNWidgets(1));

    tester.view.physicalSize = const Size(700, 400);
    await tester.pump();
    expect(find.text('Mobile Track'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(MusicAudioPlayback player) {
  final item = MusicPlayableItem.local(_track);
  final center = MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const [_track],
    albums: const [],
    artists: const [],
    playlists: const [],
    currentItem: item,
    isPlaying: true,
    playbackItems: [item],
    playbackIndex: 0,
  );
  return ProviderScope(
    overrides: [
      musicCenterControllerProvider.overrideWith(
        () => _FakeMusicCenterController(center),
      ),
      musicPlaybackSessionProvider.overrideWith(
        () => _FakeMusicPlaybackSessionController(player),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(splashFactory: NoSplash.splashFactory),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MusicImmersiveOverlay(onClose: () {}),
    ),
  );
}

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Mobile Track',
  artistName: 'Mobile Artist',
  albumTitle: 'Mobile Album',
  format: 'FLAC',
  favorite: false,
  lyricsRaw: '[00:00.00]Opening lyric\n[00:10.00]Current lyric',
);

class _FakeMusicCenterController extends MusicCenterController {
  _FakeMusicCenterController(this.initialState);

  final MusicCenterState initialState;

  @override
  Future<MusicCenterState> build() async => initialState;
}

class _FakeMusicPlaybackSessionController
    extends MusicPlaybackSessionController {
  _FakeMusicPlaybackSessionController(this.player);

  final MusicAudioPlayback player;

  @override
  MusicPlaybackSession build() {
    return MusicPlaybackSession(player: player, lastError: null);
  }
}

class _FakeMusicAudioPlayback implements MusicAudioPlayback {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);

  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState(
    playing: true,
    position: Duration(seconds: 12),
    duration: Duration(minutes: 3),
  );

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    completed: const Stream<bool>.empty(),
    log: const Stream<MusicAudioLog>.empty(),
  );

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  void setVolume(double volume) {}
  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
  }
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
