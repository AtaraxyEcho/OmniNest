import 'dart:typed_data';

import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';

/// 测试用内存密钥存储：同一用户重复读取返回同一主密钥。
class InMemoryOfflineKeyStore implements OfflineKeyStore {
  final Map<String, List<int>> _keys = {};

  @override
  Future<void> delete(String userId) async {
    _keys.remove(userId);
  }

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    final key = _keys[userId] ??= List<int>.generate(32, (index) => index + 1);
    return OfflineMasterKey(keyId: 'test', bytes: Uint8List.fromList(key));
  }
}

OfflineTextCipher createTestOfflineCipher() {
  return OfflineTextCipher(keyStore: InMemoryOfflineKeyStore());
}
