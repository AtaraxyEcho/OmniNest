import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/domain/reader_note.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读器本地 SQLite 存储
///
/// 基于 Drift 封装阅读进度、书签、标注、笔记的离线缓存读写。
/// 所有写操作先存本地，再通过 ReaderSyncQueue 异步同步服务端。
class ReaderLocalStorage {
  ReaderLocalStorage(this._db, {OfflineTextCipher? textCipher, String? userId})
    : _textCipher = textCipher,
      _columnUserId = userId;

  final LocalDatabase _db;

  /// 离线敏感列加密器与所属用户；任一为空时列保持原样（Web 或未登录场景）。
  final OfflineTextCipher? _textCipher;
  final String? _columnUserId;

  Future<String> _encipher(String plaintext) async {
    final cipher = _textCipher;
    final userId = _columnUserId;
    if (cipher == null || userId == null || userId.isEmpty) {
      return plaintext;
    }
    return cipher.encrypt(userId, plaintext);
  }

  Future<String?> _encipherNullable(String? plaintext) async {
    if (plaintext == null) {
      return null;
    }
    return _encipher(plaintext);
  }

  Future<String> _decipher(String stored) async {
    final cipher = _textCipher;
    final userId = _columnUserId;
    if (cipher == null || userId == null || userId.isEmpty) {
      return stored;
    }
    return cipher.decrypt(userId, stored);
  }

  Future<String?> _decipherNullable(String? stored) async {
    if (stored == null) {
      return null;
    }
    return _decipher(stored);
  }

  /// 归属账号过滤：按写入时落的同一取值（未登录或无归属时为 `''`）精确匹配。
  ///
  /// 共享书籍在不同账号下复用同一个 itemId，进度、书签、批注与笔记必须按写入者的
  /// 账号隔离。未登录窗口若放宽成全表匹配，会把上一个账号的书签、批注读出来，删除
  /// 与清库还会把它们一并带走；旧库升级行与未登录写入行的 `user_id` 都是 `''`，
  /// 精确匹配 `''` 既读得到设备级旧行，也不会串到具名账号。
  ///
  /// 正文与元数据缓存把归属放进了主键，一个 itemId 可以有多行：宽匹配会让
  /// `getSingleOrNull` 在换号写过之后直接抛「Too many elements」，而缓存正文本来就是
  /// 按账号密钥加密的，跨账号读也没有意义。
  Expression<bool> _ownedByUser(GeneratedColumn<String> column) =>
      column.equals(_columnUserId ?? '');

  // ─── Progress ────────────────────────────────────────────────

  /// 清除一本书的本地进度：只清当前账号归属的行。
  Future<void> deleteProgress(String itemId) async {
    await (_db.delete(_db.cachedReaderProgress)
      ..where((t) => t.itemId.equals(itemId) & _ownedByUser(t.userId))).go();
  }

  // ─── Bookmarks ───────────────────────────────────────────────

