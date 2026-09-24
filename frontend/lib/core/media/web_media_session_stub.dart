import 'dart:typed_data';

/// 非 Web 平台的 Media Session 空实现。
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
    return WebMediaSessionBinderImpl._(
      onPlay: onPlay,
      onPause: onPause,
      onNext: onNext,
      onPrevious: onPrevious,
    );
  }

  void updateMetadata({
    required String title,
    required String artistName,
    required String albumTitle,
    String? coverUrl,
    Future<Uint8List?> Function(String url)? coverLoader,
  }) {}

  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
    double speed = 1.0,
  }) {}
}
