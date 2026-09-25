import 'dart:async';

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
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// 用户跳转与切歌加载的竞争回归。
///
/// 单独成文件：系统媒体会话（audio_service）在一个测试 isolate 内只能初始化
/// 一次，与其他构建播放会话的用例同文件会互相触发单例断言。

void main() {
  test('切歌加载中的跳转在新音源打开后生效，不被归零覆盖', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final player = _StubMusicAudioPlayback();
    final container = ProviderContainer(
      overrides: [
        musicAudioPlaybackProvider.overrideWith((ref) => player),
        globalMusicProgressRepositoryProvider.overrideWith(
          (ref) => _MockProgressRepository(),
        ),
        musicCenterControllerProvider.overrideWith(
          () => _FakeMusicCenterController(
            MusicCenterState(
              dashboard: MusicDashboard.empty(),
              tracks: const <MusicTrack>[],
              albums: const <MusicAlbum>[],
              artists: const <MusicArtist>[],
              playlists: const <MusicPlaylist>[],
              currentItem: MusicPlayableItem.local(
                const MusicTrack(
                  id: 'track-2',
                  fileNodeId: 'file-2',
                  title: 'T',
                  artistName: 'A',
                  albumTitle: 'B',
                  format: 'FLAC',
                  favorite: false,
                ),
              ),
              playbackPlan: const MusicPlaybackPlan(
                trackId: 'track-2',
                url: 'https://example/track-2.mp3',
              ),
              isPlaying: true,
              playbackItems: <MusicPlayableItem>[
                MusicPlayableItem.local(
                  const MusicTrack(
                    id: 'track-2',
                    fileNodeId: 'file-2',
                    title: 'T',
                    artistName: 'A',
                    albumTitle: 'B',
                    format: 'FLAC',
                    favorite: false,
                  ),
                ),
              ],
              playbackIndex: 0,
            ),
          ),
        ),
        musicLocalPreferencesControllerProvider.overrideWith(
          () => _FakeLocalPreferencesController(),
        ),
      ],
    );
    try {
      await container.read(musicCenterControllerProvider.future);
      await container
          .read(musicPlaybackSessionProvider.notifier)
          .seekTo(const Duration(seconds: 42));
      for (var attempt = 0; attempt < 30; attempt++) {
        if (player.seekCalls.isNotEmpty &&
            player.seekCalls.last == const Duration(seconds: 42)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(player.seekCalls, isNotEmpty);
      expect(player.seekCalls.last, const Duration(seconds: 42));
      expect(
        player.seekCalls.where((position) => position == Duration.zero),
        isEmpty,
        reason: '音源打开后的归零 seek 会覆盖用户跳转',
      );
    } finally {
      container.dispose();
    }
  });

  test('曲目已在播放器上时立即跳转，不等待下一次同步', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final player = _StubMusicAudioPlayback();
    final container = ProviderContainer(
      overrides: [
        musicAudioPlaybackProvider.overrideWith((ref) => player),
        globalMusicProgressRepositoryProvider.overrideWith(
          (ref) => _MockProgressRepository(),
        ),
        musicCenterControllerProvider.overrideWith(
          () => _FakeMusicCenterController(
            MusicCenterState(
              dashboard: MusicDashboard.empty(),
              tracks: const <MusicTrack>[],
              albums: const <MusicAlbum>[],
              artists: const <MusicArtist>[],
              playlists: const <MusicPlaylist>[],
              currentItem: MusicPlayableItem.local(
                const MusicTrack(
                  id: 'track-1',
                  fileNodeId: 'file-1',
                  title: 'T',
                  artistName: 'A',
                  albumTitle: 'B',
                  format: 'FLAC',
                  favorite: false,
                ),
              ),
              playbackPlan: const MusicPlaybackPlan(
                trackId: 'track-1',
                url: 'https://example/track-1.mp3',
              ),
              playbackItems: <MusicPlayableItem>[
                MusicPlayableItem.local(
                  const MusicTrack(
                    id: 'track-1',
                    fileNodeId: 'file-1',
                    title: 'T',
                    artistName: 'A',
                    albumTitle: 'B',
                    format: 'FLAC',
                    favorite: false,
                  ),
                ),
              ],
              playbackIndex: 0,
            ),
          ),
        ),
        musicLocalPreferencesControllerProvider.overrideWith(
          () => _FakeLocalPreferencesController(),
        ),
      ],
    );
    try {
      final notifier = container.read(musicPlaybackSessionProvider.notifier);
      await container.read(musicCenterControllerProvider.future);
      await notifier.syncFromCenterState();
      player.seekCalls.clear();

      await notifier.seekTo(const Duration(seconds: 7));

      expect(player.seekCalls, <Duration>[const Duration(seconds: 7)]);
    } finally {
      container.dispose();
    }
  });
}

class _MockProgressRepository extends Mock implements MusicProgressRepository {}

class _StubMusicAudioPlayback implements MusicAudioPlayback {
  final List<Duration> seekCalls = <Duration>[];

  @override
  MusicAudioPlayerState get state => MusicAudioPlayerState(
    playing: false,
    volume: 100,
    duration: const Duration(minutes: 3),
  );

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
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
  }

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
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
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
