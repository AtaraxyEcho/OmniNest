/// Web 端阅读进度崩溃备份的 localStorage 键名，按账号隔离。
///
/// 键名规则与「登出清理」共用同一份实现：清理在 `core/security` 里按前缀扫键，
/// 不能反向依赖业务 feature，因此规则本身落在 `core/storage/user_backup_keys.dart`。
library;

export 'package:omninest/core/storage/user_backup_keys.dart'
    show readerProgressBackupKey, userBackupKeyPrefix, userBackupKeyPrefixFor;
