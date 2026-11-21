part of 'movie_player_page.dart';

/// 播放页的音量/静音与全屏切换动作（与页面 state 共用同一批字段）。
extension _MoviePlayerChrome on _MoviePlayerPageState {
  void _toggleMute() {
    _updateState(() {
      if (_isMuted) {
        _volume = _volumeBeforeMute > 0 ? _volumeBeforeMute : 80;
        _isMuted = false;
      } else {
        _volumeBeforeMute = _volume;
        _volume = 0;
        _isMuted = true;
      }
    });
    unawaited(_player.setVolume(_volume));
  }

  void _toggleFullscreen() {
    if (isDesktopPlatform) {
      // 桌面全屏走手动全屏统一入口；本页租约仅移动端表达沉浸态。
      unawaited(_windowChromeController.toggleFullscreen());
      return;
    }
    fs.toggleFullscreen();
    // 全屏状态变化后需要重建 UI 以更新图标
    if (mounted) _updateState(() {});
  }

  void _cycleAspectRatio() {
    final currentIndex = AspectRatioOption.options(context).indexWhere((o) {
      if (o.isFill) return _isFill;
      if (_isFill) return false;
      if (o.ratio == null) return _aspectRatio == null;
      return _aspectRatio == o.ratio;
    });
    final nextIndex =
        (currentIndex + 1) % AspectRatioOption.options(context).length;
    final next = AspectRatioOption.options(context)[nextIndex];
    _updateState(() {
      _aspectRatio = next.ratio;
      _isFill = next.isFill;
    });
  }
}
