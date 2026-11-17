import 'package:omninest/core/security/offline_text_cipher.dart';

/// 平台不支持持久安全存储时的列加密器工厂：返回 null，敏感列保持原样。
OfflineTextCipher? createOfflineColumnCipher() {
  return null;
}
