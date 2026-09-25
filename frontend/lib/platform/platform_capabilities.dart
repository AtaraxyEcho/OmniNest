import 'package:flutter/foundation.dart';

/// 平台能力查询，用于运行时判断当前平台支持哪些功能。
///
/// 仅保留有真实业务消费方的能力位；其余能力按平台分支在业务层判断。
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.supportsSystemTray,
    required this.supportsHoverPointer,
    required this.supportsDragAndDropUpload,
    required this.supportsFullscreenToggle,
    required this.supportsPictureInPicture,
    required this.supportsVolumeKeyPageTurn,
    required this.supportsFileSystemSaveDialog,
    required this.supportsSystemNotifications,
    required this.supportsMediaKeys,
    required this.supportsDeepLinkProtocol,
  });

  /// 根据当前运行平台返回对应的能力集。
  factory PlatformCapabilities.current() {
    if (kIsWeb) return PlatformCapabilities.web();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return PlatformCapabilities.android();
      case TargetPlatform.iOS:
        return PlatformCapabilities.ios();
      case TargetPlatform.windows:
        return PlatformCapabilities.windows();
      case TargetPlatform.linux:
        return PlatformCapabilities.linux();
      case TargetPlatform.macOS:
        return PlatformCapabilities.macOS();
      default:
        return PlatformCapabilities.fallback();
    }
  }

  final bool supportsSystemTray;

  /// 是否支持把文件拖放进窗口（`desktop_drop` 仅覆盖桌面原生端）。
  final bool supportsDragAndDropUpload;

  /// 是否存在可用的全屏切换入口。
  ///
  /// 桌面原生走窗口 API、Web 走 Fullscreen API；Android/iOS 的播放页已由
  /// 沉浸租约覆盖系统栏，再放一个全屏钮只会点了没反应。
  final bool supportsFullscreenToggle;

  /// 是否存在可产生 hover 事件的指针设备。
  ///
  /// 触屏浏览器与触屏应用不会触发 `MouseRegion.onEnter`，因此仅靠 hover
  /// 显现的操作入口在该类设备上不可达；Web 端按宿主 OS 判定。
  final bool supportsHoverPointer;

  /// 是否支持视频画中画（当前仅 Android 原生实现）。
  final bool supportsPictureInPicture;

  /// 是否支持音量键翻页（原生按键拦截，当前仅 Android）。
  final bool supportsVolumeKeyPageTurn;

  /// 是否支持系统「另存为」对话框（桌面）；移动端走系统分享。
  final bool supportsFileSystemSaveDialog;

  /// 是否支持系统通知（flutter_local_notifications 覆盖范围；Windows 当前不覆盖）。
  final bool supportsSystemNotifications;

  /// 是否支持系统媒体键（播放/暂停等；当前仅 Windows VK 通道）。
  final bool supportsMediaKeys;

  /// 是否支持注册 `omninest://` 深链协议（Windows 注册表 / macOS Info.plist / Linux xdg）。
  final bool supportsDeepLinkProtocol;

  /// Web 端按宿主 OS 判定：手机浏览器同样是触屏，不会触发 hover。
  factory PlatformCapabilities.web() {
    final hostIsTouch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return PlatformCapabilities(
      supportsSystemTray: false,
      supportsHoverPointer: !hostIsTouch,
      supportsDragAndDropUpload: false,
      supportsFullscreenToggle: true,
      supportsPictureInPicture: false,
      supportsVolumeKeyPageTurn: false,
      supportsFileSystemSaveDialog: false,
      supportsSystemNotifications: false,
      supportsMediaKeys: false,
      supportsDeepLinkProtocol: false,
    );
  }

  factory PlatformCapabilities.android() => const PlatformCapabilities(
    supportsSystemTray: false,
    supportsHoverPointer: false,
    supportsDragAndDropUpload: false,
    supportsFullscreenToggle: false,
    supportsPictureInPicture: true,
    supportsVolumeKeyPageTurn: true,
    supportsFileSystemSaveDialog: false,
    supportsSystemNotifications: true,
    supportsMediaKeys: false,
    supportsDeepLinkProtocol: true,
  );

  factory PlatformCapabilities.ios() => const PlatformCapabilities(
    supportsSystemTray: false,
    supportsHoverPointer: false,
    supportsDragAndDropUpload: false,
    supportsFullscreenToggle: false,
    supportsPictureInPicture: false,
    supportsVolumeKeyPageTurn: false,
    supportsFileSystemSaveDialog: false,
    supportsSystemNotifications: true,
    supportsMediaKeys: false,
    supportsDeepLinkProtocol: true,
  );

  factory PlatformCapabilities.windows() => const PlatformCapabilities(
    supportsSystemTray: true,
    supportsHoverPointer: true,
    supportsDragAndDropUpload: true,
    supportsFullscreenToggle: true,
    supportsPictureInPicture: false,
    supportsVolumeKeyPageTurn: false,
    supportsFileSystemSaveDialog: true,
    // flutter_local_notifications 0.18 不覆盖 Windows，任务提醒走站内。
    supportsSystemNotifications: false,
    supportsMediaKeys: true,
    supportsDeepLinkProtocol: true,
  );

  factory PlatformCapabilities.macOS() => const PlatformCapabilities(
    supportsSystemTray: true,
    supportsHoverPointer: true,
    supportsDragAndDropUpload: true,
    supportsFullscreenToggle: true,
    supportsPictureInPicture: false,
    supportsVolumeKeyPageTurn: false,
    supportsFileSystemSaveDialog: true,
    supportsSystemNotifications: true,
    // D6：macOS 媒体键需 Remote Command，另期实现。
    supportsMediaKeys: false,
    supportsDeepLinkProtocol: true,
  );

  factory PlatformCapabilities.linux() => const PlatformCapabilities(
    supportsSystemTray: true,
    supportsHoverPointer: true,
    supportsDragAndDropUpload: true,
    supportsFullscreenToggle: true,
    supportsPictureInPicture: false,
    supportsVolumeKeyPageTurn: false,
    supportsFileSystemSaveDialog: true,
    supportsSystemNotifications: true,
    // D6：Linux 媒体键需 MPRIS，本期不做。
    supportsMediaKeys: false,
    supportsDeepLinkProtocol: true,
  );

  /// 未知桌面平台：与 Linux 对齐（托盘/hover/拖放可用）。
  factory PlatformCapabilities.desktop() => PlatformCapabilities.linux();

  factory PlatformCapabilities.fallback() => const PlatformCapabilities(
    supportsSystemTray: false,
    supportsHoverPointer: false,
    supportsDragAndDropUpload: false,
    supportsFullscreenToggle: false,
    supportsPictureInPicture: false,
    supportsVolumeKeyPageTurn: false,
    supportsFileSystemSaveDialog: false,
    supportsSystemNotifications: false,
    supportsMediaKeys: false,
    supportsDeepLinkProtocol: false,
  );
}
