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

void main() {
  testWidgets('移动端播放详情支持封面歌词切换并适配短横屏', (tester) async {
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

    expect(find.text('Mobile Track'), findsNWidgets(2));
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    // 背景改为动态壁纸透出：不再有专辑图模糊底图与重遮罩色层。
    expect(find.byType(ImageFiltered), findsNothing);
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
    // 封面卡保留，模糊底图键不再出现。
    expect(find.byType(MusicDeckArtwork), findsAtLeastNWidgets(1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey &&
            (widget.key as ValueKey).value.toString().startsWith(
              'mobile-backdrop-',
            ),
      ),
      findsNothing,
    );

    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pump(const Duration(milliseconds: 360));

    expect(
      find.byKey(const ValueKey<String>('music-lyric-active')),
      findsOneWidget,
    );
    expect(find.text('Current lyric'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.album_outlined));
    await tester.pump(const Duration(milliseconds: 280));
    tester.view.physicalSize = const Size(700, 400);
    await tester.pump();

    expect(find.text('Mobile Track'), findsNWidgets(2));
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
