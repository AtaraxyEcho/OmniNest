import 'package:omninest/core/security/offline_key_store_web.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';

/// Web 端列加密器工厂：使用标签页会话级主密钥加密落库的敏感列。
OfflineTextCipher createOfflineColumnCipher() {
  return OfflineTextCipher(keyStore: createOfflineKeyStore());
}
