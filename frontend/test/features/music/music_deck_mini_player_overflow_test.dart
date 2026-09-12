import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_mini_player.dart';

void main() {
  for (final scale in <double>[1.15, 1.3]) {
    testWidgets('紧凑迷你播放器在窄面板 $scale 档位下不溢出', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 复现 Portal 右栏宿主对迷你播放器的紧约束。
      await tester.pumpWidget(
        _testApp(
          scale: scale,
          child: const SizedBox(
            width: 196,
            height: 51.5,
            child: MusicDeckMiniPlayer(
              compact: true,
              embedded: true,
              managePlaybackSession: false,
              onOpenQueue: _noop,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('标准迷你播放器在 $scale 档位下不溢出', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          scale: scale,
          child: const SizedBox(
            width: 640,
            child: MusicDeckMiniPlayer(
              compact: false,
              embedded: true,
              managePlaybackSession: false,
              onOpenQueue: _noop,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}

void _noop() {}

const MusicTrack track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Portal Focus Track',
  artistName: 'Portal Focus Artist With Long Name',
  albumTitle: 'Portal Focus Album',
  format: 'FLAC',
  favorite: false,
);

Widget _testApp({required double scale, required Widget child}) {
  final item = MusicPlayableItem.local(track);
  final center = MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const [track],
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
        () => _FakeMusicPlaybackSessionController(_FakeMusicAudioPlayback()),
      ),
    ],
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

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
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();
}
