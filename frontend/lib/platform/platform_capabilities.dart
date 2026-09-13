import 'package:flutter/foundation.dart';

/// 平台能力查询，用于运行时判断当前平台支持哪些功能。
///
/// 仅保留有真实业务消费方的能力位；其余能力按平台分支在业务层判断。
class PlatformCapabilities {
  const PlatformCapabilities({required this.supportsSystemTray});

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

  factory PlatformCapabilities.web() =>
      const PlatformCapabilities(supportsSystemTray: false);

  factory PlatformCapabilities.android() =>
      const PlatformCapabilities(supportsSystemTray: false);

  factory PlatformCapabilities.ios() =>
      const PlatformCapabilities(supportsSystemTray: false);

  factory PlatformCapabilities.desktop() =>
      const PlatformCapabilities(supportsSystemTray: true);

  factory PlatformCapabilities.fallback() =>
      const PlatformCapabilities(supportsSystemTray: false);
}
