/// 非 Web 平台的空实现。
///
/// 签名与 Web 实现保持一致（条件导出按同一套 API 编译），原生端进度只有 SQLite 一份，
/// 不需要 localStorage 备份，也没有跨账号的键名问题。
class ReaderProgressBackupWeb {
  static void setUserId(String? userId) {}

  static void save({
    required String itemId,
    required String chapterId,
    required int charOffset,
    required double chapterProgress,
    int? manifestVersion,
    DateTime? savedAt,
  }) {}

  static Map<String, dynamic>? load(String itemId) => null;

  static void clear(String itemId) {}
}
