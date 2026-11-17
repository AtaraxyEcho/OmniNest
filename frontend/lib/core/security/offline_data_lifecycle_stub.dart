import 'package:omninest/core/security/offline_data_lifecycle_base.dart';
import 'package:omninest/core/security/offline_data_lifecycle_web.dart';
import 'package:omninest/core/security/offline_key_store.dart';

/// 无持久平台能力时不执行离线数据迁移。
Future<void> initializeOfflineDataLifecycle() async {}

/// 创建无持久平台能力时的离线敏感数据生命周期实现。
OfflineDataLifecycle createOfflineDataLifecycle() {
  return WebOfflineDataLifecycle(keyStore: createOfflineKeyStore());
}
