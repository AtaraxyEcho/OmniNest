/// Web 端阅读进度崩溃备份的 localStorage 键名，按账号隔离。
///
/// 共享空间的书在不同账号下复用同一个 itemId：键名不带账号时，账号 A 留下的备份会在
/// 账号 B 首次打开同一本书（B 在 SQLite 里还没有行）时被 `preferCrashBackup` 判为唯一
/// 副本，把 A 的阅读位置写进 B 的记录。
///
/// 未绑定账号（尚未登录，或 init 没有 userId）时退回设备级键名，保持单使用者设备的读法。
library;

const String readerProgressBackupPrefix = 'omninest_progress_';

String readerProgressBackupKey({
  required String? userId,
  required String itemId,
}) {
  final owner = userId?.trim() ?? '';
  if (owner.isEmpty) {
    return '$readerProgressBackupPrefix$itemId';
  }
  return '$readerProgressBackupPrefix${owner}_$itemId';
}
