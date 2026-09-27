import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 阅读器离线同步队列
///
/// 统一处理进度、书签、标注、笔记的离线写入和在线同步。
/// 业内主流方案（Kindle、Apple Books、微信读书）：
/// 所有用户数据写入本地优先，异步同步服务端，失败不阻塞。
class ReaderSyncQueue {
  static LocalDatabase? _db;
  static bool _syncing = false;

  /// 操作类型常量
  static const opProgress = 'reader.progress';
  static const opBookmarkCreate = 'reader.bookmark.create';
  static const opBookmarkDelete = 'reader.bookmark.delete';
  static const opAnnotationCreate = 'reader.annotation.create';
  static const opAnnotationUpdate = 'reader.annotation.update';
  static const opAnnotationDelete = 'reader.annotation.delete';
  static const opNoteCreate = 'reader.note.create';
  static const opNoteUpdate = 'reader.note.update';
  static const opNoteDelete = 'reader.note.delete';
  static const opSessionCreate = 'reader.session.create';
  static const _readerOperationTypes = [
    opProgress,
    opBookmarkCreate,
    opBookmarkDelete,
    opAnnotationCreate,
    opAnnotationUpdate,
    opAnnotationDelete,
    opNoteCreate,
    opNoteUpdate,
    opNoteDelete,
    opSessionCreate,
  ];

  /// 初始化同步队列（必须在使用前调用）。
  static void init(LocalDatabase database) {
    _db = database;
  }

  static LocalDatabase get _database {
    final database = _db;
    if (database != null) return database;
    throw StateError(
      'ReaderSyncQueue not initialized. '
      'Call ReaderSyncQueue.init(database) first.',
    );
  }

  // ── 入队操作 ──

  /// 入队进度同步
  static Future<void> enqueueProgress({
    required String itemId,
    required int charOffset,
    required double progressPercent,
    required String readingMode,
    String? chapterId,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
  }) async {
    await _enqueue(opProgress, {
      'itemId': itemId,
      'charOffset': charOffset,
      'progressPercent': progressPercent,
      'readingMode': readingMode,
      if (chapterId != null) 'chapterId': chapterId,
      if (pageId != null) 'pageId': pageId,
      if (pageIndex != null) 'pageIndex': pageIndex,
      if (pageFingerprint != null) 'pageFingerprint': pageFingerprint,
      if (sourceId != null) 'sourceId': sourceId,
      if (sourcePageIndex != null) 'sourcePageIndex': sourcePageIndex,
      if (catalogKey != null) 'catalogKey': catalogKey,
      if (manifestVersion != null) 'manifestVersion': manifestVersion,
      if (intraPageOffset != null) 'intraPageOffset': intraPageOffset,
    });
  }

  /// 入队创建书签
  static Future<void> enqueueBookmarkCreate({
    required String localId,
    required String itemId,
    required int charOffset,
    required double progressPercent,
    String? note,
  }) async {
    await _enqueue(opBookmarkCreate, {
      'localId': localId,
      'itemId': itemId,
      'charOffset': charOffset,
      'progressPercent': progressPercent,
      'note': note,
    });
  }

  /// 入队删除书签
  static Future<void> enqueueBookmarkDelete({
    required String bookmarkId,
  }) async {
    await _enqueue(opBookmarkDelete, {'bookmarkId': bookmarkId});
  }

  /// 入队创建标注
  static Future<void> enqueueAnnotationCreate({
    required String localId,
    required String itemId,
    String? chapterId,
    required int startOffset,
    required int endOffset,
    String? highlightText,
    String? note,
    String? color,
  }) async {
    await _enqueue(opAnnotationCreate, {
      'localId': localId,
      'itemId': itemId,
      'chapterId': chapterId,
      'startOffset': startOffset,
      'endOffset': endOffset,
      'highlightText': highlightText,
      'note': note,
      'color': color ?? '#FFEB3B',
    });
  }

