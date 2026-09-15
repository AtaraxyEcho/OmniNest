import 'package:drift/drift.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/domain/reader_note.dart';
import 'package:omninest/features/reader/domain/reader_progress.dart';

/// 阅读器本地 SQLite 存储
///
/// 基于 Drift 封装阅读进度、书签、标注、笔记的离线缓存读写。
/// 所有写操作先存本地，再通过 ReaderSyncQueue 异步同步服务端。
class ReaderLocalStorage {
  const ReaderLocalStorage(this._db);

  final LocalDatabase _db;

  // ─── Progress ────────────────────────────────────────────────

  Future<void> saveProgress(ReaderProgress progress) async {
    await _db
        .into(_db.cachedReaderProgress)
        .insertOnConflictUpdate(
          CachedReaderProgressCompanion.insert(
            itemId: progress.readerItemId,
            charOffset: Value(progress.charOffset.toInt()),
            chapterProgress: Value(progress.progressPercent),
            mode: Value(progress.readingMode),
            chapterId: Value(progress.chapterId ?? ''),
            pageId: Value(progress.pageId),
            pageIndex: Value(progress.pageIndex),
            pageFingerprint: Value(progress.pageFingerprint),
            sourceId: Value(progress.sourceId),
            sourcePageIndex: Value(progress.sourcePageIndex),
            catalogKey: Value(progress.catalogKey),
            manifestVersion: Value(progress.manifestVersion),
            intraPageOffset: Value(progress.intraPageOffset),
            updatedAt: progress.updatedAt ?? DateTime.now(),
          ),
        );
  }

  Future<ReaderProgress?> loadProgress(
    String itemId, {
    String? chapterId,
  }) async {
    final query = _db.select(_db.cachedReaderProgress)..where(
      (t) =>
          t.itemId.equals(itemId) &
          (chapterId != null
              ? t.chapterId.equals(chapterId)
              : t.chapterId.equals('')),
    );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ReaderProgress(
      readerItemId: row.itemId,
      charOffset: row.charOffset,
      progressPercent: row.chapterProgress,
      readingMode: row.mode,
      chapterId: row.chapterId,
      pageId: row.pageId,
      pageIndex: row.pageIndex,
      pageFingerprint: row.pageFingerprint,
      sourceId: row.sourceId,
      sourcePageIndex: row.sourcePageIndex,
      catalogKey: row.catalogKey,
      manifestVersion: row.manifestVersion,
      intraPageOffset: row.intraPageOffset,
      updatedAt: row.updatedAt,
    );
  }

  Future<void> deleteProgress(String itemId) async {
    await (_db.delete(_db.cachedReaderProgress)
      ..where((t) => t.itemId.equals(itemId))).go();
  }

  // ─── Bookmarks ───────────────────────────────────────────────

