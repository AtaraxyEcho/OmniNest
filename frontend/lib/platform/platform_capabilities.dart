import 'package:flutter/foundation.dart';

/// 平台能力查询，用于运行时判断当前平台支持哪些功能。
///
/// 仅保留有真实业务消费方的能力位；其余能力按平台分支在业务层判断。
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.supportsSystemTray,
    required this.supportsHoverPointer,
    required this.supportsDragAndDropUpload,
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
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return PlatformCapabilities.desktop();
      default:
        return PlatformCapabilities.fallback();
    }
  }

  final bool supportsSystemTray;

  /// 是否支持把文件拖放进窗口（`desktop_drop` 仅覆盖桌面原生端）。
  final bool supportsDragAndDropUpload;

  /// 是否存在可产生 hover 事件的指针设备。
  ///
  /// 触屏浏览器与触屏应用不会触发 `MouseRegion.onEnter`，因此仅靠 hover
  /// 显现的操作入口在该类设备上不可达；Web 端按宿主 OS 判定。
  final bool supportsHoverPointer;

  /// Web 端按宿主 OS 判定：手机浏览器同样是触屏，不会触发 hover。
  factory PlatformCapabilities.web() {
    final hostIsTouch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return PlatformCapabilities(
      supportsSystemTray: false,
      supportsHoverPointer: !hostIsTouch,
      supportsDragAndDropUpload: false,
    );
  }

  factory PlatformCapabilities.android() => const PlatformCapabilities(
    supportsSystemTray: false,
    supportsHoverPointer: false,
    supportsDragAndDropUpload: false,
  );

  factory PlatformCapabilities.ios() => const PlatformCapabilities(
    supportsSystemTray: false,
    supportsHoverPointer: false,
    supportsDragAndDropUpload: false,
  );

  factory PlatformCapabilities.desktop() => const PlatformCapabilities(
    supportsSystemTray: true,
    supportsHoverPointer: true,
    supportsDragAndDropUpload: true,
  );

  factory PlatformCapabilities.fallback() => const PlatformCapabilities(
    supportsSystemTray: false,
    supportsHoverPointer: false,
    supportsDragAndDropUpload: false,
  );
}