  /// 入队更新标注
  static Future<void> enqueueAnnotationUpdate({
    required String annotationId,
    String? note,
    String? color,
  }) async {
    await _enqueue(opAnnotationUpdate, {
      'annotationId': annotationId,
      'note': note,
      'color': color,
    });
  }

  /// 入队删除标注
  static Future<void> enqueueAnnotationDelete({
    required String annotationId,
  }) async {
    await _enqueue(opAnnotationDelete, {'annotationId': annotationId});
  }

  /// 入队创建笔记
  static Future<void> enqueueNoteCreate({
    required String localId,
    required String itemId,
    int? charOffset,
    String? title,
    required String content,
  }) async {
    await _enqueue(opNoteCreate, {
      'localId': localId,
      'itemId': itemId,
      'charOffset': charOffset,
      'title': title,
      'content': content,
    });
  }

  /// 入队更新笔记
  static Future<void> enqueueNoteUpdate({
    required String noteId,
    String? title,
    required String content,
  }) async {
    await _enqueue(opNoteUpdate, {
      'noteId': noteId,
      'title': title,
      'content': content,
    });
  }

  /// 入队删除笔记
  static Future<void> enqueueNoteDelete({required String noteId}) async {
    await _enqueue(opNoteDelete, {'noteId': noteId});
  }

  /// 取消尚未同步的本地书签创建操作。
  static Future<void> cancelPendingBookmarkCreate({required String localId}) {
    return _deletePendingCreateOperation(
      type: opBookmarkCreate,
      localId: localId,
    );
  }

  /// 取消尚未同步的本地标注创建操作。
  static Future<void> cancelPendingAnnotationCreate({required String localId}) {
    return _deletePendingCreateOperation(
      type: opAnnotationCreate,
      localId: localId,
    );
  }

  /// 取消尚未同步的本地笔记创建操作。
  static Future<void> cancelPendingNoteCreate({required String localId}) {
    return _deletePendingCreateOperation(type: opNoteCreate, localId: localId);
  }

  /// 更新尚未同步的本地标注创建载荷。
  static Future<void> updatePendingAnnotationCreate({
    required String localId,
    String? note,
    String? color,
  }) async {
    await _updatePendingCreatePayload(
      type: opAnnotationCreate,
      localId: localId,
      update: (payload) {
        payload['note'] = note;
        if (color != null) {
          payload['color'] = color;
        }
      },
    );
  }

  /// 更新尚未同步的本地笔记创建载荷。
  static Future<void> updatePendingNoteCreate({
    required String localId,
    String? title,
    required String content,
  }) async {
    await _updatePendingCreatePayload(
      type: opNoteCreate,
      localId: localId,
      update: (payload) {
        payload['title'] = title;
        payload['content'] = content;
      },
    );
  }

  /// 入队阅读会话
  static Future<void> enqueueSessionCreate({
    required String clientSessionId,
    required String itemId,
    required String startedAt,
    required String endedAt,
    required int durationSeconds,
  }) async {
    await _enqueue(opSessionCreate, {
      'clientSessionId': clientSessionId,
      'itemId': itemId,
      'startedAt': startedAt,
      'endedAt': endedAt,
      'durationSeconds': durationSeconds,
    });
  }

