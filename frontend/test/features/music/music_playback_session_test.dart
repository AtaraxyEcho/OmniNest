import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/music/domain/music_models.dart';

class _MockProgressRepository extends Mock implements MusicProgressRepository {}

class _StubMusicAudioPlayback implements MusicAudioPlayback {
  @override
  MusicAudioPlayerState get state =>
      const MusicAudioPlayerState(playing: false, volume: 100);

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

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
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> seek(Duration position) async {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  void setVolume(double volume) {}

  @override
  void setRelativePlaySpeed(double speed) {}

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

class _FakeMusicCenterController extends MusicCenterController {
  _FakeMusicCenterController(this.initialState);

  final MusicCenterState initialState;

  @override
  Future<MusicCenterState> build() async => initialState;
}

class _FakeLocalPreferencesController extends MusicLocalPreferencesController {
  @override
  Future<String> build() async => 'test';

  @override
  Future<double> loadPlaybackSpeed() async => 1.0;
}

void main() {
  test('MusicPlaybackSession copyWith can update and clear lastError', () {
    final player = _StubMusicAudioPlayback();
    final session = MusicPlaybackSession(player: player, lastError: null);
    final failed = session.copyWith(lastError: 'failed');
    expect(failed.player, same(player));
    expect(failed.lastError, 'failed');
    final cleared = failed.copyWith(lastError: null);
    expect(cleared.lastError, isNull);
  });

  test('isIgnorableMusicPlayerLog ignores known native fallback logs', () {
    expect(
      isIgnorableMusicPlayerLog(
        'error: property not found _setProperty(osc, 1)',
      ),
      isTrue,
    );
    expect(isIgnorableMusicPlayerLog('Failed to create file cache.'), isTrue);
    expect(isIgnorableMusicPlayerLog('Failed to open audio stream.'), isFalse);
  });

  test('only typed playback failures are promoted to user-visible errors', () {
    expect(
      isMusicPlaybackFailureLog(
        const MusicAudioLog('SoLoud 频谱读取失败: visualization unavailable'),
      ),
      isFalse,
    );
    expect(
      isMusicPlaybackFailureLog(
        const MusicAudioLog(
          'SoLoud 音乐打开失败: unsupported codec',
          playbackFailure: true,
        ),
      ),
      isTrue,
    );
  });

  test('invalidate 后在同一 notifier 上重建不触发 late final 重复初始化', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer(
      overrides: [
        musicAudioPlaybackProvider.overrideWith(
          (ref) => _StubMusicAudioPlayback(),
        ),
        globalMusicProgressRepositoryProvider.overrideWith(
          (ref) => _MockProgressRepository(),
        ),
        musicCenterControllerProvider.overrideWith(
          () => _FakeMusicCenterController(
            MusicCenterState(
              dashboard: MusicDashboard.empty(),
              tracks: const [],
              albums: const [],
              artists: const [],
              playlists: const [],
            ),
          ),
        ),
        musicLocalPreferencesControllerProvider.overrideWith(
          () => _FakeLocalPreferencesController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(musicPlaybackSessionProvider);
    final player = first.player;

    container.invalidate(musicPlaybackSessionProvider);
    await Future<void>.delayed(Duration.zero);

    final second = container.read(musicPlaybackSessionProvider);

    expect(second.player, same(player));
    expect(second.lastError, isNull);
  });
}
