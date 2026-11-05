import 'package:omninest/core/security/offline_data_lifecycle_base.dart';
import 'package:omninest/core/security/offline_key_store.dart';
import 'package:omninest/core/security/offline_memory_cache.dart';
import 'package:omninest/core/storage/user_backup_keys.dart';
import 'package:web/web.dart' as web;

/// Web 平台没有需要迁移的持久化明文缓存。
Future<void> initializeOfflineDataLifecycle() async {}

/// 创建 Web 会话级离线敏感数据生命周期实现。
OfflineDataLifecycle createOfflineDataLifecycle() {
  return WebOfflineDataLifecycle(keyStore: createOfflineKeyStore());
}

/// 清理 Web 会话级主密钥。
class WebOfflineDataLifecycle implements OfflineDataLifecycle {
  WebOfflineDataLifecycle({required OfflineKeyStore keyStore})
    : _keyStore = keyStore;

  final OfflineKeyStore _keyStore;

  @override
  Future<void> clearUser(String userId) async {
    OfflineMemoryCache.clearUser(userId);
    await _keyStore.delete(userId);
    _clearReaderProgressBackups(userId);
  }

  /// 阅读进度的崩溃备份按 `omninest_progress_<userId>_<itemId>` 落在 localStorage，
  /// 不会随 SQLite 清理消失；登出后它仍能被下次登录的恢复流程读到。
  void _clearReaderProgressBackups(String userId) {
    if (userId.isEmpty) {
      return;
    }
    try {
      final storage = web.window.localStorage;
      final prefix = userBackupKeyPrefixFor(userId);
      // 先收集再删除：边遍历边 removeItem 会让后续下标整体前移，漏掉一部分键。
      final targets = <String>[];
      for (var index = 0; index < storage.length; index++) {
        final key = storage.key(index);
        if (key != null && key.startsWith(prefix)) {
          targets.add(key);
        }
      }
      for (final key in targets) {
        storage.removeItem(key);
      }
    } on Exception {
      // localStorage 被浏览器禁用时清不掉，登出流程不能因此中断。
    }
  }
}
