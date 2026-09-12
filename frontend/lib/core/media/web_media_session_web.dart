// Web 平台的 Media Session 绑定实现（dart:js_interop）。

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class WebMediaSessionBinderImpl {
  WebMediaSessionBinderImpl._({
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
  });

  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  static WebMediaSessionBinderImpl register({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    final binder = WebMediaSessionBinderImpl._(
      onPlay: onPlay,
      onPause: onPause,
      onNext: onNext,
      onPrevious: onPrevious,
    );
    binder._registerActionHandlers();
    return binder;
  }

  void _registerActionHandlers() {
    final session = web.window.navigator.mediaSession;
    // toJS 要求同步签名：命令为异步，包装为 void 后交 unawaited 执行。
    session.setActionHandler(
      'play',
      ((web.Event _) {
        unawaited(onPlay());
      }).toJS,
    );
    session.setActionHandler(
      'pause',
      ((web.Event _) {
        unawaited(onPause());
      }).toJS,
    );
    session.setActionHandler(
      'previoustrack',
      ((web.Event _) {
        unawaited(onPrevious());
      }).toJS,
    );
    session.setActionHandler(
      'nexttrack',
      ((web.Event _) {
        unawaited(onNext());
      }).toJS,
    );
  }

  /// 同步当前曲目元数据（标题/艺人/专辑/封面）。
  void updateMetadata({
    required String title,
    required String artistName,
    required String albumTitle,
    String? coverUrl,
  }) {
    final artwork = <web.MediaImage>[];
    final url = coverUrl?.trim();
    if (url != null && url.isNotEmpty) {
      artwork.add(
        web.MediaImage(src: url, sizes: '512x512', type: 'image/jpeg'),
      );
    }
    web.window.navigator.mediaSession.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: title,
        artist: artistName,
        album: albumTitle,
        artwork: artwork.toJS,
      ),
    );
  }

  /// 同步播放状态（playing/paused）与进度（供系统面板展示）。
  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
    double speed = 1.0,
  }) {
    final session = web.window.navigator.mediaSession;
    session.playbackState = playing ? 'playing' : 'paused';
    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0) {
      return;
    }
    try {
      session.setPositionState(
        web.MediaPositionState(
          duration: seconds,
          position: (position.inMilliseconds / 1000.0).clamp(0.0, seconds),
          playbackRate: speed,
        ),
      );
    } on Object {
      // 部分浏览器对非法区间抛 NotSupportedError，忽略即可。
    }
  }
}
