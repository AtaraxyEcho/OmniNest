import 'package:drift/drift.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';

/// 基于 SQLite 的阅读进度本地存储。
///
/// [userId] 是账号归属：共享书籍在不同账号下复用同一个 itemId，读取必须按归属
/// 过滤，否则换号会读到上一个账号的位置。未登录时按写入用的 `''` 精确匹配，
/// 不放行成全表匹配。
class DatabaseReaderLocalProgressStore implements ReaderLocalProgressStore {
  /// 创建阅读进度本地存储。
  const DatabaseReaderLocalProgressStore(this._database, {String? userId})
    : _userId = userId;

  final LocalDatabase _database;
  final String? _userId;

  /// 归属账号过滤：按写入时落的同一取值（未登录时为 `''`）精确匹配。
  Expression<bool> _ownerFilter(GeneratedColumn<String> column) =>
      column.equals(_userId ?? '');

  /// 保存进度到本地 SQLite。
  @override
  Future<void> save({
    required String itemId,
    required double chapterProgress,
    required String mode,
    String? chapterId,
    int charOffset = 0,
    double? bookProgress,
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
            userId: Value(_userId ?? ''),
            itemId: itemId,
            charOffset: Value(charOffset),
            chapterProgress: Value(chapterProgress),
            bookProgress: Value(bookProgress),
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
                (t) =>
                    t.itemId.equals(itemId) &
                    t.chapterId.equals(chapterId) &
                    _ownerFilter(t.userId),
              )
              ..limit(1))
            .get();
    if (rows.isEmpty) {
      return null;
    }
    return _toPayload(rows.first);
  }

  /// 读取最近保存的一条进度（任意章节），用于 fallback。
  @override
  Future<Map<String, dynamic>?> loadLatest(String itemId) async {
    final rows =
        await (_database.select(_database.cachedReaderProgress)
              ..where((t) => t.itemId.equals(itemId) & _ownerFilter(t.userId))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .get();
    if (rows.isEmpty) {
      return null;
    }
    return _toPayload(rows.first);
  }

  /// 清除本地进度。
  @override
  Future<void> clear(String itemId) async {
    await (_database.delete(_database.cachedReaderProgress)..where(
      (table) => table.itemId.equals(itemId) & _ownerFilter(table.userId),
    )).go();
  }

  Map<String, dynamic> _toPayload(CachedReaderProgressData row) {
    return {
      'charOffset': row.charOffset,
      'chapterProgress': row.chapterProgress,
      'bookProgress': row.bookProgress,
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
}
