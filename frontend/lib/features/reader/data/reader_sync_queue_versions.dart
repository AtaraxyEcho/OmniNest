part of 'reader_sync_queue.dart';

/// 更新请求的乐观锁版本：读本地最后看到的版本、成功后回写、冲突时取回远端版本。
///
/// 从 [ReaderSyncQueue] 拆出，只服务「更新已有记录」这一条链路：创建走
/// `ReaderSyncReplacements`，进度与书签不需要版本。冲突重试仍是本地内容覆盖，
/// 只是让它在覆盖前经过一次显式确认，避免并发编辑完全无感地互相抹掉。
class ReaderSyncVersions {
  /// 更新批注：带上本地最后看到的版本；被其他设备改过时取回新版本重试一次。
  static Future<void> dispatchAnnotationUpdate(
    ReaderApi api,
    Map<String, dynamic> payload,
  ) async {
    final annotationId = payload['annotationId'] as String;
    final note = payload['note'] as String?;
    final color = payload['color'] as String?;
    try {
      await _applyAnnotationUpdate(api, annotationId, note: note, color: color);
    } on AppException catch (error) {
      if (error.code != AppErrorCodes.conflict) rethrow;
      if (!await rebaseAnnotation(api, annotationId)) {
        // 服务端已没有这条批注：本地无从对齐版本，留给失败队列显式暴露。
        rethrow;
      }
      await _applyAnnotationUpdate(api, annotationId, note: note, color: color);
    }
  }

  static Future<void> dispatchNoteUpdate(
    ReaderApi api,
    Map<String, dynamic> payload,
  ) async {
    final noteId = payload['noteId'] as String;
    final title = payload['title'] as String?;
    final content = payload['content'] as String;
    try {
      await _applyNoteUpdate(api, noteId, title: title, content: content);
    } on AppException catch (error) {
      if (error.code != AppErrorCodes.conflict) rethrow;
      if (!await rebaseNote(api, noteId)) {
        rethrow;
      }
      await _applyNoteUpdate(api, noteId, title: title, content: content);
    }
  }

  static Future<void> _applyAnnotationUpdate(
    ReaderApi api,
    String annotationId, {
    String? note,
    String? color,
  }) async {
    final updated = await api.updateAnnotation(
      annotationId,
      note: note,
      color: color,
      expectedVersion: await localAnnotationVersion(annotationId),
    );
    await writeAnnotationVersion(annotationId, updated.version);
  }

  static Future<void> _applyNoteUpdate(
    ReaderApi api,
    String noteId, {
    String? title,
    required String content,
  }) async {
    final updated = await api.updateNote(
      noteId,
      title: title,
      content: content,
      expectedVersion: await localNoteVersion(noteId),
    );
    await writeNoteVersion(noteId, updated.version);
  }

  static Future<int?> localAnnotationVersion(String annotationId) async {
    final db = ReaderSyncQueue._db;
    if (db == null) return null;
    final row =
        await (db.select(db.cachedReaderAnnotations)..where(
          (t) =>
              t.id.equals(annotationId) &
              ReaderSyncQueue._ownedByCurrentUser(t.userId),
        )).getSingleOrNull();
    return row?.version;
  }

  static Future<void> writeAnnotationVersion(
    String annotationId,
    int? version,
  ) async {
    final db = ReaderSyncQueue._db;
    if (db == null || version == null) return;
    await (db.update(db.cachedReaderAnnotations)..where(
      (t) =>
          t.id.equals(annotationId) &
          ReaderSyncQueue._ownedByCurrentUser(t.userId),
    )).write(CachedReaderAnnotationsCompanion(version: Value(version)));
  }

  /// 冲突后取回服务端当前版本写入本地，供下一次（也是最后一次）重试携带。
  static Future<bool> rebaseAnnotation(
    ReaderApi api,
    String annotationId,
  ) async {
    final db = ReaderSyncQueue._db;
    if (db == null) return false;
    final row =
        await (db.select(db.cachedReaderAnnotations)..where(
          (t) =>
              t.id.equals(annotationId) &
              ReaderSyncQueue._ownedByCurrentUser(t.userId),
        )).getSingleOrNull();
    if (row == null) return false;
    final remote = await api.annotations(row.readerItemId);
    for (final annotation in remote) {
      if (annotation.id == annotationId) {
        await writeAnnotationVersion(annotationId, annotation.version);
        return annotation.version != null;
      }
    }
    return false;
  }

  static Future<int?> localNoteVersion(String noteId) async {
    final db = ReaderSyncQueue._db;
    if (db == null) return null;
    final row =
        await (db.select(db.cachedReaderNotes)..where(
          (t) =>
              t.id.equals(noteId) &
              ReaderSyncQueue._ownedByCurrentUser(t.userId),
        )).getSingleOrNull();
    return row?.version;
  }

  static Future<void> writeNoteVersion(String noteId, int? version) async {
    final db = ReaderSyncQueue._db;
    if (db == null || version == null) return;
    await (db.update(db.cachedReaderNotes)..where(
      (t) =>
          t.id.equals(noteId) & ReaderSyncQueue._ownedByCurrentUser(t.userId),
    )).write(CachedReaderNotesCompanion(version: Value(version)));
  }

  static Future<bool> rebaseNote(ReaderApi api, String noteId) async {
    final db = ReaderSyncQueue._db;
    if (db == null) return false;
    final row =
        await (db.select(db.cachedReaderNotes)..where(
          (t) =>
              t.id.equals(noteId) &
              ReaderSyncQueue._ownedByCurrentUser(t.userId),
        )).getSingleOrNull();
    if (row == null) return false;
    final remote = await api.notes(row.readerItemId);
    for (final note in remote) {
      if (note.id == noteId) {
        await writeNoteVersion(noteId, note.version);
        return note.version != null;
      }
    }
    return false;
  }
}
