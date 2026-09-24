// Web 平台的 Media Session 绑定实现（dart:js_interop）。

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:omninest/core/log/dev_log.dart';
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

  /// 元数据代次：封面字节异步到位时用于丢弃已切歌的回写。
  int _metadataGeneration = 0;
  String? _lastTitle;
  String? _lastArtist;
  String? _lastAlbum;

  /// 由封面字节创建的 object URL，换曲或换封面时必须释放，否则整会话内持续累积。
  String? _coverObjectUrl;

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
  ///
  /// [coverLoader] 非空表示该封面地址浏览器不能直连（需鉴权的稳定 API 路径）：
  /// 先出文字元数据，字节到位后再补 artwork，并把上一张的 object URL 释放。
  void updateMetadata({
    required String title,
    required String artistName,
    required String albumTitle,
    String? coverUrl,
    Future<Uint8List?> Function(String url)? coverLoader,
  }) {
    final generation = ++_metadataGeneration;
    _lastTitle = title;
    _lastArtist = artistName;
    _lastAlbum = albumTitle;
    final url = coverUrl?.trim();
    if (url == null || url.isEmpty) {
      _revokeCoverUrl();
      _writeMetadata();
      return;
    }
    final loader = coverLoader;
    if (loader == null) {
      _revokeCoverUrl();
      _writeMetadata(artworkUrl: url, artworkMime: 'image/jpeg');
      return;
    }
    _writeMetadata();
    unawaited(_attachLoadedCover(loader, url, generation));
  }

  void _writeMetadata({String? artworkUrl, String? artworkMime}) {
    final artwork = <web.MediaImage>[];
    if (artworkUrl != null && artworkMime != null) {
      artwork.add(
        web.MediaImage(src: artworkUrl, sizes: '512x512', type: artworkMime),
      );
    }
    web.window.navigator.mediaSession.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: _lastTitle ?? '',
        artist: _lastArtist ?? '',
        album: _lastAlbum ?? '',
        artwork: artwork.toJS,
      ),
    );
  }

  Future<void> _attachLoadedCover(
    Future<Uint8List?> Function(String url) loader,
    String url,
    int generation,
  ) async {
    try {
      final bytes = await loader(url);
      if (bytes == null || bytes.isEmpty) {
        return;
      }
      // 字节到位可能已经切歌：只有仍是最新一次同步时才回写 artwork。
      if (generation != _metadataGeneration) {
        return;
      }
      final mime = _coverMimeTypeForBytes(bytes);
      final blob = web.Blob(
        <JSAny>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: mime),
      );
      final objectUrl = web.URL.createObjectURL(blob);
      _revokeCoverUrl();
      _coverObjectUrl = objectUrl;
      _writeMetadata(artworkUrl: objectUrl, artworkMime: mime);
    } on Object catch (error) {
      devLog('Web 媒体会话封面加载失败: ${error.runtimeType}');
    }
  }

  void _revokeCoverUrl() {
    final previous = _coverObjectUrl;
    if (previous == null) {
      return;
    }
    _coverObjectUrl = null;
    web.URL.revokeObjectURL(previous);
  }

  String _coverMimeTypeForBytes(Uint8List bytes) {
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length > 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length > 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'image/webp';
    }
    return 'image/jpeg';
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
