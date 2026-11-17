import 'dart:typed_data';

/// 用户离线主密钥。
class OfflineMasterKey {
  const OfflineMasterKey({required this.keyId, required this.bytes});

  final String keyId;
  final Uint8List bytes;
}

/// 离线主密钥存储接口。
abstract interface class OfflineKeyStore {
  /// 读取用户主密钥，不存在时生成并持久化。
  Future<OfflineMasterKey> readOrCreate(String userId);

  /// 删除用户主密钥。
  Future<void> delete(String userId);
}
