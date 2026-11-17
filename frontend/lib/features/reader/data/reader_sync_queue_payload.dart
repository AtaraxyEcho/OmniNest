part of 'reader_sync_queue.dart';

/// 序列化队列载荷。
///
/// 只有笔记/批注正文与摘录在落库前加密。进度、删除目标 ID 与会话记录不含
/// 隐私正文，保持明文 JSON：它们必须在密钥不可用的另一个标签页里也可读，
/// 否则跨标签页比较进度与读取待删 ID 都会失败，进而误删别人的队列行。
Future<String> _serializePayload(String type, Map<String, dynamic> data) async {
  final encoded = jsonEncode(data);
  if (!ReaderSyncQueue._encryptedOperationTypes.contains(type)) {
    return encoded;
  }
  final cipher = ReaderSyncQueue._textCipher;
  final userId = ReaderSyncQueue._userId;
  if (cipher == null || userId == null || userId.isEmpty) {
    return encoded;
  }
  return cipher.encrypt(userId, encoded);
}

/// 反序列化队列载荷。
///
/// 密文只能用当前密钥解开；密钥不可用或认证失败一律返回 null，禁止把密文
/// 当明文再解析一次。无前缀的历史行按明文兼容读取。
Future<Map<String, dynamic>?> _decodePayload(SyncOperation operation) async {
  final cipher = ReaderSyncQueue._textCipher;
  final userId = ReaderSyncQueue._userId;
  final stored = operation.payload;
  final encrypted = OfflineTextCipher.isEncryptedValue(stored);
  if (encrypted) {
    if (cipher == null || userId == null || userId.isEmpty) {
      return null;
    }
    final plain = await cipher.decrypt(userId, stored);
    if (plain.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(plain) as Map<String, dynamic>;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
  try {
    return jsonDecode(stored) as Map<String, dynamic>;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

/// 载荷在当前会话内不可恢复（密钥轮换或数据损坏），区别于可重试的网络失败。
class _UnrecoverableSyncPayload implements Exception {
  const _UnrecoverableSyncPayload();
}
