/// 按账号分键的本地备份键名。
///
/// Web 端的崩溃备份落在 `localStorage`，键名必须带账号：共享空间的书在不同账号下
/// 复用同一个 itemId，键名不带账号时，账号 A 留下的备份会在账号 B 首次打开同一本书
/// （B 在 SQLite 里还没有行）时被当成唯一副本，把 A 的阅读位置写进 B 的记录。
///
/// 放在 core 是因为「登出清理」也要按同一套前缀扫键：清理逻辑在 core/security，
/// 不能反向依赖业务 feature，键名规则因此只能由 core 提供、feature 引用。
library;

const String userBackupKeyPrefix = 'omninest_progress_';

/// 阅读进度崩溃备份的 localStorage 键名。
///
/// 未绑定账号（尚未登录，或 init 没有 userId）时退回设备级键名，保持单使用者设备的读法。
String readerProgressBackupKey({
  required String? userId,
  required String itemId,
}) {
  final owner = userId?.trim() ?? '';
  if (owner.isEmpty) {
    return '$userBackupKeyPrefix$itemId';
  }
  return '$userBackupKeyPrefix${owner}_$itemId';
}

/// 指定账号的全部备份键前缀，登出清理按它扫键。
String userBackupKeyPrefixFor(String userId) {
  return '$userBackupKeyPrefix${userId}_';
}
