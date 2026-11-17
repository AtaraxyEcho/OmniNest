import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/security/offline_key_store_web.dart' as web;

/// 创建不支持平台安全存储时的内存密钥存储。
///
/// 必须复用 Web 的模块级单例：列加密器与登出清理要看到同一份密钥。
OfflineKeyStore createOfflineKeyStore() {
  return web.createOfflineKeyStore();
}
