part of 'reader_sync_queue.dart';

/// 序列化队列载荷。
///
/// 笔记/批注的标题、正文与摘录属于敏感内容，SQLite 本身不加密且失败行会长期
/// 保留，因此落库前用列加密器加密；敏感操作在缺少加密器或用户绑定时由
/// [_enqueue] 直接拒绝，不再退化为明文。
Future<String> _serializePayload(Map<String, dynamic> data) async {
  final encoded = jsonEncode(data);
  final cipher = ReaderSyncQueue._textCipher;
  final userId = ReaderSyncQueue._userId;
  if (cipher == null || userId == null || userId.isEmpty) {
    return encoded;
  }
  return cipher.encrypt(userId, encoded);
}

/// 反序列化队列载荷；密文无法解开时回退明文（兼容升级前已落库的行），
/// 仍无法解析则返回 null，由调用方按原语义处理。
Future<Map<String, dynamic>?> _decodePayload(SyncOperation operation) async {
  final cipher = ReaderSyncQueue._textCipher;
  final userId = ReaderSyncQueue._userId;
  final stored = operation.payload;
  if (cipher != null && userId != null && userId.isNotEmpty) {
    try {
      final plain = await cipher.decrypt(userId, stored);
      return jsonDecode(plain) as Map<String, dynamic>;
    } catch (_) {
      // 旧版本可能以明文写入；继续尝试明文解析，不能把历史行直接判坏。
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
