import 'package:omninest/core/security/offline_crypto.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';

/// 创建 Web 内存级离线主密钥存储。
///
/// Web 不承诺离线能力，主密钥只保存在当前页面内存中：刷新或重开页面即丢弃，
/// 已落库的密文按缓存未命中重建，避免 XSS 通过 sessionStorage 直接取得主密钥。
OfflineKeyStore createOfflineKeyStore() {
  return MemoryOfflineKeyStore();
}

/// 纯内存密钥存储，保留给 Web 与纯 Stub 平台复用。
class MemoryOfflineKeyStore implements OfflineKeyStore {
  MemoryOfflineKeyStore({OfflineCrypto crypto = const OfflineCrypto()})
    : _crypto = crypto;

  final OfflineCrypto _crypto;
  final Map<String, OfflineMasterKey> _keys = <String, OfflineMasterKey>{};

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    return _keys.putIfAbsent(
      userId,
      () => OfflineMasterKey(keyId: 'memory-v1', bytes: _crypto.generateKey()),
    );
  }

  @override
  Future<void> delete(String userId) async {
    _keys.remove(userId);
  }
}
