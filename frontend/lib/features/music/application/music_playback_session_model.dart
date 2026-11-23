part of 'music_playback_session.dart';

/// 音乐播放会话。
class MusicPlaybackSession {
  const MusicPlaybackSession({required this.player, required this.lastError});

  final MusicAudioPlayback player;
  final String? lastError;

  MusicPlaybackSession copyWith({
    MusicAudioPlayback? player,
    Object? lastError = _noChange,
  }) {
    return MusicPlaybackSession(
      player: player ?? this.player,
      lastError:
          identical(lastError, _noChange)
              ? this.lastError
              : lastError as String?,
    );
  }
}

const Object _noChange = Object();

/// 当前平台使用的音乐播放适配器。
final musicAudioPlaybackProvider = Provider.autoDispose<MusicAudioPlayback>((
  ref,
) {
  final player = createMusicAudioPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

/// 切歌加载中记下的一次跳转目标。