  Future<void> saveBookmark(ReaderBookmark bookmark) async {
    await _db
        .into(_db.cachedReaderBookmarks)
        .insertOnConflictUpdate(
          CachedReaderBookmarksCompanion.insert(
            id: bookmark.id,
            userId: Value(_columnUserId ?? ''),
            readerItemId: bookmark.readerItemId,
            chapterId: Value(bookmark.chapterId),
            charOffset: Value(bookmark.charOffset),
            progressPercent: Value(bookmark.progressPercent),
            note: Value(await _encipherNullable(bookmark.note)),
            createdAt: bookmark.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<ReaderBookmark>> loadBookmarks(String itemId) async {
    final query =
        _db.select(_db.cachedReaderBookmarks)
          ..where((t) => t.readerItemId.equals(itemId) & _ownedByUser(t.userId))
          ..orderBy([(t) => OrderingTerm.asc(t.charOffset)]);
    final rows = await query.get();
    final bookmarks = <ReaderBookmark>[];
    for (final row in rows) {
      bookmarks.add(
        ReaderBookmark(
          id: row.id,
          readerItemId: row.readerItemId,
          chapterId: row.chapterId,
          charOffset: row.charOffset,
          progressPercent: row.progressPercent,
          note: await _decipherNullable(row.note),
          createdAt: row.createdAt,
        ),
      );
    }
    return bookmarks;
  }

  /// 按 ID 读取单条书签；不存在或不属于当前账号时返回 null。
  Future<ReaderBookmark?> loadBookmarkById(String bookmarkId) async {
    final row =
        await (_db.select(_db.cachedReaderBookmarks)..where(
          (t) => t.id.equals(bookmarkId) & _ownedByUser(t.userId),
        )).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return ReaderBookmark(
      id: row.id,
      readerItemId: row.readerItemId,
      chapterId: row.chapterId,
      charOffset: row.charOffset,
      progressPercent: row.progressPercent,
      note: await _decipherNullable(row.note),
      createdAt: row.createdAt,
    );
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    await (_db.delete(_db.cachedReaderBookmarks)
      ..where((t) => t.id.equals(bookmarkId) & _ownedByUser(t.userId))).go();
  }

  /// 用服务端书签替换本地临时书签。
  ///
  /// 返回 false 表示本地临时行已经不在（用户在 HTTP 在途期间删了它）：此时
  /// 不得把服务端刚创建的实体写回本地，调用方需补发一次服务端删除，否则
  /// 墓碑复活且服务端永久残留。
  Future<bool> replaceBookmarkId({
    required String localId,
    required ReaderBookmark serverBookmark,
  }) async {
    return _db.transaction(() async {
      final local = await loadBookmarkById(localId);
      if (local == null) {
        return false;
      }
      await deleteBookmark(localId);
      await saveBookmark(serverBookmark);
      return true;
    });
  }

  Future<void> deleteBookmarksForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderBookmarks)..where(
      (t) => t.readerItemId.equals(itemId) & _ownedByUser(t.userId),
    )).go();
  }

  // ─── Annotations ─────────────────────────────────────────────

