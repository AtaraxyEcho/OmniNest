import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/deep_link/deep_link_service.dart';

void main() {
  group('resolveDeepLinkPath', () {
    test('maps whitelisted schemes to app routes', () {
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://s/abc123')),
        '/s/abc123',
      );
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://shared/photos/token-1')),
        '/shared/photos/token-1',
      );
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://reader/items/item-9')),
        '/reader/items/item-9',
      );
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://video/1234/play')),
        '/video/1234/play',
      );
    });

    test('rejects non-omninest schemes and non-whitelisted paths', () {
      expect(resolveDeepLinkPath(Uri.parse('https://s/abc')), isNull);
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://admin/settings')),
        isNull,
      );
      expect(resolveDeepLinkPath(Uri.parse('omninest://profile')), isNull);
      expect(resolveDeepLinkPath(Uri.parse('omninest://s/')), isNull);
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://reader/items/../admin')),
        isNull,
      );
    });

    test('rejects separator and control-character smuggling', () {
      // Uri.parse 在解析期就归一化点段：'%2e%2e/admin' 解出来是 /admin，
      // 只会留在 video 前缀之内，并不会跳到 /admin 路由（报告设想的穿越不成立）。
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://video/%2e%2e/admin')),
        '/video/admin',
      );
      // 真正必须拦的是解码后仍留在段内的分隔符与控制字符：
      // 它们会让交给 GoRouter 的形状与白名单校验的形状不一致。
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://video/a%2fb/c')),
        isNull,
      );
      expect(resolveDeepLinkPath(Uri.parse('omninest://video//admin')), isNull);
      expect(
        resolveDeepLinkPath(Uri.parse('omninest://video/%00admin')),
        isNull,
      );
    });

    test('never resolves to a route outside the whitelist', () {
      for (final raw in const [
        'omninest://video/%2e%2e/admin',
        'omninest://video/..%2f..%2fadmin',
        'omninest://reader/items/%2e%2e/%2e%2e/admin',
        'omninest://s/abc/..',
      ]) {
        final route = resolveDeepLinkPath(Uri.parse(raw));
        if (route == null) {
          continue;
        }
        expect(
          deepLinkAllowedPrefixes.any(route.startsWith),
          isTrue,
          reason: '$raw 解析成 $route，已跳出白名单',
        );
        expect(route, isNot(contains('//')));
      }
    });
  });
}
