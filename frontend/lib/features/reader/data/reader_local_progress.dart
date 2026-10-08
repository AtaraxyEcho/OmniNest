import 'package:drift/drift.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';

/// 基于 SQLite 的阅读进度本地存储。
class DatabaseReaderLocalProgressStore implements ReaderLocalProgressStore {
  /// 创建阅读进度本地存储。
  const DatabaseReaderLocalProgressStore(this._database);

  final LocalDatabase _database;

  /// 保存进度到本地 SQLite。
  @override
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
  }) async {
    // 沿用进度自己的记录时刻：写盘时刻顶掉它，会让延迟落盘或失败重放的旧读数
    // 被打成"刚刚"，与上报侧的时间口径分家。
    final recordedAt = updatedAt ?? DateTime.now();
    await _database
        .into(_database.cachedReaderProgress)
        .insertOnConflictUpdate(
          CachedReaderProgressCompanion.insert(
            itemId: itemId,
            charOffset: Value(charOffset),
            chapterProgress: Value(chapterProgress),
            mode: Value(mode),
            chapterId: Value(chapterId ?? ''),
            pageId: Value(pageId),
            pageIndex: Value(pageIndex),
            pageFingerprint: Value(pageFingerprint),
            sourceId: Value(sourceId),
            sourcePageIndex: Value(sourcePageIndex),
            catalogKey: Value(catalogKey),
            manifestVersion: Value(manifestVersion),
            intraPageOffset: Value(intraPageOffset),
            updatedAt: recordedAt,
          ),
        );
  }

  /// 按 (itemId, chapterId) 读取指定章节的进度。
  @override
  Future<Map<String, dynamic>?> load(String itemId, String chapterId) async {
    final rows =
        await (_database.select(_database.cachedReaderProgress)
              ..where(
                (t) => t.itemId.equals(itemId) & t.chapterId.equals(chapterId),
              )
              ..limit(1))
            .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'charOffset': row.charOffset,
      'chapterProgress': row.chapterProgress,
      'mode': row.mode,
      'chapterId': row.chapterId,
      'pageId': row.pageId,
      'pageIndex': row.pageIndex,
      'pageFingerprint': row.pageFingerprint,
      'sourceId': row.sourceId,
      'sourcePageIndex': row.sourcePageIndex,
      'catalogKey': row.catalogKey,
      'manifestVersion': row.manifestVersion,
      'intraPageOffset': row.intraPageOffset,
      'updatedAt': row.updatedAt.toIso8601String(),
    };
  }

  /// 读取最近保存的一条进度（任意章节），用于 fallback。
  @override
  Future<Map<String, dynamic>?> loadLatest(String itemId) async {
    final rows =
        await (_database.select(_database.cachedReaderProgress)
              ..where((t) => t.itemId.equals(itemId))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'charOffset': row.charOffset,
      'chapterProgress': row.chapterProgress,
      'mode': row.mode,
      'chapterId': row.chapterId,
      'pageId': row.pageId,
      'pageIndex': row.pageIndex,
      'pageFingerprint': row.pageFingerprint,
      'sourceId': row.sourceId,
      'sourcePageIndex': row.sourcePageIndex,
      'catalogKey': row.catalogKey,
      'manifestVersion': row.manifestVersion,
      'intraPageOffset': row.intraPageOffset,
      'updatedAt': row.updatedAt.toIso8601String(),
    };
  }

  /// 清除本地进度。
  @override
  Future<void> clear(String itemId) async {
    await (_database.delete(_database.cachedReaderProgress)
      ..where((table) => table.itemId.equals(itemId))).go();
  }
}
