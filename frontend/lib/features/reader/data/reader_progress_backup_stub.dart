/// 非 Web 平台的空实现。
class ReaderProgressBackupWeb {
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
