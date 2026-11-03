part of 'reader_sync_queue.dart';

/// 创建回包的 ID 归位：把客户端临时 ID 改写成服务端真实 ID。
///
/// 从 [ReaderSyncQueue] 拆出，职责是「一次创建成功后需要对齐的三件事」：
/// 改写指向 localId 的后续操作、替换本地行、以及本地行已被删时补发清理。
/// 与队列本体的差别在于它只处理创建回包，不参与入队与刷写调度。
class ReaderSyncReplacements {
  /// 创建请求在途期间用户可能已经删除或改写了这条本地记录：回包后既不能把已删的
  /// 记录写回本地（服务端刚创建的那份也得跟着清），也不能让服务端返回值覆盖用户
  /// 刚写的内容（那才是最新意图，需要补一条更新把服务端对齐过来）。
  static ReaderLocalStorage get _localStorage => ReaderLocalStorage(
    ReaderSyncQueue._database,
    textCipher: ReaderSyncQueue._textCipher,
    userId: ReaderSyncQueue._userId,
  );

  static Future<void> replaceBookmark(
    String? localId,
    ReaderBookmark bookmark,
  ) async {
    if (localId == null || localId.isEmpty || localId == bookmark.id) {
      return;
    }
    final rewritten = await _rewritePendingReference(
      localId: localId,
      serverId: bookmark.id,
      types: const {ReaderSyncQueue.opBookmarkDelete},
      field: 'bookmarkId',
    );
    final replaced = await _localStorage.replaceBookmarkId(
      localId: localId,
      serverBookmark: bookmark,
    );
    if (!replaced && !rewritten.contains(ReaderSyncQueue.opBookmarkDelete)) {
      await ReaderSyncQueue.enqueueBookmarkDelete(bookmarkId: bookmark.id);
    }
  }

  static Future<void> replaceAnnotation(
    String? localId,
    ReaderAnnotation annotation,
  ) async {
    if (localId == null || localId.isEmpty || localId == annotation.id) {
      return;
    }
    // 创建在途期间用户已排队的更新/删除仍指向 localId；服务端真 ID 回来后
    // 必须先改写这些操作，否则它们会带着临时 ID 必定失败。
    final rewritten = await _rewritePendingReference(
      localId: localId,
      serverId: annotation.id,
      types: const {
        ReaderSyncQueue.opAnnotationUpdate,
        ReaderSyncQueue.opAnnotationDelete,
      },
      field: 'annotationId',
    );
    // 旧行由替换事务自己读出：本地行在 HTTP 在途期间被删时返回 null，
    // 此时服务端刚创建的记录要补发删除，也不能再为一条已删记录排更新。
    final local = await _localStorage.replaceAnnotationId(
      localId: localId,
      serverAnnotation: annotation,
    );
    if (local == null) {
      if (!rewritten.contains(ReaderSyncQueue.opAnnotationDelete)) {
        await ReaderSyncQueue.enqueueAnnotationDelete(
          annotationId: annotation.id,
        );
      }
      return;
    }
    final note = local.note ?? annotation.note;
    final color = local.color;
    if (note != annotation.note || color != annotation.color) {
      await ReaderSyncQueue.enqueueAnnotationUpdate(
        annotationId: annotation.id,
        note: note,
        color: color,
      );
    }
  }

  static Future<void> replaceNote(String? localId, ReaderNote note) async {
    if (localId == null || localId.isEmpty || localId == note.id) {
      return;
    }
    final rewritten = await _rewritePendingReference(
      localId: localId,
      serverId: note.id,
      types: const {ReaderSyncQueue.opNoteUpdate, ReaderSyncQueue.opNoteDelete},
      field: 'noteId',
    );
    final local = await _localStorage.replaceNoteId(
      localId: localId,
      serverNote: note,
    );
    if (local == null) {
      if (!rewritten.contains(ReaderSyncQueue.opNoteDelete)) {
        await ReaderSyncQueue.enqueueNoteDelete(noteId: note.id);
      }
      return;
    }
    if (local.title != note.title || local.content != note.content) {
      await ReaderSyncQueue.enqueueNoteUpdate(
        noteId: note.id,
        title: local.title,
        content: local.content,
      );
    }
  }

  /// 把队列中指向客户端临时 ID 的更新/删除操作改写到服务端真实 ID。
  ///
  /// 只处理当前账号的 pending/failed 行；已完成行会在 flush 末尾清理。
  static Future<Set<String>> _rewritePendingReference({
    required String localId,
    required String serverId,
    required Set<String> types,
    required String field,
  }) async {
    final database = ReaderSyncQueue._database;
    final operations =
        await (database.select(database.syncOperations)..where(
          (table) =>
              table.type.isIn(types) &
              table.status.isIn(const ['pending', 'failed']) &
              ReaderSyncQueue._ownedByCurrentUser(table.userId),
        )).get();
    final rewritten = <String>{};
    for (final operation in operations) {
      final payload = await ReaderSyncQueue._decodePayload(operation);
      if (payload == null || payload[field] != localId) {
        continue;
      }
      payload[field] = serverId;
      await (database.update(database.syncOperations)
        ..where((table) => table.id.equals(operation.id))).write(
        SyncOperationsCompanion(
          payload: Value(await ReaderSyncQueue._serializePayload(payload)),
        ),
      );
      rewritten.add(operation.type);
    }
    return rewritten;
  }
}
