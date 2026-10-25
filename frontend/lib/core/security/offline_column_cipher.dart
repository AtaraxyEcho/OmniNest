import 'package:omninest/core/security/offline_column_cipher_stub.dart'
    if (dart.library.io) 'package:omninest/core/security/offline_column_cipher_io.dart'
    if (dart.library.js_interop) 'package:omninest/core/security/offline_column_cipher_web.dart'
    as platform_cipher;

import 'package:omninest/core/security/offline_text_cipher.dart';

export 'package:omninest/core/security/offline_text_cipher.dart';

/// 创建当前平台的离线敏感列加密器。
///
/// 原生平台使用系统安全存储中的主密钥；Web 使用页面内存（不承诺离线）
/// 的会话主密钥，关闭标签页即销毁。仅无安全存储能力的平台返回 null。
OfflineTextCipher? createOfflineColumnCipher() {
  return platform_cipher.createOfflineColumnCipher();
}

OfflineTextCipher? _sharedCipher;

/// 进程内共享的列加密器。
///
/// 敏感列写入方与用户数据清理流程必须拿到同一个实例：清理时删掉主密钥后要
/// 同时清掉实例里的派生密钥缓存，各自新建实例会让旧缓存留在另一个实例里，
/// 同进程重新登录后的写入随即变成无法解开的密文。
OfflineTextCipher? sharedOfflineColumnCipher() {
  return _sharedCipher ??= platform_cipher.createOfflineColumnCipher();
}
