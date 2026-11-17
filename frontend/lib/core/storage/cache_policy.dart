/// 缓存策略：基于大小和时间的本地缓存管理。
class CachePolicy {
  const CachePolicy({
    required this.maxBytes,
    this.maxAge = const Duration(days: 7),
  });

  final int maxBytes;
  final Duration maxAge;

  /// 缓存是否超限。
  bool shouldEvict(int currentBytes) => currentBytes > maxBytes;

  /// 缓存条目是否过期。
  bool isExpired(DateTime cachedAt) =>
      DateTime.now().difference(cachedAt) > maxAge;
}
