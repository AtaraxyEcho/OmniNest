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

OfflineTextCipher? _sharedCipher;

/// 进程内共享的列加密器。
///
/// 敏感列写入方与用户数据清理流程必须拿到同一个实例：清理时删掉主密钥后要
/// 同时清掉实例里的派生密钥缓存，各自新建实例会让旧缓存留在另一个实例里，
/// 同进程重新登录后的写入随即变成无法解开的密文。Web 平台始终返回 null。
OfflineTextCipher? sharedOfflineColumnCipher() {
  return _sharedCipher ??= platform_cipher.createOfflineColumnCipher();
}
