import 'dart:math';

import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/domain/reader_note.dart';

/// 阅读器数据管理器 — 离线优先写入模式
///
/// 业内主流方案（Kindle、Apple Books、微信读书）：
/// 所有写操作先存本地，再异步同步服务端。
/// 网络失败不阻塞，同步队列在网络恢复时自动重试。
class ReaderDataManager {
  ReaderDataManager({
    required ReaderApi api,
    required ReaderLocalStorage localStorage,
  }) : _api = api,
       _localStorage = localStorage;

  final ReaderApi _api;
  final ReaderLocalStorage _localStorage;
  static final Random _localIdRandom = Random();

  // ── 书签 ──

  /// 创建书签（本地优先 + 服务端同步）
  Future<ReaderBookmark> createBookmark({
    required String itemId,
    required int charOffset,
    required double progressPercent,
    String? chapterId,
    String? note,
  }) async {
    final now = DateTime.now();
    final id = _newLocalId();

    final bookmark = ReaderBookmark(
      id: id,
      readerItemId: itemId,
      chapterId: chapterId,
      charOffset: charOffset,
      progressPercent: progressPercent,
      note: note,
      createdAt: now,
    );

    // 1. 本地写入
    await _localStorage.saveBookmark(bookmark);

    // 2. 入队同步
    await ReaderSyncQueue.enqueueBookmarkCreate(
      localId: id,
      itemId: itemId,
      chapterId: chapterId,
      charOffset: charOffset,
      progressPercent: progressPercent,
      note: note,
    );

    return bookmark;
  }

  /// 删除书签（本地优先 + 服务端同步）
  Future<void> deleteBookmark(String bookmarkId) async {
    // 1. 本地删除
    await _localStorage.deleteBookmark(bookmarkId);

    // 2. 入队同步（如果不是本地临时 ID）
    if (bookmarkId.startsWith('local_')) {
      await ReaderSyncQueue.cancelPendingBookmarkCreate(localId: bookmarkId);
    } else {
      await ReaderSyncQueue.enqueueBookmarkDelete(bookmarkId: bookmarkId);
    }
  }

  /// 加载书签列表（远端拉取 + 离线待同步项合并）
  Future<List<ReaderBookmark>> loadBookmarks(String itemId) async {
    Future<List<ReaderBookmark>> loadLocal() =>
        _localStorage.loadBookmarks(itemId);
    try {
      return await _mergeWithPendingMutations<ReaderBookmark>(
        loadLocal: loadLocal,
        fetchRemote: () => _api.bookmarks(itemId),
        deleteType: ReaderSyncQueue.opBookmarkDelete,
        idField: 'bookmarkId',
        idOf: (bookmark) => bookmark.id,
        saveRemote: (bookmark) => _localStorage.saveBookmark(bookmark),
        deleteLocal: (bookmarkId) => _localStorage.deleteBookmark(bookmarkId),
      );
    } on Exception {
      return loadLocal();
    }
  }

  // ── 标注 ──

  /// 创建标注（本地优先 + 服务端同步）
  Future<ReaderAnnotation> createAnnotation({
    required String itemId,
    String? chapterId,
    required int startOffset,
    required int endOffset,
    String? highlightText,
    String? note,
    String? color,
  }) async {
    final now = DateTime.now();
    final id = _newLocalId();

    final annotation = ReaderAnnotation(
      id: id,
      readerItemId: itemId,
      chapterId: chapterId,
      startOffset: startOffset,
      endOffset: endOffset,
      highlightText: highlightText,
      note: note,
      color: color ?? '#FFEB3B',
      createdAt: now,
    );

    // 1. 本地写入
    await _localStorage.saveAnnotation(annotation);

    // 2. 入队同步
    await ReaderSyncQueue.enqueueAnnotationCreate(
      localId: id,
      itemId: itemId,
      chapterId: chapterId,
      startOffset: startOffset,
      endOffset: endOffset,
      highlightText: highlightText,
      note: note,
      color: color,
    );

    return annotation;
  }

  /// 更新标注（本地优先 + 服务端同步）
  Future<void> updateAnnotation({
    required String annotationId,
    String? note,
    String? color,
  }) async {
    // 1. 本地更新
    await _localStorage.updateAnnotation(
      annotationId,
      note: note,
      color: color,
    );

    // 2. 入队同步
    if (annotationId.startsWith('local_')) {
      await ReaderSyncQueue.updatePendingAnnotationCreate(
        localId: annotationId,
        note: note,
        color: color,
      );
    } else {
      await ReaderSyncQueue.enqueueAnnotationUpdate(
        annotationId: annotationId,
        note: note,
        color: color,
      );
    }
  }

  /// 删除标注（本地优先 + 服务端同步）
  Future<void> deleteAnnotation(String annotationId) async {
    await _localStorage.deleteAnnotation(annotationId);

    if (annotationId.startsWith('local_')) {
      await ReaderSyncQueue.cancelPendingAnnotationCreate(
        localId: annotationId,
      );
    } else {
      await ReaderSyncQueue.enqueueAnnotationDelete(annotationId: annotationId);
    }
  }

