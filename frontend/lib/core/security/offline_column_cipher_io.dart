import 'package:omninest/core/security/offline_key_store_io.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';

/// 原生平台（Android/Desktop）列加密器工厂：
/// 基于系统安全存储中的离线主密钥派生列密钥。
OfflineTextCipher createOfflineColumnCipher() {
  return OfflineTextCipher(keyStore: createOfflineKeyStore());
}
