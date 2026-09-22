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
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('probe', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final player = _P();
    addTearDown(player.dispose);
    final container = ProviderContainer.test(
      overrides: [
        musicCenterControllerProvider.overrideWith(() => _C(_S())),
        musicPlaybackSessionProvider.overrideWith(() => _Sess(player)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              height: 60,
              child: MusicImmersiveLyrics(
                palette: const MusicImmersivePalette(
                  background: Color(0xFF000000),
                  surface: Color(0xFF000000),
                  surfaceStrong: Color(0xFF000000),
                  text: Colors.white,
                  muted: Colors.white,
                  accent: Colors.white,
                  accentAlt: Colors.white,
                  glow: Colors.white,
                ),
                player: player,
                track: _track,
                lyrics: _lyrics,
                scale: 1,
                textAlign: TextAlign.left,
                blockAnchor: Alignment.centerLeft,
                onTogglePlayback: () {},
                onPrevious: () {},
                onNext: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

class _S {
  MusicCenterState call() => MusicCenterState(
    dashboard: MusicDashboard.empty(),
    tracks: const [],
    albums: const [],
    artists: const [],
    playlists: const [],
  );
}

class _C extends MusicCenterController {
  _C(this.fn);
  final _S fn;
  @override
  Future<MusicCenterState> build() async => fn();
}

class _Sess extends MusicPlaybackSessionController {
  _Sess(this.player);
  final MusicAudioPlayback player;
  @override
  MusicPlaybackSession build() =>
      MusicPlaybackSession(player: player, lastError: null);
  @override
  Future<void> syncFromCenterState() async {}
}

const _track = MusicTrack(
  id: 't',
  fileNodeId: '',
  title: 'T',
  artistName: 'A',
  albumTitle: 'B',
  format: 'FLAC',
  favorite: false,
);

final _lyrics = List<MusicLyricLine>.generate(
  30,
  (index) => MusicLyricLine(
    position: Duration(seconds: index * 10),
    text: 'Lyric ${index + 1}',
  ),
);

class _P implements MusicAudioPlayback {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  @override
  MusicAudioPlayerState get state => const MusicAudioPlayerState(
    playing: true,
    position: Duration(seconds: 25),
    duration: Duration(minutes: 5),
  );
  @override
  ValueListenable<MusicSpectrumFrame> get spectrum => const _L();
  @override
  MusicAudioPlayerStreams get stream => MusicAudioPlayerStreams(
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
  Future<void> seek(Duration position) async {}
  @override
  void setVolume(double volume) {}
  @override
  void setRelativePlaySpeed(double speed) {}
  @override
  void setSpectrumTrack(MusicTrack? track) {}
  @override
  Future<void> dispose() async {
    await _positionController.close();
  }
}

class _L implements ValueListenable<MusicSpectrumFrame> {
  const _L();
  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
