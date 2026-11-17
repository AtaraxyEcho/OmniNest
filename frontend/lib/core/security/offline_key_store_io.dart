import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omninest/core/security/offline_crypto.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';

/// 进程级单例：文件保险库与列加密器各自调用工厂，但主密钥只能有一把，
/// 单飞锁必须全局生效，否则并发首次读取会生成两把密钥并互相覆盖。
final SecureOfflineKeyStore _sharedIoKeyStore = SecureOfflineKeyStore();

/// 创建原生平台离线主密钥存储（复用进程级单例）。
OfflineKeyStore createOfflineKeyStore() {
  return _sharedIoKeyStore;
}

/// 使用系统安全存储保存离线主密钥。
class SecureOfflineKeyStore implements OfflineKeyStore {
  SecureOfflineKeyStore({
    FlutterSecureStorage? secureStorage,
    OfflineCrypto crypto = const OfflineCrypto(),
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _crypto = crypto;

  static const _keyId = 'master-v1';
  static const _storagePrefix = 'omninest.offline.master.v1.';

  final FlutterSecureStorage _secureStorage;
  final OfflineCrypto _crypto;

  /// 按用户的进行中读取：并发的首次调用共享同一个 Future，
  /// 避免两次 read 都读到 null 后各生成一把主密钥。
  final Map<String, Future<OfflineMasterKey>> _inFlight = {};

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) {
    return _inFlight.putIfAbsent(userId, () async {
      try {
        return await _readOrCreateUnlocked(userId);
      } finally {
        _inFlight.remove(userId);
      }
    });
  }

  Future<OfflineMasterKey> _readOrCreateUnlocked(String userId) async {
    final storageKey = _storageKey(userId);
    final encoded = await _secureStorage.read(key: storageKey);
    if (encoded != null && encoded.isNotEmpty) {
      final bytes = _decodeKey(encoded);
      if (bytes != null) {
        return OfflineMasterKey(keyId: _keyId, bytes: bytes);
      }
    }

    final bytes = _crypto.generateKey();
    await _secureStorage.write(key: storageKey, value: base64Encode(bytes));
    return OfflineMasterKey(keyId: _keyId, bytes: bytes);
  }

  @override
  Future<void> delete(String userId) async {
    // 必须先等进行中的创建结束：先删后写会让刚生成的密钥在登出后又落回存储。
    final pending = _inFlight[userId];
    if (pending != null) {
      try {
        await pending;
      } on Object {
        // 读取失败说明没有可用密钥，直接继续删除存储键。
      }
    }
    await _secureStorage.delete(key: _storageKey(userId));
  }

  Uint8List? _decodeKey(String encoded) {
    try {
      final bytes = base64Decode(encoded);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } on FormatException {
      return null;
    }
  }

  String _storageKey(String userId) {
    final userKey = base64UrlEncode(utf8.encode(userId)).replaceAll('=', '');
    return '$_storagePrefix$userKey';
  }
}
