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
  });
}
