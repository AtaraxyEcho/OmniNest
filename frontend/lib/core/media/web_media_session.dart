import 'web_media_session_stub.dart'
    if (dart.library.js_interop) 'web_media_session_web.dart'
    as impl;

/// Web Media Session 绑定器：把浏览器/系统媒体控件（媒体键、锁屏面板）
/// 接入音乐播放命令，并把当前曲目元数据与播放状态同步给浏览器。
///
/// 仅 Web 平台有实际行为；其它平台为空实现。命令回调由音乐播放会话层注入。
class WebMediaSessionBinder {
  WebMediaSessionBinder._(this._impl);

  final impl.WebMediaSessionBinderImpl _impl;

  static WebMediaSessionBinder? _instance;

  /// 注册浏览器媒体会话：幂等，重复调用返回既有实例。
  static WebMediaSessionBinder register({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }
    final binder = WebMediaSessionBinder._(
      impl.WebMediaSessionBinderImpl.register(
        onPlay: onPlay,
        onPause: onPause,
        onNext: onNext,
        onPrevious: onPrevious,
      ),
    );
    _instance = binder;
    return binder;
  }

  /// 同步当前曲目元数据（标题/艺人/专辑/封面）。
  void updateMetadata({
    required String title,
    required String artistName,
    required String albumTitle,
    String? coverUrl,
  }) {
    _impl.updateMetadata(
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      coverUrl: coverUrl,
    );
  }

  /// 同步播放状态（playing/paused）与进度（供系统面板展示）。
  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
    double speed = 1.0,
  }) {
    _impl.updatePlaybackState(
      playing: playing,
      position: position,
      duration: duration,
      speed: speed,
    );
  }
}
