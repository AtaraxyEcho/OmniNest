/// 阅读进度本地存储端口。
abstract interface class ReaderLocalProgressStore {
  /// 保存阅读进度。
  Future<void> save({
    required String itemId,
    required double chapterProgress,
    required String mode,
    String? chapterId,
    int charOffset = 0,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
    DateTime? updatedAt,
  });

  /// 按书籍和章节读取进度。
  Future<Map<String, dynamic>?> load(String itemId, String chapterId);

  /// 读取书籍最近保存的进度。
  Future<Map<String, dynamic>?> loadLatest(String itemId);

  /// 清除书籍的本地进度。
  Future<void> clear(String itemId);
}

/// 阅读进度本地存储门面。
class ReaderLocalProgress {
  static ReaderLocalProgressStore? _store;

  /// 注入本地存储实现。
  static void init(ReaderLocalProgressStore store) {
    _store = store;
  }

  static ReaderLocalProgressStore get _requiredStore {
    final store = _store;
    if (store != null) {
      return store;
    }
    throw StateError(
      'ReaderLocalProgress not initialized. '
      'Call ReaderLocalProgress.init(store) first.',
    );
  }

  /// 保存阅读进度。
  static Future<void> save({
    required String itemId,
    required double chapterProgress,
    required String mode,
    String? chapterId,
    int charOffset = 0,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
    DateTime? updatedAt,
  }) {
    return _requiredStore.save(
      itemId: itemId,
      chapterProgress: chapterProgress,
      mode: mode,
      chapterId: chapterId,
      charOffset: charOffset,
      pageId: pageId,
      pageIndex: pageIndex,
      pageFingerprint: pageFingerprint,
      sourceId: sourceId,
      sourcePageIndex: sourcePageIndex,
      catalogKey: catalogKey,
      manifestVersion: manifestVersion,
      intraPageOffset: intraPageOffset,
      updatedAt: updatedAt,
    );
  }

  /// 按书籍和章节读取进度。
  static Future<Map<String, dynamic>?> load(String itemId, String chapterId) {
    return _requiredStore.load(itemId, chapterId);
  }

  /// 读取书籍最近保存的进度。
  static Future<Map<String, dynamic>?> loadLatest(String itemId) {
    return _requiredStore.loadLatest(itemId);
  }

  /// 清除书籍的本地进度。
  static Future<void> clear(String itemId) {
    return _requiredStore.clear(itemId);
  }
}