  Future<void> saveBookmark(ReaderBookmark bookmark) async {
    await _db
        .into(_db.cachedReaderBookmarks)
        .insertOnConflictUpdate(
          CachedReaderBookmarksCompanion.insert(
            id: bookmark.id,
            readerItemId: bookmark.readerItemId,
            charOffset: Value(bookmark.charOffset),
            progressPercent: Value(bookmark.progressPercent),
            note: Value(bookmark.note),
            createdAt: bookmark.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<ReaderBookmark>> loadBookmarks(String itemId) async {
    final query =
        _db.select(_db.cachedReaderBookmarks)
          ..where((t) => t.readerItemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm.asc(t.charOffset)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => ReaderBookmark(
            id: row.id,
            readerItemId: row.readerItemId,
            charOffset: row.charOffset,
            progressPercent: row.progressPercent,
            note: row.note,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    await (_db.delete(_db.cachedReaderBookmarks)
      ..where((t) => t.id.equals(bookmarkId))).go();
  }

  /// 用服务端书签替换本地临时书签。
  Future<void> replaceBookmarkId({
    required String localId,
    required ReaderBookmark serverBookmark,
  }) async {
    await _db.transaction(() async {
      await deleteBookmark(localId);
      await saveBookmark(serverBookmark);
    });
  }

  Future<void> deleteBookmarksForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderBookmarks)
      ..where((t) => t.readerItemId.equals(itemId))).go();
  }

  // ─── Annotations ─────────────────────────────────────────────

  Future<void> saveAnnotation(ReaderAnnotation annotation) async {
    await _db
        .into(_db.cachedReaderAnnotations)
        .insertOnConflictUpdate(
          CachedReaderAnnotationsCompanion.insert(
            id: annotation.id,
            readerItemId: annotation.readerItemId,
            chapterId: Value(annotation.chapterId),
            startOffset: annotation.startOffset,
            endOffset: annotation.endOffset,
            highlightText: Value(annotation.highlightText),
            note: Value(annotation.note),
            color: Value(annotation.color),
            createdAt: annotation.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<ReaderAnnotation>> loadAnnotations(String itemId) async {
    final query =
        _db.select(_db.cachedReaderAnnotations)
          ..where((t) => t.readerItemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm.asc(t.startOffset)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => ReaderAnnotation(
            id: row.id,
            readerItemId: row.readerItemId,
            chapterId: row.chapterId,
            startOffset: row.startOffset,
            endOffset: row.endOffset,
            highlightText: row.highlightText,
            note: row.note,
            color: row.color,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }

  Future<void> updateAnnotation(
    String annotationId, {
    String? note,
    String? color,
  }) async {
    await (_db.update(_db.cachedReaderAnnotations)
      ..where((t) => t.id.equals(annotationId))).write(
      CachedReaderAnnotationsCompanion(
        note: Value(note),
        color: color != null ? Value(color) : const Value.absent(),
      ),
    );
  }

  Future<void> deleteAnnotation(String annotationId) async {
    await (_db.delete(_db.cachedReaderAnnotations)
      ..where((t) => t.id.equals(annotationId))).go();
  }

  /// 用服务端标注替换本地临时标注。
  Future<void> replaceAnnotationId({
    required String localId,
    required ReaderAnnotation serverAnnotation,
  }) async {
    await _db.transaction(() async {
      await deleteAnnotation(localId);
      await saveAnnotation(serverAnnotation);
    });
  }

  Future<void> deleteAnnotationsForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderAnnotations)
      ..where((t) => t.readerItemId.equals(itemId))).go();
  }

  // ─── Notes ───────────────────────────────────────────────────

  Future<void> saveNote(ReaderNote note) async {
    await _db
        .into(_db.cachedReaderNotes)
        .insertOnConflictUpdate(
          CachedReaderNotesCompanion.insert(
            id: note.id,
            readerItemId: note.readerItemId,
            charOffset: Value(note.charOffset),
            title: Value(note.title),
            content: note.content,
            createdAt: note.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<ReaderNote>> loadNotes(String itemId) async {
    final query =
        _db.select(_db.cachedReaderNotes)
          ..where((t) => t.readerItemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => ReaderNote(
            id: row.id,
            readerItemId: row.readerItemId,
            charOffset: row.charOffset,
            title: row.title,
            content: row.content,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }

  Future<void> updateNote(
    String noteId, {
    String? title,
    required String content,
  }) async {
    await (_db.update(_db.cachedReaderNotes)
      ..where((t) => t.id.equals(noteId))).write(
      CachedReaderNotesCompanion(title: Value(title), content: Value(content)),
    );
  }

  Future<void> deleteNote(String noteId) async {
    await (_db.delete(_db.cachedReaderNotes)
      ..where((t) => t.id.equals(noteId))).go();
  }

  /// 用服务端笔记替换本地临时笔记。
  Future<void> replaceNoteId({
    required String localId,
    required ReaderNote serverNote,
  }) async {
    await _db.transaction(() async {
      await deleteNote(localId);
      await saveNote(serverNote);
    });
  }

  Future<void> deleteNotesForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderNotes)
      ..where((t) => t.readerItemId.equals(itemId))).go();
  }

  // ─── 书籍元数据缓存 ──────────────────────────────────────────

  Future<void> saveBookMeta({
    required String itemId,
    String? title,
    String? author,
    String? description,
    String? publisher,
    String? language,
    required String chaptersJson,
    required int totalChars,
    required String itemType,
    String cacheVersion = '',
  }) async {
    await _db
        .into(_db.cachedReaderBooks)
        .insertOnConflictUpdate(
          CachedReaderBooksCompanion.insert(
            itemId: itemId,
            title: Value(title),
            author: Value(author),
            description: Value(description),
            publisher: Value(publisher),
            language: Value(language),
            chaptersJson: Value(chaptersJson),
            totalChars: Value(totalChars),
            itemType: Value(itemType),
            cacheVersion: Value(cacheVersion),
            cachedAt: DateTime.now(),
          ),
        );
  }

  Future<Map<String, dynamic>?> loadBookMeta(String itemId) async {
    final query = _db.select(_db.cachedReaderBooks)
      ..where((t) => t.itemId.equals(itemId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return {
      'itemId': row.itemId,
      'title': row.title,
      'author': row.author,
      'description': row.description,
      'publisher': row.publisher,
      'language': row.language,
      'chaptersJson': row.chaptersJson,
      'totalChars': row.totalChars,
      'itemType': row.itemType,
      'cacheVersion': row.cacheVersion,
      'cachedAt': row.cachedAt.toIso8601String(),
    };
  }

  /// 删除指定书籍的元数据缓存。
  Future<void> deleteBookMeta(String itemId) async {
    await (_db.delete(_db.cachedReaderBooks)
      ..where((t) => t.itemId.equals(itemId))).go();
  }

  // ─── 章节内容缓存 ──────────────────────────────────────────

  Future<void> saveChapterContent({
    required String itemId,
    required String contentPath,
    required String title,
    required int chapterNumber,
    required int charCount,
    required String processedHtml,
  }) async {
    await _db
        .into(_db.cachedReaderChapters)
        .insertOnConflictUpdate(
          CachedReaderChaptersCompanion.insert(
            itemId: itemId,
            contentPath: contentPath,
            title: Value(title),
            chapterNumber: Value(chapterNumber),
            charCount: Value(charCount),
            processedHtml: processedHtml,
            cachedAt: DateTime.now(),
          ),
        );
  }

  Future<String?> loadChapterContent({
    required String itemId,
    required String contentPath,
  }) async {
    final query = _db.select(_db.cachedReaderChapters)..where(
      (t) => t.itemId.equals(itemId) & t.contentPath.equals(contentPath),
    );
    final row = await query.getSingleOrNull();
    return row?.processedHtml;
  }

  /// 删除指定书籍的所有章节缓存
  Future<void> deleteChaptersForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderChapters)
      ..where((t) => t.itemId.equals(itemId))).go();
  }

  /// 删除单个章节的缓存内容，损坏章节精准清理时避免整本书失效。
  Future<void> deleteChapter(String itemId, String contentPath) async {
    await (_db.delete(_db.cachedReaderChapters)..where(
      (t) => t.itemId.equals(itemId) & t.contentPath.equals(contentPath),
    )).go();
  }

  /// 清理超过指定天数的章节缓存
  Future<void> cleanOldChapters({int maxAgeDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
    await (_db.delete(_db.cachedReaderChapters)
      ..where((t) => t.cachedAt.isSmallerThanValue(cutoff))).go();
  }

  // ─── 书籍详情缓存 ──────────────────────────────────────────

  Future<void> deleteBookDetail(String itemId) async {
    await (_db.delete(_db.cachedReaderBookDetails)
      ..where((t) => t.itemId.equals(itemId))).go();
  }

  // ─── Bulk cleanup ────────────────────────────────────────────

  /// 删除指定条目的结构化本地数据。
  Future<void> deleteAllForItem(String itemId) async {
    await deleteProgress(itemId);
    await deleteBookmarksForItem(itemId);
    await deleteAnnotationsForItem(itemId);
    await deleteNotesForItem(itemId);
    await deleteChaptersForItem(itemId);
    await deleteBookDetail(itemId);
  }
}
