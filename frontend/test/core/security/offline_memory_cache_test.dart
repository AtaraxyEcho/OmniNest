import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/offline_memory_cache.dart';

void main() {
  const userId = 'memory-budget-user';
  const cacheType = 'test-cache';

  tearDown(() {
    OfflineMemoryCache.clearUser(userId);
  });

  test('按用户和缓存类型的字节预算执行 LRU 淘汰', () {
    OfflineMemoryCache.write(
      userId: userId,
      cacheType: cacheType,
      businessId: 'first',
      bytes: Uint8List.fromList(<int>[1, 1]),
      maxTypeBytes: 4,
    );
    OfflineMemoryCache.write(
      userId: userId,
      cacheType: cacheType,
      businessId: 'second',
      bytes: Uint8List.fromList(<int>[2, 2]),
      maxTypeBytes: 4,
    );

    expect(
      OfflineMemoryCache.read(
        userId: userId,
        cacheType: cacheType,
        businessId: 'first',
      ),
      isNotNull,
    );

    OfflineMemoryCache.write(
      userId: userId,
      cacheType: cacheType,
      businessId: 'third',
      bytes: Uint8List.fromList(<int>[3, 3]),
      maxTypeBytes: 4,
    );

    expect(
      OfflineMemoryCache.contains(
        userId: userId,
        cacheType: cacheType,
        businessId: 'first',
      ),
      isTrue,
    );
    expect(
      OfflineMemoryCache.contains(
        userId: userId,
        cacheType: cacheType,
        businessId: 'second',
      ),
      isFalse,
    );
    expect(
      OfflineMemoryCache.contains(
        userId: userId,
        cacheType: cacheType,
        businessId: 'third',
      ),
      isTrue,
    );
    expect(
      OfflineMemoryCache.sizeBytes(userId: userId, cacheType: cacheType),
      4,
    );
  });

  test('超过单类预算的单项不会进入缓存', () {
    OfflineMemoryCache.write(
      userId: userId,
      cacheType: cacheType,
      businessId: 'oversized',
      bytes: Uint8List(5),
      maxTypeBytes: 4,
    );

    expect(
      OfflineMemoryCache.contains(
        userId: userId,
        cacheType: cacheType,
        businessId: 'oversized',
      ),
      isFalse,
    );
    expect(
      OfflineMemoryCache.sizeBytes(userId: userId, cacheType: cacheType),
      0,
    );
  });
}
