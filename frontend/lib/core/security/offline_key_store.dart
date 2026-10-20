import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/security/offline_key_store_stub.dart'
    if (dart.library.io) 'package:omninest/core/security/offline_key_store_io.dart'
    if (dart.library.js_interop) 'package:omninest/core/security/offline_key_store_web.dart'
    as platform_store;

export 'package:omninest/core/security/offline_key_store_base.dart';

/// 创建当前平台的离线主密钥存储。
OfflineKeyStore createOfflineKeyStore() {
  return platform_store.createOfflineKeyStore();
}
