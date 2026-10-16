import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';
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
  static OfflineTextCipher? _textCipher;
  static String? _userId;

  /// 操作重试上限，超过后进度行按过期数据清理。
  static const int maxOperationRetries = 3;

  /// 单批重放的 reader 操作数上限。
  static const int maxOperationBatch = 50;

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

  static const _deleteOperationTypes = [
    opBookmarkDelete,
    opAnnotationDelete,
    opNoteDelete,
  ];

  /// "服务端已经没有这条记录"的业务错误名（后端 `ErrorCode` 枚举名）。
  ///
  /// 书签/批注/笔记的删除入口都以 `MEDIA_NOT_FOUND` 报缺失，`NOT_FOUND` 与
  /// `BOOK_NOT_FOUND` 是条目本身已不在时的返回；三者对删除来说都是目标状态已达成。
  static const _alreadyGoneErrorNames = {
    'NOT_FOUND',
    'MEDIA_NOT_FOUND',
    'BOOK_NOT_FOUND',
  };

  /// 初始化同步队列（必须在使用前调用）。
  ///
  /// [textCipher]/[userId] 用于回写替换路径的敏感列加密，与
  /// ReaderLocalStorage 主实例保持一致；为空时按明文写入（Web 平台）。
  static void init(
    LocalDatabase database, {
    OfflineTextCipher? textCipher,
    String? userId,
  }) {
    _db = database;
    _textCipher = textCipher;
    _userId = userId;
  }

  static LocalDatabase get _database {
    final database = _db;
    if (database != null) return database;
    throw StateError(
      'ReaderSyncQueue not initialized. '
      'Call ReaderSyncQueue.init(database) first.',
    );
  }

  /// 队列行的账号归属：共享书籍在不同账号下复用同一个 itemId，重放必须只发
  /// 当前账号积压的操作，否则换号后会把上一个账号的位置与笔记写到新账号名下。
  /// 未登录（init 未传 userId）时不隔离，保持设备内单一使用者的读法。
  static bool get _hasOwner {
    final userId = _userId;
    return userId != null && userId.isNotEmpty;
  }

  static Expression<bool> _ownedByCurrentUser(GeneratedColumn<String> column) {
    if (!_hasOwner) {
      return Constant(true);
    }
    return column.equals(_userId!);
  }

  static Future<void> _deleteOwnedOperations(Iterable<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await (_database.delete(_database.syncOperations)
      ..where((table) => table.id.isIn(ids))).go();
  }

  // ── 入队操作 ──

  /// 入队进度同步
  ///
  /// 同一本书只保留最新一条待同步进度：合并判据是**记录时刻**，不是入队顺序。
  /// 慢请求超时后才失败的那一条记录时刻更早，按入队顺序合并会让它删掉队列里
  /// 更新的一行，新位置从此永不补传；服务端围栏救不到这一步，因为它发生在发网之前。
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
    DateTime? clientUpdatedAt,
  }) async {
    final hasNewerRow = await _supersedePendingProgress(
      itemId,
      reportedAt: clientUpdatedAt,
    );
    if (hasNewerRow) {
      return;
    }
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
      if (clientUpdatedAt != null)
        'clientUpdatedAt': clientUpdatedAt.toUtc().toIso8601String(),
    });
  }

  /// 入队创建书签
  static Future<void> enqueueBookmarkCreate({
    required String localId,
    required String itemId,
    required int charOffset,
    required double progressPercent,
    String? chapterId,
    String? note,
  }) async {
    await _enqueue(opBookmarkCreate, {
      'localId': localId,
      'itemId': itemId,
      'chapterId': chapterId,
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
            userId: Value(_userId ?? ''),
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
          table.status.isIn(const ['pending', 'failed']) &
          _ownedByCurrentUser(table.userId),
    )).get();
  }

  /// 按类型取出待重放的 reader 操作，按入队时间升序。
  static Future<List<SyncOperation>> _pendingReaderOps({
    required List<String> types,
    int? limit,
  }) async {
    final query =
        (_database.select(_database.syncOperations)
          ..where(
            (table) =>
                table.status.equals('pending') &
                table.type.isIn(types) &
                _ownedByCurrentUser(table.userId),
          )
          ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]));
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  /// 清除同书（以及载荷已损坏）的未同步进度行。
  /// 删除同书里记录时刻不晚于本次的待传/失败进度行。
  ///
  /// 返回 true 表示队列里存在记录时刻更晚的一行，本次入队应当作废。
  /// 缺记录时刻的行按最旧处理；本次也没有时刻时退化为原样合并（无从比较）。
  static Future<bool> _supersedePendingProgress(
    String itemId, {
    DateTime? reportedAt,
  }) async {
    final operations =
        await (_database.select(_database.syncOperations)..where(
          (table) =>
              table.type.equals(opProgress) &
              table.status.isIn(const ['pending', 'failed']) &
              _ownedByCurrentUser(table.userId),
        )).get();
    final staleIds = <int>[];
    var hasNewerRow = false;
    for (final operation in operations) {
      final payload = _decodePayload(operation);
      if (payload == null) {
        staleIds.add(operation.id);
        continue;
      }
      if (payload['itemId'] != itemId) {
        continue;
      }
      final storedAt = DateTime.tryParse(
        payload['clientUpdatedAt'] as String? ?? '',
      );
      if (storedAt == null) {
        staleIds.add(operation.id);
        continue;
      }
      // 本次没有记录时刻时无从比较：队列里带时刻的行更可能是别处刚记的位置，
      // 删掉它就是把已知进度丢掉。在线直传成功后的清理同理，那条进度已经
      // 落库，不需要靠删队列行来合并。
      if (reportedAt == null || storedAt.isAfter(reportedAt)) {
        hasNewerRow = true;
        continue;
      }
      staleIds.add(operation.id);
    }
    await _deleteOwnedOperations(staleIds);
    return hasNewerRow;
  }

  /// 在线直传成功后清理同书已不需要的离线进度行。
  ///
  /// 直传绕过了队列，队列里同书的旧进度必须一并作废，否则下一轮 flush 会把
  /// 更旧的位置再发一次；带更新记录时刻的行由围栏拒绝，这里同样不删。
  static Future<void> clearSupersededProgress(
    String itemId, {
    DateTime? reportedAt,
  }) async {
    await _supersedePendingProgress(itemId, reportedAt: reportedAt);
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

  // ── 待同步删改查询 ──

  /// 队列中尚未同步成功的删改目标，供远端拉取合并时兜底。
  ///
  /// 离线期间删掉的记录会随远端快照回来，离线改过的内容会被旧值覆盖，
  /// 合并前必须先读这里：待删 ID 直接过滤掉，待改 ID 保留本地字段。
  static Future<ReaderPendingMutations> pendingMutations({
    String? updateType,
    required String deleteType,
    required String idField,
  }) async {
    final types = <String>[if (updateType != null) updateType, deleteType];
    final operations =
        await (_database.select(_database.syncOperations)..where(
          (table) =>
              table.type.isIn(types) &
              table.status.isIn(const ['pending', 'failed']) &
              _ownedByCurrentUser(table.userId),
        )).get();
    final deletingIds = <String>{};
    final updatingPayloads = <String, Map<String, dynamic>>{};
    for (final operation in operations) {
      final payload = _decodePayload(operation);
      final targetId = payload?[idField] as String?;
      if (targetId == null) {
        continue;
      }
      if (operation.type == deleteType) {
        // 同一目标既待删又待改时删除优先：服务端不该再收到一条更新。
        updatingPayloads.remove(targetId);
        deletingIds.add(targetId);
      } else if (!deletingIds.contains(targetId)) {
        updatingPayloads[targetId] = payload!;
      }
    }
    return (deletingIds: deletingIds, updatingPayloads: updatingPayloads);
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
    // 进度行先出：同一本书已合并为一条，数量很小，但笔记/批注积压超过一批时
    // 不能把续读指针排在 50 条之外等下一轮。其余操作仍按 createdAt 升序，
    // 保持 create→update 的先后语义（倒序会让旧更新覆盖新创建载荷）。
    final progressOps = await _pendingReaderOps(types: const [opProgress]);
    final otherOps = await _pendingReaderOps(
      types: _readerOperationTypes,
      limit: maxOperationBatch,
    );
    final remainingSlots = (maxOperationBatch - progressOps.length).clamp(
      0,
      maxOperationBatch,
    );
    final pending = <SyncOperation>[
      ...progressOps,
      ...otherOps
          .where((operation) => operation.type != opProgress)
          .take(remainingSlots),
    ];

    for (final op in pending) {
      try {
        await _dispatch(api, op);
        await _markCompleted(op.id);
      } on AppException catch (error) {
        if (error.code == AppErrorCodes.forbidden) {
          // 无 activity:write 的角色：书签/标注/笔记保留本地（本地优先
          // 模型，本地即真值），跳过远端同步，不做无意义重试。
          await _markCompleted(op.id);
        } else if (_isIdempotentDeleteFailure(op, error)) {
          // 记录多半在另一台设备上已经删掉了：补发永远不会成功，留着失败行会
          // 长期占表，并让本地删除一直显示"尚未同步"。
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
    if (pending.isNotEmpty) {
      // 已完成 reader 操作的 payload 含笔记/批注明文，同步成功后即清理，
      // 不在本地库长期保留敏感明文副本
      await (_database.delete(_database.syncOperations)..where(
        (table) =>
            table.status.equals('completed') &
            table.type.isIn(_readerOperationTypes) &
            _ownedByCurrentUser(table.userId),
      )).go();
    }
    // 进度以本地 cached_reader_progress 为真值，重试耗尽的失败行只会
    // 长期占表并在下次 retryFailed 里被反复捞起；笔记/批注失败行保留，
    // 那些数据本地即唯一副本。
    await (_database.delete(_database.syncOperations)..where(
      (table) =>
          table.type.equals(opProgress) &
          table.status.equals('failed') &
          table.retryCount.isBiggerOrEqualValue(maxOperationRetries) &
          _ownedByCurrentUser(table.userId),
    )).go();
  }

  /// 这次失败是否等于"服务端已经没有这条记录"：只有删除操作可以按幂等完成处理。
  ///
  /// 创建/更新遇到同一错误名不能吞——目标不存在意味着要新建的内容丢了。
  static bool _isIdempotentDeleteFailure(
    SyncOperation operation,
    AppException error,
  ) {
    if (!_deleteOperationTypes.contains(operation.type)) {
      return false;
    }
    final errorName = error.details['errorName'] as String?;
    return errorName != null && _alreadyGoneErrorNames.contains(errorName);
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
          // 补传沿用入队时的记录时刻，围栏才有意义；缺失时交给服务端按接收时间处理。
          clientUpdatedAt: DateTime.tryParse(
            payload['clientUpdatedAt'] as String? ?? '',
          ),
        );

      case opBookmarkCreate:
        final bookmark = await api.createBookmark(
          itemId: payload['itemId'] as String,
          chapterId: payload['chapterId'] as String?,
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
  static Future<void> retryFailed({int maxRetries = maxOperationRetries}) {
    return (_database.update(_database.syncOperations)..where(
      (table) =>
          table.status.equals('failed') &
          table.type.isIn(_readerOperationTypes) &
          table.retryCount.isSmallerThanValue(maxRetries) &
          _ownedByCurrentUser(table.userId),
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
                _database.syncOperations.type.isIn(_readerOperationTypes) &
                _ownedByCurrentUser(_database.syncOperations.userId),
          );
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 创建请求在途期间用户可能已经删除或改写了这条本地记录：回包后既不能把已删的
  /// 记录写回本地（服务端刚创建的那份也得跟着清），也不能让服务端返回值覆盖用户
  /// 刚写的内容（那才是最新意图，需要补一条更新把服务端对齐过来）。
  static ReaderLocalStorage get _localStorage =>
      ReaderLocalStorage(_database, textCipher: _textCipher, userId: _userId);

  static Future<void> _replaceBookmark(
    String? localId,
    ReaderBookmark bookmark,
  ) async {
    if (localId == null || localId.isEmpty || localId == bookmark.id) {
      return;
    }
    final replaced = await _localStorage.replaceBookmarkId(
      localId: localId,
      serverBookmark: bookmark,
    );
    if (!replaced) {
      await enqueueBookmarkDelete(bookmarkId: bookmark.id);
    }
  }

  static Future<void> _replaceAnnotation(
    String? localId,
    ReaderAnnotation annotation,
  ) async {
    if (localId == null || localId.isEmpty || localId == annotation.id) {
      return;
    }
    final storage = _localStorage;
    final local = await storage.loadAnnotationById(localId);
    if (local == null) {
      final replaced = await storage.replaceAnnotationId(
        localId: localId,
        serverAnnotation: annotation,
      );
      if (!replaced) {
        await enqueueAnnotationDelete(annotationId: annotation.id);
      }
      return;
    }
    await storage.replaceAnnotationId(
      localId: localId,
      serverAnnotation: annotation,
    );
    final note = local.note ?? annotation.note;
    final color = local.color;
    if (note != annotation.note || color != annotation.color) {
      await enqueueAnnotationUpdate(
        annotationId: annotation.id,
        note: note,
        color: color,
      );
    }
  }

  static Future<void> _replaceNote(String? localId, ReaderNote note) async {
    if (localId == null || localId.isEmpty || localId == note.id) {
      return;
    }
    final storage = _localStorage;
    final local = await storage.loadNoteById(localId);
    if (local == null) {
      final replaced = await storage.replaceNoteId(
        localId: localId,
        serverNote: note,
      );
      if (!replaced) {
        await enqueueNoteDelete(noteId: note.id);
      }
      return;
    }
    await storage.replaceNoteId(localId: localId, serverNote: note);
    if (local.title != note.title || local.content != note.content) {
      await enqueueNoteUpdate(
        noteId: note.id,
        title: local.title,
        content: local.content,
      );
    }
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
}

/// 队列中尚未同步成功的删改目标。
typedef ReaderPendingMutations =
    ({
      Set<String> deletingIds,
      Map<String, Map<String, dynamic>> updatingPayloads,
    });