  /// 加载标注列表（远端拉取 + 离线待同步项合并）
  Future<List<ReaderAnnotation>> loadAnnotations(String itemId) async {
    Future<List<ReaderAnnotation>> loadLocal() =>
        _localStorage.loadAnnotations(itemId);
    try {
      return await _mergeWithPendingMutations<ReaderAnnotation>(
        loadLocal: loadLocal,
        fetchRemote: () => _api.annotations(itemId),
        updateType: ReaderSyncQueue.opAnnotationUpdate,
        deleteType: ReaderSyncQueue.opAnnotationDelete,
        idField: 'annotationId',
        idOf: (annotation) => annotation.id,
        saveRemote: (annotation) => _localStorage.saveAnnotation(annotation),
        deleteLocal:
            (annotationId) => _localStorage.deleteAnnotation(annotationId),
      );
    } on Exception {
      return loadLocal();
    }
  }

  // ── 笔记 ──

  /// 创建笔记（本地优先 + 服务端同步）
  Future<ReaderNote> createNote({
    required String itemId,
    int? charOffset,
    String? title,
    required String content,
  }) async {
    final now = DateTime.now();
    final id = _newLocalId();

    final note = ReaderNote(
      id: id,
      readerItemId: itemId,
      charOffset: charOffset,
      title: title,
      content: content,
      createdAt: now,
    );

    await _localStorage.saveNote(note);

    await ReaderSyncQueue.enqueueNoteCreate(
      localId: id,
      itemId: itemId,
      charOffset: charOffset,
      title: title,
      content: content,
    );

    return note;
  }

  /// 更新笔记
  Future<void> updateNote({
    required String noteId,
    String? title,
    required String content,
  }) async {
    await _localStorage.updateNote(noteId, title: title, content: content);

    if (noteId.startsWith('local_')) {
      await ReaderSyncQueue.updatePendingNoteCreate(
        localId: noteId,
        title: title,
        content: content,
      );
    } else {
      await ReaderSyncQueue.enqueueNoteUpdate(
        noteId: noteId,
        title: title,
        content: content,
      );
    }
  }

  /// 删除笔记
  Future<void> deleteNote(String noteId) async {
    await _localStorage.deleteNote(noteId);

    if (noteId.startsWith('local_')) {
      await ReaderSyncQueue.cancelPendingNoteCreate(localId: noteId);
    } else {
      await ReaderSyncQueue.enqueueNoteDelete(noteId: noteId);
    }
  }

  /// 加载笔记列表（远端拉取 + 离线待同步项合并）
  Future<List<ReaderNote>> loadNotes(String itemId) async {
    Future<List<ReaderNote>> loadLocal() => _localStorage.loadNotes(itemId);
    try {
      return await _mergeWithPendingMutations<ReaderNote>(
        loadLocal: loadLocal,
        fetchRemote: () => _api.notes(itemId),
        updateType: ReaderSyncQueue.opNoteUpdate,
        deleteType: ReaderSyncQueue.opNoteDelete,
        idField: 'noteId',
        idOf: (note) => note.id,
        saveRemote: (note) => _localStorage.saveNote(note),
        deleteLocal: (noteId) => _localStorage.deleteNote(noteId),
      );
    } on Exception {
      return loadLocal();
    }
  }

  /// 先重放队列、再拉取、按待同步队列过滤合并。
  ///
  /// 顺序不能倒：离线积压的删改先推给服务端，远端快照才可能已经是最新事实，
  /// 否则远端返回的还是旧内容。仍未同步成功的操作必须继续生效——待删 ID 在
  /// 远端快照里仍然存在，直接覆写本地就是墓碑复活；待改 ID 会被旧内容回滚。
  ///
  /// `retryFailed` 不能省：断网期间试过一次 flush 会把操作留在 `failed`，
  /// 而 `_doFlush` 只捞 `pending`；不先唤醒，本机的删除会永远停在失败态。
  Future<List<T>> _mergeWithPendingMutations<T>({
    required Future<List<T>> Function() loadLocal,
    required Future<List<T>> Function() fetchRemote,
    required String deleteType,
    required String idField,
    required String Function(T item) idOf,
    required Future<void> Function(T item) saveRemote,
    required Future<void> Function(String id) deleteLocal,
    String? updateType,
  }) async {
    await ReaderSyncQueue.retryFailed();
    await ReaderSyncQueue.flush(api: _api);
    final mutations = await ReaderSyncQueue.pendingMutations(
      updateType: updateType,
      deleteType: deleteType,
      idField: idField,
    );
    // 本地列表在 flush 之后读取：在途创建成功回包会把临时 ID 换成服务端 ID，
    // flush 之前读到的那份临时行已经不存在了。
    final local = await loadLocal();
    final remote = await fetchRemote();
    final remoteIds = remote.map(idOf).toSet();
    final localById = {for (final item in local) idOf(item): item};
    final merged = <T>[];
    for (final item in remote) {
      final id = idOf(item);
      if (mutations.deletingIds.contains(id)) {
        await deleteLocal(id);
        continue;
      }
      if (mutations.updatingPayloads.containsKey(id)) {
        merged.add(localById[id] ?? item);
        continue;
      }
      await saveRemote(item);
      merged.add(item);
    }
    for (final item in local) {
      final id = idOf(item);
      if (id.startsWith('local_')) {
        // 创建还排在队列里：本地行是它唯一的副本，远端自然没有它。
        if (!remoteIds.contains(id)) {
          merged.add(item);
        }
        continue;
      }
      if (!remoteIds.contains(id)) {
        await deleteLocal(id);
      }
    }
    return merged;
  }

  /// 生成本地临时 ID，作为离线创建的幂等操作号。
  String _newLocalId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = _localIdRandom.nextInt(0x3fffffff).toRadixString(16);
    return 'local_${timestamp}_${random.padLeft(8, '0')}';
  }

  // ── 同步 ──
}
