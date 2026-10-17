import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';

/// 当前认证会话拥有的解析书籍元数据缓存。
final readerParsedBookCacheProvider = Provider<ReaderParsedBookCache>((ref) {
  final ownerUserId = ref.watch(
    authSessionProvider.select((session) => session.value?.user?.id),
  );
  final cache = ReaderParsedBookCache(ownerUserId: ownerUserId);
  ref.onDispose(cache.clear);
  return cache;
});

/// 使用固定条目预算保存最近访问的解析书籍元数据。
class ReaderParsedBookCache {
  ReaderParsedBookCache({required this.ownerUserId, this.maxEntries = 5})
    : assert(maxEntries > 0);

  /// 缓存所属用户；认证会话变化时 Provider 会创建新实例。
  final String? ownerUserId;

  /// 最大缓存条目数。
  final int maxEntries;

  final Map<String, ParsedBook> _entries = <String, ParsedBook>{};
  final List<String> _accessOrder = <String>[];

  /// 读取条目并更新最近访问顺序。
  ParsedBook? read(String itemId) {
    final book = _entries[itemId];
    if (book == null) {
      return null;
    }
    _accessOrder.remove(itemId);
    _accessOrder.add(itemId);
    return book;
  }

  /// 写入条目并淘汰最久未访问的元数据。
  void write(String itemId, ParsedBook book) {
    _entries[itemId] = book;
    _accessOrder.remove(itemId);
    _accessOrder.add(itemId);
    while (_accessOrder.length > maxEntries) {
      _entries.remove(_accessOrder.removeAt(0));
    }
  }

  /// 删除指定条目。
  void remove(String itemId) {
    _entries.remove(itemId);
    _accessOrder.remove(itemId);
  }

  /// 清空当前会话缓存。
  void clear() {
    _entries.clear();
    _accessOrder.clear();
  }
}