  Future<void> saveAnnotation(ReaderAnnotation annotation) async {
    await _db
        .into(_db.cachedReaderAnnotations)
        .insertOnConflictUpdate(
          CachedReaderAnnotationsCompanion.insert(
            id: annotation.id,
            userId: Value(_columnUserId ?? ''),
            readerItemId: annotation.readerItemId,
            chapterId: Value(annotation.chapterId),
            startOffset: annotation.startOffset,
            endOffset: annotation.endOffset,
            highlightText: Value(
              await _encipherNullable(annotation.highlightText),
            ),
            note: Value(await _encipherNullable(annotation.note)),
            color: Value(annotation.color),
            createdAt: annotation.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<ReaderAnnotation>> loadAnnotations(String itemId) async {
    final query =
        _db.select(_db.cachedReaderAnnotations)
          ..where((t) => t.readerItemId.equals(itemId) & _ownedByUser(t.userId))
          ..orderBy([(t) => OrderingTerm.asc(t.startOffset)]);
    final rows = await query.get();
    final annotations = <ReaderAnnotation>[];
    for (final row in rows) {
      annotations.add(
        ReaderAnnotation(
          id: row.id,
          readerItemId: row.readerItemId,
          chapterId: row.chapterId,
          startOffset: row.startOffset,
          endOffset: row.endOffset,
          highlightText: await _decipherNullable(row.highlightText),
          note: await _decipherNullable(row.note),
          color: row.color,
          createdAt: row.createdAt,
        ),
      );
    }
    return annotations;
  }

  /// 跨书最近标注（Reader 空间「最近笔记」数据源），按创建时间倒序。
  Future<List<ReaderAnnotation>> loadRecentAnnotations({int limit = 6}) async {
    final query =
        _db.select(_db.cachedReaderAnnotations)
          ..where((t) => _ownedByUser(t.userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit);
    final rows = await query.get();
    final annotations = <ReaderAnnotation>[];
    for (final row in rows) {
      annotations.add(
        ReaderAnnotation(
          id: row.id,
          readerItemId: row.readerItemId,
          chapterId: row.chapterId,
          startOffset: row.startOffset,
          endOffset: row.endOffset,
          highlightText: await _decipherNullable(row.highlightText),
          note: await _decipherNullable(row.note),
          color: row.color,
          createdAt: row.createdAt,
        ),
      );
    }
    return annotations;
  }

  Future<void> updateAnnotation(
    String annotationId, {
    String? note,
    String? color,
  }) async {
    await (_db.update(_db.cachedReaderAnnotations)
      ..where((t) => t.id.equals(annotationId) & _ownedByUser(t.userId))).write(
      CachedReaderAnnotationsCompanion(
        // null 表示本次不改备注，与服务端 PATCH 口径一致；空串才是清空。
        note:
            note == null
                ? const Value.absent()
                : Value(await _encipherNullable(note)),
        color: color != null ? Value(color) : const Value.absent(),
      ),
    );
  }

  Future<void> deleteAnnotation(String annotationId) async {
    await (_db.delete(_db.cachedReaderAnnotations)
      ..where((t) => t.id.equals(annotationId) & _ownedByUser(t.userId))).go();
  }

  /// 按 ID 读取单条标注；不存在或不属于当前账号时返回 null。
  Future<ReaderAnnotation?> loadAnnotationById(String annotationId) async {
    final row =
        await (_db.select(_db.cachedReaderAnnotations)..where(
          (t) => t.id.equals(annotationId) & _ownedByUser(t.userId),
        )).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return ReaderAnnotation(
      id: row.id,
      readerItemId: row.readerItemId,
      chapterId: row.chapterId,
      startOffset: row.startOffset,
      endOffset: row.endOffset,
      highlightText: await _decipherNullable(row.highlightText),
      note: await _decipherNullable(row.note),
      color: row.color,
      createdAt: row.createdAt,
    );
  }

  /// 用服务端标注替换本地临时标注，返回事务内读到的本地旧行。
  ///
  /// 判存与替换同处一个事务：分成两次读时，"事务外读到了" 与 "事务内已经不在" 可以
  /// 并存，调用方就会拿过期快照决定要不要补发服务端删除。返回 null 表示本地临时行
  /// 已经不在，此时不得把服务端刚创建的实体写回本地，调用方需补发一次服务端删除。
  Future<ReaderAnnotation?> replaceAnnotationId({
    required String localId,
    required ReaderAnnotation serverAnnotation,
  }) async {
    return _db.transaction(() async {
      final local = await loadAnnotationById(localId);
      if (local == null) {
        return null;
      }
      await deleteAnnotation(localId);
      await saveAnnotation(serverAnnotation);
      return local;
    });
  }

  Future<void> deleteAnnotationsForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderAnnotations)..where(
      (t) => t.readerItemId.equals(itemId) & _ownedByUser(t.userId),
    )).go();
  }

  // ─── Notes ───────────────────────────────────────────────────

  Future<void> saveNote(ReaderNote note) async {
    await _db
        .into(_db.cachedReaderNotes)
        .insertOnConflictUpdate(
          CachedReaderNotesCompanion.insert(
            id: note.id,
            userId: Value(_columnUserId ?? ''),
            readerItemId: note.readerItemId,
            charOffset: Value(note.charOffset),
            title: Value(note.title),
            content: await _encipher(note.content),
            createdAt: note.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<ReaderNote>> loadNotes(String itemId) async {
    final query =
        _db.select(_db.cachedReaderNotes)
          ..where((t) => t.readerItemId.equals(itemId) & _ownedByUser(t.userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    final rows = await query.get();
    final notes = <ReaderNote>[];
    for (final row in rows) {
      notes.add(
        ReaderNote(
          id: row.id,
          readerItemId: row.readerItemId,
          charOffset: row.charOffset,
          title: row.title,
          content: await _decipher(row.content),
          createdAt: row.createdAt,
        ),
      );
    }
    return notes;
  }

  Future<void> updateNote(
    String noteId, {
    String? title,
    required String content,
  }) async {
    await (_db.update(_db.cachedReaderNotes)
      ..where((t) => t.id.equals(noteId) & _ownedByUser(t.userId))).write(
      CachedReaderNotesCompanion(
        title: Value(title),
        content: Value(await _encipher(content)),
      ),
    );
  }

  Future<void> deleteNote(String noteId) async {
    await (_db.delete(_db.cachedReaderNotes)
      ..where((t) => t.id.equals(noteId) & _ownedByUser(t.userId))).go();
  }

  /// 按 ID 读取单条笔记；不存在或不属于当前账号时返回 null。
  Future<ReaderNote?> loadNoteById(String noteId) async {
    final row =
        await (_db.select(_db.cachedReaderNotes)..where(
          (t) => t.id.equals(noteId) & _ownedByUser(t.userId),
        )).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return ReaderNote(
      id: row.id,
      readerItemId: row.readerItemId,
      charOffset: row.charOffset,
      title: row.title,
      content: await _decipher(row.content),
      createdAt: row.createdAt,
    );
  }

  /// 用服务端笔记替换本地临时笔记，返回事务内读到的本地旧行。
  ///
  /// 判存与替换同处一个事务，语义与 [replaceAnnotationId] 一致：返回 null 表示本地
  /// 临时行已经不在，调用方需补发一次服务端删除。
  Future<ReaderNote?> replaceNoteId({
    required String localId,
    required ReaderNote serverNote,
  }) async {
    return _db.transaction(() async {
      final local = await loadNoteById(localId);
      if (local == null) {
        return null;
      }
      await deleteNote(localId);
      await saveNote(serverNote);
      return local;
    });
  }

  Future<void> deleteNotesForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderNotes)..where(
      (t) => t.readerItemId.equals(itemId) & _ownedByUser(t.userId),
    )).go();
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
            userId: Value(_columnUserId ?? ''),
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
      ..where((t) => t.itemId.equals(itemId) & _ownedByUser(t.userId));
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
      ..where((t) => t.itemId.equals(itemId) & _ownedByUser(t.userId))).go();
  }

  // ─── 章节内容缓存 ──────────────────────────────────────────

  Future<void> saveChapterContent({
    required String itemId,
    required String contentPath,
    required String title,
    required int chapterNumber,
    required int charCount,
    required String processedHtml,
    required List<String> stylesheetRefs,
  }) async {
    await _db
        .into(_db.cachedReaderChapters)
        .insertOnConflictUpdate(
          CachedReaderChaptersCompanion.insert(
            userId: Value(_columnUserId ?? ''),
            itemId: itemId,
            contentPath: contentPath,
            title: Value(title),
            chapterNumber: Value(chapterNumber),
            charCount: Value(charCount),
            processedHtml: await _encipher(processedHtml),
            stylesheetRefsJson: Value(
              await _encipher(jsonEncode(stylesheetRefs)),
            ),
            cachedAt: DateTime.now(),
          ),
        );
  }

  Future<({String html, List<String> refs})?> loadChapterContent({
    required String itemId,
    required String contentPath,
  }) async {
    final query = _db.select(_db.cachedReaderChapters)..where(
      (t) =>
          t.itemId.equals(itemId) &
          t.contentPath.equals(contentPath) &
          _ownedByUser(t.userId),
    );
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    return (
      html: await _decipher(row.processedHtml),
      refs: await _decipherStringList(row.stylesheetRefsJson),
    );
  }

  // ─── 书级样式表池 ──────────────────────────────────────────

  /// 写入这本书的样式表池（归档内路径 → CSS 文本）。
  ///
  /// 只更新那一列：整行覆盖会把元数据与章节清单一起写回，而池是在章节 ingest 时
  /// 补写的，那时手上的信息不足以重建整行。元数据行不存在时返回 false，由调用方
  /// 决定重试还是放弃（章节行只带次序引用，池缺失就意味着那些章没有书的排版）。
  Future<bool> saveStylesheetPool({
    required String itemId,
    required Map<String, String> pool,
  }) async {
    if (pool.isEmpty) return false;
    final changes = await (_db.update(_db.cachedReaderBooks)..where(
      (table) => table.itemId.equals(itemId) & _ownedByUser(table.userId),
    )).write(
      CachedReaderBooksCompanion(
        stylesheetPoolJson: Value(await _encipher(jsonEncode(pool))),
      ),
    );
    return changes > 0;
  }

  /// 读出这本书的样式表池；没有池或读坏时返回空表。
  ///
  /// 空池是合法状态：样式表缺失只降级到阅读器默认档，不能让一章打不开。读坏同样
  /// 按空表处理，但要留一行日志——它会让这本书静默失去原版排版。
  Future<Map<String, String>> loadStylesheetPool(String itemId) async {
    final row =
        await (_db.select(_db.cachedReaderBooks)..where(
          (table) => table.itemId.equals(itemId) & _ownedByUser(table.userId),
        )).getSingleOrNull();
    final stored = row?.stylesheetPoolJson;
    if (stored == null || stored.isEmpty || stored == '{}') {
      return const {};
    }
    try {
      final decoded = jsonDecode(await _decipher(stored));
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException catch (error) {
      readerDebugLog('ReaderStorage: 样式表池解析失败 itemId=$itemId: $error');
      return const {};
    }
  }

  Future<List<String>> _decipherStringList(String stored) async {
    if (stored.isEmpty || stored == '[]') return const [];
    try {
      final decoded = jsonDecode(await _decipher(stored));
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String) item,
      ];
    } on FormatException catch (error) {
      readerDebugLog('ReaderStorage: 章节样式表次序解析失败: $error');
      return const [];
    }
  }

  /// 删除指定书籍的所有章节缓存
  Future<void> deleteChaptersForItem(String itemId) async {
    await (_db.delete(_db.cachedReaderChapters)
      ..where((t) => t.itemId.equals(itemId) & _ownedByUser(t.userId))).go();
  }

  /// 删除单个章节的缓存内容，损坏章节精准清理时避免整本书失效。
  Future<void> deleteChapter(String itemId, String contentPath) async {
    await (_db.delete(_db.cachedReaderChapters)..where(
      (t) =>
          t.itemId.equals(itemId) &
          t.contentPath.equals(contentPath) &
          _ownedByUser(t.userId),
    )).go();
  }

  /// 清理超过指定天数的章节缓存
  Future<void> cleanOldChapters({int maxAgeDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
    await (_db.delete(_db.cachedReaderChapters)
      ..where((t) => t.cachedAt.isSmallerThanValue(cutoff))).go();
    await _dropOrphanStylesheetPools();
  }

  /// 章节行清完后把书级样式表池一起回收。
  ///
  /// 池只在章节 ingest 时写、只在"某章带着次序引用"时被读；章节行没了，它就是
  /// 没人再读的孤儿（一本最坏 256KB）。不回收的话，读过很多书之后缓存里会留下
  /// 一串永远用不到的样式表。
  Future<void> _dropOrphanStylesheetPools() async {
    final orphans =
        await _db
            .customSelect(
              'SELECT b.user_id AS user_id, b.item_id AS item_id '
              'FROM cached_reader_books b '
              'LEFT JOIN cached_reader_chapters c '
              'ON c.item_id = b.item_id AND c.user_id = b.user_id '
              "WHERE b.stylesheet_pool_json <> '{}' AND c.item_id IS NULL",
            )
            .get();
    for (final row in orphans) {
      await (_db.update(_db.cachedReaderBooks)..where(
        (table) =>
            table.itemId.equals(row.read<String>('item_id')) &
            table.userId.equals(row.read<String>('user_id')),
      )).write(
        const CachedReaderBooksCompanion(stylesheetPoolJson: Value('{}')),
      );
    }
  }

  // ─── Bulk cleanup ────────────────────────────────────────────

  /// 删除指定条目的结构化本地数据。
  Future<void> deleteAllForItem(String itemId) async {
    await deleteProgress(itemId);
    await deleteBookmarksForItem(itemId);
    await deleteAnnotationsForItem(itemId);
    await deleteNotesForItem(itemId);
    await deleteChaptersForItem(itemId);
    // 元数据行带着书级样式表池：漏删它就是留着一条没人再读的加密正文缓存。
    await deleteBookMeta(itemId);
  }
}
