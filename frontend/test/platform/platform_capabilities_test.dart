import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/platform_capabilities.dart';

void main() {
  group('PlatformCapabilities', () {
    test('Android 同时支持 PiP 与音量键翻页', () {
      final caps = PlatformCapabilities.android();
      expect(caps.supportsPictureInPicture, isTrue);
      expect(caps.supportsVolumeKeyPageTurn, isTrue);
    });

    test('iOS 不提供 PiP / 音量键翻页，避免死开关', () {
      final caps = PlatformCapabilities.ios();
      expect(caps.supportsPictureInPicture, isFalse);
      expect(caps.supportsVolumeKeyPageTurn, isFalse);
      expect(caps.supportsFullscreenToggle, isFalse);
    });

    test('桌面与 Web 不提供 PiP / 音量键翻页', () {
      expect(PlatformCapabilities.desktop().supportsPictureInPicture, isFalse);
      expect(
        PlatformCapabilities.desktop().supportsVolumeKeyPageTurn,
        isFalse,
      );
      expect(PlatformCapabilities.web().supportsPictureInPicture, isFalse);
      expect(PlatformCapabilities.web().supportsVolumeKeyPageTurn, isFalse);
    });

    test('仅桌面支持系统保存对话框，移动端走系统分享', () {
      expect(
        PlatformCapabilities.desktop().supportsFileSystemSaveDialog,
        isTrue,
      );
      expect(
        PlatformCapabilities.android().supportsFileSystemSaveDialog,
        isFalse,
      );
      expect(
        PlatformCapabilities.ios().supportsFileSystemSaveDialog,
        isFalse,
      );
    });

    test('桌面 OS 粒度：通知/媒体键/深链', () {
      final windows = PlatformCapabilities.windows();
      expect(windows.supportsSystemNotifications, isFalse);
      expect(windows.supportsMediaKeys, isTrue);
      expect(windows.supportsDeepLinkProtocol, isTrue);

      final macOS = PlatformCapabilities.macOS();
      expect(macOS.supportsSystemNotifications, isTrue);
      expect(macOS.supportsMediaKeys, isFalse);
      expect(macOS.supportsDeepLinkProtocol, isTrue);

      final linux = PlatformCapabilities.linux();
      expect(linux.supportsSystemNotifications, isTrue);
      expect(linux.supportsMediaKeys, isFalse);
      expect(linux.supportsDeepLinkProtocol, isTrue);
    });

    test('移动与 Web 的通知/媒体键/深链能力', () {
      expect(
        PlatformCapabilities.android().supportsSystemNotifications,
        isTrue,
      );
      expect(PlatformCapabilities.android().supportsMediaKeys, isFalse);
      expect(PlatformCapabilities.web().supportsSystemNotifications, isFalse);
      expect(PlatformCapabilities.web().supportsMediaKeys, isFalse);
      expect(PlatformCapabilities.web().supportsDeepLinkProtocol, isFalse);
    });
  });

  test('current() 在非 Web 测试环境跟随 defaultTargetPlatform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(
      PlatformCapabilities.current().supportsVolumeKeyPageTurn,
      isTrue,
    );
  });
}
