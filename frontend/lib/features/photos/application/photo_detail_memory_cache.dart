import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 进程内照片详情缓存。
///
/// 详情接口会签发原图 sourceUrl、动态视频与 AI 分析；列表接口刻意不带
/// sourceUrl。缓存最近详情结果，使反复进出详情页时 UI 可立刻用列表已有
/// 字段与磁盘图片缓存秒开，网络请求改为后台补全。
class PhotoDetailMemoryCache {
  PhotoDetailMemoryCache({this.maxEntries = 120});

  final int maxEntries;
  final LinkedHashMap<String, PhotoItem> _entries = LinkedHashMap();

  PhotoItem? get(String id) => _entries[id];

  void put(PhotoItem photo) {
    if (photo.id.isEmpty) {
      return;
    }
    _entries.remove(photo.id);
    _entries[photo.id] = photo;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate(String id) {
    _entries.remove(id);
  }

  void clear() {
    _entries.clear();
  }
}

final photoDetailMemoryCacheProvider = Provider<PhotoDetailMemoryCache>((ref) {
  final cache = PhotoDetailMemoryCache();
  // 退出登录后同一进程可能切到另一个账号：进程内详情缓存必须立刻失效。
  ref.listen(authSessionProvider, (previous, next) {
    final wasAuthenticated = previous?.value?.isAuthenticated ?? false;
    final isAuthenticated = next.value?.isAuthenticated ?? false;
    if (wasAuthenticated && !isAuthenticated) {
      cache.clear();
    }
  });
  return cache;
});
