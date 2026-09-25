import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/utils/platform_helper.dart';

void main() {
  group('resolveFullscreenCommandTarget', () {
    test('Web 走浏览器 Fullscreen API，不得走桌面窗口 chrome', () {
      expect(
        resolveFullscreenCommandTarget(isWeb: true, isDesktop: false),
        FullscreenCommandTarget.browser,
      );
      expect(
        resolveFullscreenCommandTarget(isWeb: true, isDesktop: true),
        FullscreenCommandTarget.browser,
        reason: 'Web 分支优先，避免与桌面 chrome 双触发',
      );
    });

    test('桌面走 windowChrome，不调用浏览器 API', () {
      expect(
        resolveFullscreenCommandTarget(isWeb: false, isDesktop: true),
        FullscreenCommandTarget.windowChrome,
      );
    });

    test('移动端无页内全屏入口', () {
      expect(
        resolveFullscreenCommandTarget(isWeb: false, isDesktop: false),
        FullscreenCommandTarget.none,
      );
    });
  });
}
