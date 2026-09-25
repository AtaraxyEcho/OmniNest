import 'package:flutter/foundation.dart';

/// 当前是否运行在 Web 平台。
bool get isWebPlatform => kIsWeb;

/// 当前是否运行在移动平台（Android / iOS）。
bool get isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 当前是否运行在桌面平台（Windows / Linux / macOS）。
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// 当前是否运行在 Android 平台。
bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 当前是否运行在 iOS 平台。
bool get isIOSPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 是否支持翻页模式（左右滑动）。
///
/// 懒加载分页（PageNavigator）按需计算单页，窗口大小变化时重新分页即可。
/// Web 只开放滚动阅读（产品决策 D3），不得提供翻页入口。
bool get supportsPageMode => !kIsWeb;

/// 页内全屏命令的分发目标。
enum FullscreenCommandTarget {
  /// 无可用全屏入口（移动端等）。
  none,

  /// Web Fullscreen API（`fullscreen_helper`）。
  browser,

  /// 桌面窗口 chrome（window_manager / 原生通道）。
  windowChrome,
}

/// 根据平台决定页内全屏命令应走的通道。
///
/// Web 必须走浏览器 Fullscreen API；桌面走 windowChromeController；
/// 移动端不提供全屏切换（见 [PlatformCapabilities.supportsFullscreenToggle]）。
FullscreenCommandTarget resolveFullscreenCommandTarget({
  required bool isWeb,
  required bool isDesktop,
}) {
  if (isWeb) {
    return FullscreenCommandTarget.browser;
  }
  if (isDesktop) {
    return FullscreenCommandTarget.windowChrome;
  }
  return FullscreenCommandTarget.none;
}
