import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 播放系统命令回调：由音乐播放会话层注入，转接 MusicCenter 命令。
class MusicMediaCommandCallbacks {
  const MusicMediaCommandCallbacks({
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onPlayPauseToggle,
    required this.onSeek,
  });

  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  /// 播放/暂停媒体键触发的状态切换，实现方按当前播放状态选择播放或暂停。
  final Future<void> Function() onPlayPauseToggle;

  final Future<void> Function(Duration position) onSeek;
}

/// 音乐系统媒体会话处理：Android/iOS 通知栏媒体卡片与系统媒体键的统一出口。
///
/// playbackState/position 由 soloud 事件经播放会话层驱动；metadata 来自当前曲。
class MusicMediaSessionHandler extends BaseAudioHandler with SeekHandler {
  MusicMediaSessionHandler({required MusicMediaCommandCallbacks callbacks})
    : _callbacks = callbacks;

  final MusicMediaCommandCallbacks _callbacks;

  /// 系统媒体卡片元数据（标题/艺人/专辑/封面/时长）。
  Future<void> updateNowPlaying({
    required MusicTrack? track,
    required bool playing,
    required Duration position,
    required Duration duration,
  }) async {
    if (track != null) {
      mediaItem.add(
        MediaItem(
          id: 'local:${track.id}',
          album: track.albumTitle,
          title: track.title,
          artist: track.artistName,
          duration:
              track.durationSeconds != null
                  ? Duration(seconds: track.durationSeconds!)
                  : (duration > Duration.zero ? duration : null),
          artUri: _artUri(track.coverUrl),
        ),
      );
    }
    playbackState.add(
      playbackState.value.copyWith(
        processingState:
            track == null
                ? AudioProcessingState.idle
                : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        bufferedPosition: duration,
        speed: 1.0,
        systemActions: const <MediaAction>{MediaAction.seek},
      ),
    );
  }

  Uri? _artUri(String? coverUrl) {
    final url = coverUrl?.trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return Uri.tryParse(url);
  }

  @override
  Future<void> play() async {
    await _callbacks.onPlay();
  }

  @override
  Future<void> pause() async {
    await _callbacks.onPause();
  }

  @override
  Future<void> skipToNext() async {
    await _callbacks.onNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _callbacks.onPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    await _callbacks.onSeek(position);
  }
}

/// 全局会话实例，由初始化流程创建，播放会话层与系统命令共享。
MusicMediaSessionHandler? _activeHandler;

StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
StreamSubscription<void>? _becomingNoisySub;
bool _resumeAfterInterruption = false;

/// 是否在本平台启用 audio_service 媒体会话（仅 Android/iOS）。
bool get musicMediaSessionSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> _bindAudioFocus(
  AudioSession session,
  MusicMediaCommandCallbacks callbacks,
) async {
  await session.setActive(true);
  await _interruptionSub?.cancel();
  await _becomingNoisySub?.cancel();
  _interruptionSub = session.interruptionEventStream.listen((event) async {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = true;
          await callbacks.onPause();
        case AudioInterruptionType.duck:
          break;
      }
      return;
    }
    if (_resumeAfterInterruption) {
      _resumeAfterInterruption = false;
      await callbacks.onPlay();
    }
  });
  _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
    _resumeAfterInterruption = false;
    unawaited(callbacks.onPause());
  });
}

/// 初始化系统媒体会话：音频焦点（audio_session）+ 通知栏媒体卡片（audio_service）。
///
/// 幂等：重复调用返回既有实例。
Future<MusicMediaSessionHandler?> ensureMusicMediaSession(
  MusicMediaCommandCallbacks callbacks,
) async {
  if (!musicMediaSessionSupported) {
    return null;
  }
  final existing = _activeHandler;
  if (existing != null) {
    return existing;
  }
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await _bindAudioFocus(session, callbacks);
  final handler = MusicMediaSessionHandler(callbacks: callbacks);
  await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.omninest.app.audio.playback',
      androidNotificationChannelName: '音乐播放',
      androidNotificationChannelDescription: '音乐后台播放与媒体控制',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  _activeHandler = handler;
  return handler;
}

/// 桌面媒体键桥：桌面热键服务（系统级媒体键）转接音乐命令。
abstract final class MusicMediaKeyBridge {
  static MusicMediaCommandCallbacks? _callbacks;

  /// 由音乐播放会话层注册命令回调。
  static void register(MusicMediaCommandCallbacks callbacks) {
    _callbacks = callbacks;
  }

  /// 播放/暂停媒体键：按当前播放状态切换，不做固定的单向下发。
  static Future<void> dispatchPlayPauseToggle() async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return;
    }
    await callbacks.onPlayPauseToggle();
  }

  static Future<void> dispatch({
    required bool play,
    bool pause = false,
    bool next = false,
    bool previous = false,
  }) async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return;
    }
    if (pause) {
      await callbacks.onPause();
    } else if (next) {
      await callbacks.onNext();
    } else if (previous) {
      await callbacks.onPrevious();
    } else if (play) {
      await callbacks.onPlay();
    }
  }
}
