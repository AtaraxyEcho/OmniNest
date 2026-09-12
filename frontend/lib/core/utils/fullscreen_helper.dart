import 'fullscreen_helper_stub.dart'
    if (dart.library.html) 'fullscreen_helper_web.dart'
    as platform;

bool get isFullscreen => platform.FullscreenHelperWeb.isFullscreenEnabled;

void toggleFullscreen() {
  if (platform.FullscreenHelperWeb.isFullscreenEnabled) {
    platform.FullscreenHelperWeb.exitFullscreen();
  } else {
    platform.FullscreenHelperWeb.enterFullscreen(
      platform.FullscreenHelperWeb.documentElement,
    );
  }
}

/// 订阅全屏状态变化，Web 之外的平台不产生事件。
void addFullscreenChangeListener(void Function(bool active) onChanged) {
  platform.FullscreenHelperWeb.addChangeListener(onChanged);
}

/// 取消订阅全屏状态变化。
void removeFullscreenChangeListener(void Function(bool active) onChanged) {
  platform.FullscreenHelperWeb.removeChangeListener(onChanged);
}
