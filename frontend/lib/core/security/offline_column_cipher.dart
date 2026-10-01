import 'package:omninest/core/security/offline_column_cipher_stub.dart'
    if (dart.library.io) 'package:omninest/core/security/offline_column_cipher_io.dart'
    as platform_cipher;

import 'package:omninest/core/security/offline_text_cipher.dart';

export 'package:omninest/core/security/offline_text_cipher.dart';

/// 创建当前平台的离线敏感列加密器。
///
/// 仅原生平台（安全存储可用）返回实例；Web 等平台返回 null，
/// 调用方按"无加密"处理，避免用易失密钥加密落库导致跨会话无法读取。
OfflineTextCipher? createOfflineColumnCipher() {
  return platform_cipher.createOfflineColumnCipher();
}
