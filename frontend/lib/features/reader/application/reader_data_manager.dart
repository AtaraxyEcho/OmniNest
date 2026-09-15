import 'dart:math';

import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/domain/reader_note.dart';
import 'package:omninest/features/reader/domain/reader_progress.dart';

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

  // ── 进度 ──

  /// 保存阅读进度（本地优先 + 服务端同步）
  Future<void> saveProgress({
    required String itemId,
    required int charOffset,
    required double progressPercent,
    required String readingMode,
  }) async {
    final now = DateTime.now();
    final progress = ReaderProgress(
      readerItemId: itemId,
      charOffset: charOffset,
      progressPercent: progressPercent,
      readingMode: readingMode,
      updatedAt: now,
    );

    // 1. 本地写入（始终成功）
    await _localStorage.saveProgress(progress);

    // 2. 入队同步（异步，不阻塞）
    await ReaderSyncQueue.enqueueProgress(
      itemId: itemId,
      charOffset: charOffset,
      progressPercent: progressPercent,
      readingMode: readingMode,
    );
  }

  /// 加载阅读进度（本地优先，服务端对比取最新）
  Future<ReaderProgress?> loadProgress(String itemId) async {
    return _localStorage.loadProgress(itemId);
  }

  // ── 书签 ──

  /// 创建书签（本地优先 + 服务端同步）
  Future<ReaderBookmark> createBookmark({
    required String itemId,
    required int charOffset,
    required double progressPercent,
    String? note,
  }) async {
    final now = DateTime.now();
    final id = _newLocalId();

    final bookmark = ReaderBookmark(
      id: id,
      readerItemId: itemId,
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

  /// 加载书签列表
  Future<List<ReaderBookmark>> loadBookmarks(String itemId) async {
    return _localStorage.loadBookmarks(itemId);
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

  /// 加载标注列表
  Future<List<ReaderAnnotation>> loadAnnotations(String itemId) async {
    final local = await _localStorage.loadAnnotations(itemId);
    try {
      final remote = await _api.annotations(itemId);
      final remoteIds = remote.map((annotation) => annotation.id).toSet();
      for (final annotation in remote) {
        await _localStorage.saveAnnotation(annotation);
      }
      for (final annotation in local) {
        if (!annotation.id.startsWith('local_') &&
            !remoteIds.contains(annotation.id)) {
          await _localStorage.deleteAnnotation(annotation.id);
        }
      }
      return [
        ...remote,
        ...local.where(
          (annotation) =>
              annotation.id.startsWith('local_') &&
              !remoteIds.contains(annotation.id),
        ),
      ];
    } on Exception {
      return local;
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

  /// 加载笔记列表
  Future<List<ReaderNote>> loadNotes(String itemId) async {
    final local = await _localStorage.loadNotes(itemId);
    try {
      final remote = await _api.notes(itemId);
      final remoteIds = remote.map((note) => note.id).toSet();
      for (final note in remote) {
        await _localStorage.saveNote(note);
      }
      for (final note in local) {
        if (!note.id.startsWith('local_') && !remoteIds.contains(note.id)) {
          await _localStorage.deleteNote(note.id);
        }
      }
      return [
        ...remote,
        ...local.where(
          (note) =>
              note.id.startsWith('local_') && !remoteIds.contains(note.id),
        ),
      ];
    } on Exception {
      return local;
    }
  }

  /// 生成本地临时 ID，作为离线创建的幂等操作号。
  String _newLocalId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = _localIdRandom.nextInt(0x3fffffff).toRadixString(16);
    return 'local_${timestamp}_${random.padLeft(8, '0')}';
  }

  // ── 同步 ──
}
