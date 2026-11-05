import 'package:omninest/core/security/offline_crypto.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';

/// 当前页面共享的唯一密钥存储。
///
/// 列加密器与登出清理必须操作同一个实例：每次调用都新建会得到两套 Map，
/// 登出删掉的是空实例，真正持有主密钥的实例与其字节从未被销毁。
final MemoryOfflineKeyStore _sharedMemoryKeyStore = MemoryOfflineKeyStore();

/// 创建 Web 内存级离线主密钥存储。
///
/// Web 不承诺离线能力，主密钥只保存在当前页面内存中：刷新或重开页面即丢弃，
/// 已落库的密文按缓存未命中重建，避免 XSS 通过 sessionStorage 直接取得主密钥。
OfflineKeyStore createOfflineKeyStore() {
  return _sharedMemoryKeyStore;
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
    final removed = _keys.remove(userId);
    final bytes = removed?.bytes;
    if (bytes != null) {
      // 就地清零：仅从 Map 移除只断开引用，堆里的密钥字节要等 GC 才可能消失。
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
