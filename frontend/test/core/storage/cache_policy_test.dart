import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/cache_policy.dart';

void main() {
  group('CachePolicy', () {
    test('shouldEvict returns true when over limit', () {
      const policy = CachePolicy(maxBytes: 1024);
      expect(policy.shouldEvict(2048), isTrue);
    });

    test('shouldEvict returns false when under limit', () {
      const policy = CachePolicy(maxBytes: 1024);
      expect(policy.shouldEvict(512), isFalse);
    });

    test('shouldEvict returns false when exactly at limit', () {
      const policy = CachePolicy(maxBytes: 1024);
      expect(policy.shouldEvict(1024), isFalse);
    });

    test('isExpired returns true when past maxAge', () {
      const policy = CachePolicy(maxBytes: 1024, maxAge: Duration(hours: 1));
      expect(
        policy.isExpired(DateTime.now().subtract(const Duration(hours: 2))),
        isTrue,
      );
    });

    test('isExpired returns false when within maxAge', () {
      const policy = CachePolicy(maxBytes: 1024, maxAge: Duration(hours: 1));
      expect(policy.isExpired(DateTime.now()), isFalse);
    });

    test('default maxAge is 7 days', () {
      const policy = CachePolicy(maxBytes: 1024);
      expect(policy.maxAge, const Duration(days: 7));
    });
  });
}