  /// 通用入队
  static Future<void> _enqueue(String type, Map<String, dynamic> data) async {
    await _database
        .into(_database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: type,
            payload: jsonEncode(data),
            createdAt: DateTime.now(),
          ),
        );
  }

  static Future<void> _deletePendingCreateOperation({
    required String type,
    required String localId,
  }) async {
    final operations = await _pendingCreateOperations(type);
    for (final operation in operations) {
      final payload = _decodePayload(operation);
      if (payload?['localId'] != localId) {
        continue;
      }
      await (_database.delete(_database.syncOperations)
        ..where((table) => table.id.equals(operation.id))).go();
    }
  }

  static Future<void> _updatePendingCreatePayload({
    required String type,
    required String localId,
    required void Function(Map<String, dynamic> payload) update,
  }) async {
    final operations = await _pendingCreateOperations(type);
    for (final operation in operations) {
      final payload = _decodePayload(operation);
      if (payload == null || payload['localId'] != localId) {
        continue;
      }
      update(payload);
      await (_database.update(_database.syncOperations)..where(
        (table) => table.id.equals(operation.id),
      )).write(SyncOperationsCompanion(payload: Value(jsonEncode(payload))));
    }
  }

  static Future<List<SyncOperation>> _pendingCreateOperations(String type) {
    return (_database.select(_database.syncOperations)..where(
      (table) =>
          table.type.equals(type) &
          table.status.isIn(const ['pending', 'failed']),
    )).get();
  }

  static Map<String, dynamic>? _decodePayload(SyncOperation operation) {
    try {
      return jsonDecode(operation.payload) as Map<String, dynamic>;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  // ── 刷新队列 ──

  /// 批量发送队列中的待同步操作。
  ///
  /// 网络请求超时由 Dio 层负责，避免底层请求仍在执行时提前释放同步锁。
  static Future<void> flush({ReaderApi? api}) async {
    if (_syncing || api == null) return;
    _syncing = true;

    try {
      await _doFlush(api);
    } finally {
      _syncing = false;
    }
  }

  /// 执行实际的队列刷新逻辑。
  static Future<void> _doFlush(ReaderApi api) async {
    final pending =
        await (_database.select(_database.syncOperations)
              ..where(
                (table) =>
                    table.status.equals('pending') &
                    table.type.isIn(_readerOperationTypes),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.createdAt)])
              ..limit(50))
            .get();

    for (final op in pending) {
      try {
        await _dispatch(api, op);
        await _markCompleted(op.id);
      } on AppException catch (error) {
        if (error.code == AppErrorCodes.forbidden) {
          // 无 activity:write 的角色：书签/标注/笔记保留本地（本地优先
          // 模型，本地即真值），跳过远端同步，不做无意义重试。
          await _markCompleted(op.id);
        } else {
          await _markFailed(op);
        }
      } on FormatException {
        await _markFailed(op);
      } on TypeError {
        await _markFailed(op);
      } on Exception {
        await _markFailed(op);
      }
    }
  }

  /// 根据操作类型分发到对应的 API 调用。
  static Future<void> _dispatch(ReaderApi api, SyncOperation op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;

    switch (op.type) {
      case opProgress:
        await api.updateProgress(
          itemId: payload['itemId'] as String,
          charOffset: payload['charOffset'] as int,
          progressPercent: (payload['progressPercent'] as num).toDouble(),
          readingMode: payload['readingMode'] as String? ?? 'scroll',
          chapterId: payload['chapterId'] as String?,
          pageId: payload['pageId'] as String?,
          pageIndex: payload['pageIndex'] as int?,
          pageFingerprint: payload['pageFingerprint'] as String?,
          sourceId: payload['sourceId'] as String?,
          sourcePageIndex: payload['sourcePageIndex'] as int?,
          catalogKey: payload['catalogKey'] as String?,
          manifestVersion: payload['manifestVersion'] as int?,
          intraPageOffset: (payload['intraPageOffset'] as num?)?.toDouble(),
        );

      case opBookmarkCreate:
        final bookmark = await api.createBookmark(
          itemId: payload['itemId'] as String,
          charOffset: payload['charOffset'] as int,
          progressPercent: (payload['progressPercent'] as num).toDouble(),
          note: payload['note'] as String?,
          clientOperationId: payload['localId'] as String?,
        );
        await _replaceBookmark(payload['localId'] as String?, bookmark);

      case opBookmarkDelete:
        await api.deleteBookmark(payload['bookmarkId'] as String);

      case opAnnotationCreate:
        final annotation = await api.createAnnotation(
          itemId: payload['itemId'] as String,
          chapterId: payload['chapterId'] as String?,
          startOffset: payload['startOffset'] as int,
          endOffset: payload['endOffset'] as int,
          highlightText: payload['highlightText'] as String?,
          note: payload['note'] as String?,
          color: payload['color'] as String? ?? '#FFEB3B',
          clientOperationId: payload['localId'] as String?,
        );
        await _replaceAnnotation(payload['localId'] as String?, annotation);

      case opAnnotationUpdate:
        await api.updateAnnotation(
          payload['annotationId'] as String,
          note: payload['note'] as String?,
          color: payload['color'] as String?,
        );

      case opAnnotationDelete:
        await api.deleteAnnotation(payload['annotationId'] as String);

      case opNoteCreate:
        final note = await api.createNote(
          itemId: payload['itemId'] as String,
          charOffset: payload['charOffset'] as int?,
          title: payload['title'] as String?,
          content: payload['content'] as String,
          clientOperationId: payload['localId'] as String?,
        );
        await _replaceNote(payload['localId'] as String?, note);

      case opNoteUpdate:
        await api.updateNote(
          payload['noteId'] as String,
          title: payload['title'] as String?,
          content: payload['content'] as String,
        );

      case opNoteDelete:
        await api.deleteNote(payload['noteId'] as String);

      case opSessionCreate:
        await api.recordSession(
          clientSessionId: payload['clientSessionId'] as String,
          itemId: payload['itemId'] as String,
          startedAt: payload['startedAt'] as String,
          endedAt: payload['endedAt'] as String,
          durationSeconds: payload['durationSeconds'] as int,
        );

      default:
        // 未知操作类型，标记完成避免阻塞队列
        break;
    }
  }

  /// 将可重试失败项重新放回待同步状态。
  static Future<void> retryFailed({int maxRetries = 3}) {
    return (_database.update(_database.syncOperations)..where(
      (table) =>
          table.status.equals('failed') &
          table.type.isIn(_readerOperationTypes) &
          table.retryCount.isSmallerThanValue(maxRetries),
    )).write(SyncOperationsCompanion(status: const Value('pending')));
  }

  /// 队列中待处理的同步项数量。
  static Future<int> pendingCount() async {
    final count = _database.syncOperations.id.count();
    final query =
        _database.selectOnly(_database.syncOperations)
          ..addColumns([count])
          ..where(
            _database.syncOperations.status.equals('pending') &
                _database.syncOperations.type.isIn(_readerOperationTypes),
          );
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  static Future<void> _replaceBookmark(
    String? localId,
    ReaderBookmark bookmark,
  ) async {
    if (localId == null || localId.isEmpty || localId == bookmark.id) {
      return;
    }
    await ReaderLocalStorage(
      _database,
    ).replaceBookmarkId(localId: localId, serverBookmark: bookmark);
  }

  static Future<void> _replaceAnnotation(
    String? localId,
    ReaderAnnotation annotation,
  ) async {
    if (localId == null || localId.isEmpty || localId == annotation.id) {
      return;
    }
    await ReaderLocalStorage(
      _database,
    ).replaceAnnotationId(localId: localId, serverAnnotation: annotation);
  }

  static Future<void> _replaceNote(String? localId, ReaderNote note) async {
    if (localId == null || localId.isEmpty || localId == note.id) {
      return;
    }
    await ReaderLocalStorage(
      _database,
    ).replaceNoteId(localId: localId, serverNote: note);
  }

  static Future<void> _markCompleted(int id) {
    return (_database.update(_database.syncOperations)
      ..where((table) => table.id.equals(id))).write(
      SyncOperationsCompanion(
        status: const Value('completed'),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  static Future<void> _markFailed(SyncOperation operation) {
    return (_database.update(_database.syncOperations)
      ..where((table) => table.id.equals(operation.id))).write(
      SyncOperationsCompanion(
        status: const Value('failed'),
        retryCount: Value(operation.retryCount + 1),
      ),
    );
  }

  static void dispose() {}
}
