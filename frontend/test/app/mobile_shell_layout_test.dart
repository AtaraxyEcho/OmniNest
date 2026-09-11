import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';

void main() {
  group('shouldUseResponsiveMobileShell', () {
    test('桌面应用紧凑视口启用移动端壳层', () {
      expect(
        shouldUseResponsiveMobileShell(mobilePlatform: false, width: 360),
        isTrue,
      );
      expect(
        shouldUseResponsiveMobileShell(mobilePlatform: false, width: 899),
        isTrue,
      );
    });

    test('桌面浏览器收缩窗口不切换移动端壳层，手机浏览器保持自适应', () {
      // 桌面浏览器（宿主 OS 为桌面系统）窄窗 → 桌面布局。
      expect(
        resolveMobileShell(
          mobilePlatform: false,
          web: true,
          hostPlatform: TargetPlatform.windows,
          width: 360,
        ),
        isFalse,
      );
      expect(
        resolveMobileShell(
          mobilePlatform: false,
          web: true,
          hostPlatform: TargetPlatform.macOS,
          width: 899,
        ),
        isFalse,
      );
      // 手机浏览器窄屏 → 移动布局。
      expect(
        resolveMobileShell(
          mobilePlatform: false,
          web: true,
          hostPlatform: TargetPlatform.android,
          width: 414,
        ),
        isTrue,
      );
      expect(
        resolveMobileShell(
          mobilePlatform: false,
          web: true,
          hostPlatform: TargetPlatform.iOS,
          width: 390,
        ),
        isTrue,
      );
      // 手机浏览器宽屏（平板横放）→ 桌面布局。
      expect(
        resolveMobileShell(
          mobilePlatform: false,
          web: true,
          hostPlatform: TargetPlatform.android,
          width: 1200,
        ),
        isFalse,
      );
    });

    test('Windows 和 Web 桌面视口保留桌面布局', () {
      expect(
        shouldUseResponsiveMobileShell(mobilePlatform: false, width: 900),
        isFalse,
      );
      expect(
        shouldUseResponsiveMobileShell(mobilePlatform: false, width: 3840),
        isFalse,
      );
    });

    test('Android 和 iOS 在平板宽度继续使用移动端信息架构', () {
      expect(
        shouldUseResponsiveMobileShell(mobilePlatform: true, width: 1280),
        isTrue,
      );
    });
  });
}
