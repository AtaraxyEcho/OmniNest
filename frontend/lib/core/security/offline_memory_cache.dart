import 'dart:collection';
import 'dart:typed_data';

/// Web 会话内敏感字节缓存。
class OfflineMemoryCache {
  OfflineMemoryCache._();

  static const int _defaultMaxTypeBytes = 32 * 1024 * 1024;
  static const Map<String, int> _typeBudgets = <String, int>{
    'reader-book': 128 * 1024 * 1024,
    'reader-image': 64 * 1024 * 1024,
  };

  static final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, int> _usageBytes = <String, int>{};

  /// 读取用户与用途隔离的缓存内容。
  static Uint8List? read({
    required String userId,
    required String cacheType,
    required String businessId,
  }) {
    final key = _key(userId, cacheType, businessId);
    final bytes = _entries.remove(key);
    if (bytes == null) {
      return null;
    }
    _entries[key] = bytes;
    return bytes;
  }

  /// 写入用户与用途隔离的缓存内容。
  static void write({
    required String userId,
    required String cacheType,
    required String businessId,
    required Uint8List bytes,
    int? maxTypeBytes,
  }) {
    final scope = _prefix(userId, cacheType);
    final key = _key(userId, cacheType, businessId);
    final budget =
        maxTypeBytes ?? _typeBudgets[cacheType] ?? _defaultMaxTypeBytes;
    _removeKey(key, scope);
    if (bytes.length > budget) {
      return;
    }
    _entries[key] = bytes;
    _usageBytes[scope] = (_usageBytes[scope] ?? 0) + bytes.length;
    _evictToBudget(scope, budget);
  }

  /// 判断缓存是否存在。
  static bool contains({
    required String userId,
    required String cacheType,
    required String businessId,
  }) {
    return _entries.containsKey(_key(userId, cacheType, businessId));
  }

  /// 删除单项缓存。
  static void remove({
    required String userId,
    required String cacheType,
    required String businessId,
  }) {
    final scope = _prefix(userId, cacheType);
    _removeKey(_key(userId, cacheType, businessId), scope);
  }

  /// 删除业务标识符合前缀的缓存。
  static void removeByBusinessPrefix({
    required String userId,
    required String cacheType,
    required String businessPrefix,
  }) {
    final scope = _prefix(userId, cacheType);
    final businessKeyPrefix = '$scope$businessPrefix';
    final keys = _entries.keys
        .where((key) => key.startsWith(businessKeyPrefix))
        .toList(growable: false);
    for (final key in keys) {
      _removeKey(key, scope);
    }
  }

  /// 清除指定用户和用途的全部缓存。
  static void clearType({required String userId, required String cacheType}) {
    final scope = _prefix(userId, cacheType);
    _entries.removeWhere((key, _) => key.startsWith(scope));
    _usageBytes.remove(scope);
  }

  /// 统计指定用户和用途的缓存字节数。
  static int sizeBytes({required String userId, required String cacheType}) {
    return _usageBytes[_prefix(userId, cacheType)] ?? 0;
  }

  /// 清除指定用户的全部会话缓存。
  static void clearUser(String userId) {
    final prefix = '$userId\u0000';
    _entries.removeWhere((key, _) => key.startsWith(prefix));
    _usageBytes.removeWhere((scope, _) => scope.startsWith(prefix));
  }

  static void _evictToBudget(String scope, int budget) {
    while ((_usageBytes[scope] ?? 0) > budget) {
      final oldestKey = _entries.keys.firstWhere(
        (key) => key.startsWith(scope),
        orElse: () => '',
      );
      if (oldestKey.isEmpty) {
        _usageBytes.remove(scope);
        return;
      }
      _removeKey(oldestKey, scope);
    }
  }

  static void _removeKey(String key, String scope) {
    final removed = _entries.remove(key);
    if (removed == null) {
      return;
    }
    final remaining = (_usageBytes[scope] ?? 0) - removed.length;
    if (remaining > 0) {
      _usageBytes[scope] = remaining;
    } else {
      _usageBytes.remove(scope);
    }
  }

  static String _key(String userId, String cacheType, String businessId) {
    return '${_prefix(userId, cacheType)}$businessId';
  }

  static String _prefix(String userId, String cacheType) {
    return '$userId\u0000$cacheType\u0000';
  }
}
