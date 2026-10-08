import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

class MockReaderApi extends Mock implements ReaderApi {}

void main() {
  late LocalDatabase db;
  late ReaderLocalStorage storage;
  late MockReaderApi api;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    storage = ReaderLocalStorage(db);
    api = MockReaderApi();
    ReaderSyncQueue.init(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('flush replaces local bookmark id with server bookmark id', () async {
    final createdAt = DateTime(2026, 6, 30);
    await storage.saveBookmark(
      ReaderBookmark(
        id: 'local-1',
        readerItemId: 'item-1',
        charOffset: 120,
        progressPercent: 0.12,
        note: 'note',
        createdAt: createdAt,
      ),
    );
    await ReaderSyncQueue.enqueueBookmarkCreate(
      localId: 'local-1',
      itemId: 'item-1',
      charOffset: 120,
      progressPercent: 0.12,
      note: 'note',
    );
    when(
      () => api.createBookmark(
        itemId: 'item-1',
        charOffset: 120,
        progressPercent: 0.12,
        note: 'note',
        clientOperationId: 'local-1',
      ),
    ).thenAnswer(
      (_) async => ReaderBookmark(
        id: 'server-1',
        readerItemId: 'item-1',
        charOffset: 120,
        progressPercent: 0.12,
        note: 'note',
        createdAt: createdAt,
      ),
    );

    await ReaderSyncQueue.flush(api: api);

    final bookmarks = await storage.loadBookmarks('item-1');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.id, 'server-1');
    verify(
      () => api.createBookmark(
        itemId: 'item-1',
        charOffset: 120,
        progressPercent: 0.12,
        note: 'note',
        clientOperationId: 'local-1',
      ),
    ).called(1);
    // 同步成功后的 reader 操作（含明文 payload）会被清理，不留本地副本
    final operations = await db.select(db.syncOperations).get();
    expect(operations, isEmpty);
  });

  test(
    'annotation loading merges remote data with pending local records',
    () async {
      final manager = ReaderDataManager(api: api, localStorage: storage);
      final pending = await manager.createAnnotation(
        itemId: 'item-annotations',
        chapterId: 'chapter_2',
        startOffset: 10,
        endOffset: 20,
        highlightText: 'pending',
      );
      final remote = ReaderAnnotation(
        id: 'annotation-server',
        readerItemId: 'item-annotations',
        startOffset: 30,
        endOffset: 40,
        highlightText: 'remote',
        color: '#FFEB3B',
        createdAt: DateTime(2026, 7, 18),
      );
      when(
        () => api.annotations('item-annotations'),
      ).thenAnswer((_) async => [remote]);

      final result = await manager.loadAnnotations('item-annotations');

      expect(result.map((annotation) => annotation.id), {
        'annotation-server',
        pending.id,
      });
      final cached = await storage.loadAnnotations('item-annotations');
      expect(cached, hasLength(2));
      expect(
        cached
            .singleWhere((annotation) => annotation.id == pending.id)
            .chapterId,
        'chapter_2',
      );
    },
  );

  test('annotation sync preserves chapter ownership', () async {
    final createdAt = DateTime(2026, 7, 31);
    await ReaderSyncQueue.enqueueAnnotationCreate(
      localId: 'local-annotation',
      itemId: 'item-annotations',
      chapterId: 'chapter_3',
      startOffset: 15,
      endOffset: 30,
      highlightText: 'chapter text',
    );
    when(
      () => api.createAnnotation(
        itemId: 'item-annotations',
        chapterId: 'chapter_3',
        startOffset: 15,
        endOffset: 30,
        highlightText: 'chapter text',
        color: '#FFEB3B',
        clientOperationId: 'local-annotation',
      ),
    ).thenAnswer(
      (_) async => ReaderAnnotation(
        id: 'server-annotation',
        readerItemId: 'item-annotations',
        chapterId: 'chapter_3',
        startOffset: 15,
        endOffset: 30,
        highlightText: 'chapter text',
        color: '#FFEB3B',
        createdAt: createdAt,
      ),
    );

    await ReaderSyncQueue.flush(api: api);

    verify(
      () => api.createAnnotation(
        itemId: 'item-annotations',
        chapterId: 'chapter_3',
        startOffset: 15,
        endOffset: 30,
        highlightText: 'chapter text',
        color: '#FFEB3B',
        clientOperationId: 'local-annotation',
      ),
    ).called(1);
    final cached = await storage.loadAnnotations('item-annotations');
    expect(cached.single.chapterId, 'chapter_3');
  });

  test('enqueueProgress 取代同书旧的进度行，保留其它书', () async {
    await ReaderSyncQueue.enqueueProgress(
      itemId: 'item-1',
      charOffset: 100,
      progressPercent: 0.1,
      readingMode: 'scroll',
      chapterId: 'chapter_1',
    );
    await ReaderSyncQueue.enqueueProgress(
      itemId: 'item-2',
      charOffset: 200,
      progressPercent: 0.2,
      readingMode: 'scroll',
      chapterId: 'chapter_1',
    );
    await ReaderSyncQueue.enqueueProgress(
      itemId: 'item-1',
      charOffset: 900,
      progressPercent: 0.9,
      readingMode: 'scroll',
      chapterId: 'chapter_2',
    );

    final rows = await db.select(db.syncOperations).get();
    final progressRows =
        rows.where((row) => row.type == ReaderSyncQueue.opProgress).toList();
    // 服务端进度是 last-write-wins：旧行重放只会用过期位置覆盖新位置，
    // 且离线期间每次失败都留下一行，重放时对同一本书逐条发 PUT。
    expect(progressRows, hasLength(2));
    final item1 =
        progressRows
            .where((row) => row.payload.contains('"itemId":"item-1"'))
            .toList();
    expect(item1, hasLength(1));
    expect(item1.single.payload.contains('"charOffset":900'), isTrue);
  });

  test('flush 清理重试耗尽的进度失败行，保留笔记失败行', () async {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: ReaderSyncQueue.opProgress,
            payload:
                '{"itemId":"item-1","charOffset":100,"progressPercent":0.1,"readingMode":"scroll"}',
            status: const Value('failed'),
            retryCount: const Value(3),
            createdAt: DateTime(2026, 6, 30),
          ),
        );
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: ReaderSyncQueue.opNoteUpdate,
            payload: '{"noteId":"note-1","content":"草稿"}',
            status: const Value('failed'),
            retryCount: const Value(3),
            createdAt: DateTime(2026, 6, 30),
          ),
        );

    await ReaderSyncQueue.flush(api: api);

    final rows = await db.select(db.syncOperations).get();
    // 进度有本地行为真值，耗尽重试的失败行只是噪声；
    // 笔记/批注本地即真值，必须留着重试或对用户可见。
    expect(rows.map((row) => row.type), [ReaderSyncQueue.opNoteUpdate]);
  });

  test('flush 在笔记积压超过一批时仍先上报进度', () async {
    for (var index = 0; index < 60; index++) {
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              type: ReaderSyncQueue.opNoteUpdate,
              payload:
                  '{"noteId":"note-$index","title":null,"content":"草稿 $index"}',
              createdAt: DateTime(2026, 6, 1).add(Duration(minutes: index)),
            ),
          );
    }
    await ReaderSyncQueue.enqueueProgress(
      itemId: 'item-1',
      charOffset: 4000,
      progressPercent: 0.4,
      readingMode: 'scroll',
      chapterId: 'chapter_2',
    );

    await ReaderSyncQueue.flush(api: api);

    verify(
      () => api.updateProgress(
        itemId: 'item-1',
        charOffset: 4000,
        progressPercent: 0.4,
        readingMode: 'scroll',
        chapterId: 'chapter_2',
        pageId: null,
        pageIndex: null,
        pageFingerprint: null,
        sourceId: null,
        sourcePageIndex: null,
        catalogKey: null,
        manifestVersion: null,
        intraPageOffset: null,
        clientUpdatedAt: null,
      ),
    ).called(1);
  });

  test('flush ignores non reader operations in shared sync table', () async {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: 'file.favorite',
            payload: '{"fileId":"file-1"}',
            createdAt: DateTime(2026, 6, 30),
          ),
        );

    await ReaderSyncQueue.flush(api: api);

    final operations = await db.select(db.syncOperations).get();
    expect(operations.single.status, 'pending');
    verifyNever(
      () => api.updateProgress(
        itemId: any(named: 'itemId'),
        charOffset: any(named: 'charOffset'),
        progressPercent: any(named: 'progressPercent'),
        readingMode: any(named: 'readingMode'),
        chapterId: any(named: 'chapterId'),
      ),
    );
  });

  test('flush syncs comic progress anchor fields', () async {
    await ReaderSyncQueue.enqueueProgress(
      itemId: 'comic-1',
      charOffset: 12,
      progressPercent: 0.4,
      readingMode: 'scroll',
      chapterId: 'chapter-a',
      pageId: 'page-12',
      pageIndex: 12,
      pageFingerprint: 'fingerprint-12',
      sourceId: 'source-1',
      sourcePageIndex: 8,
      catalogKey: 'volume-1/chapter-a',
      manifestVersion: 3,
      intraPageOffset: 0.35,
    );
    when(
      () => api.updateProgress(
        itemId: 'comic-1',
        charOffset: 12,
        progressPercent: 0.4,
        readingMode: 'scroll',
        chapterId: 'chapter-a',
        pageId: 'page-12',
        pageIndex: 12,
        pageFingerprint: 'fingerprint-12',
        sourceId: 'source-1',
        sourcePageIndex: 8,
        catalogKey: 'volume-1/chapter-a',
        manifestVersion: 3,
        intraPageOffset: 0.35,
        clientUpdatedAt: null,
      ),
    ).thenAnswer((_) async {});

    await ReaderSyncQueue.flush(api: api);

    verify(
      () => api.updateProgress(
        itemId: 'comic-1',
        charOffset: 12,
        progressPercent: 0.4,
        readingMode: 'scroll',
        chapterId: 'chapter-a',
        pageId: 'page-12',
        pageIndex: 12,
        pageFingerprint: 'fingerprint-12',
        sourceId: 'source-1',
        sourcePageIndex: 8,
        catalogKey: 'volume-1/chapter-a',
        manifestVersion: 3,
        intraPageOffset: 0.35,
        clientUpdatedAt: null,
      ),
    ).called(1);
    // 同步成功后的 reader 操作（含明文 payload）会被清理，不留本地副本
    final operations = await db.select(db.syncOperations).get();
    expect(operations, isEmpty);
  });

  test('deleting local bookmark cancels unsynced create operation', () async {
    final manager = ReaderDataManager(api: api, localStorage: storage);

    final bookmark = await manager.createBookmark(
      itemId: 'item-1',
      charOffset: 80,
      progressPercent: 0.08,
      note: 'draft',
    );
    await manager.deleteBookmark(bookmark.id);
    await ReaderSyncQueue.flush(api: api);

    final bookmarks = await storage.loadBookmarks('item-1');
    expect(bookmarks, isEmpty);
    final operations = await db.select(db.syncOperations).get();
    expect(operations, isEmpty);
    verifyNever(
      () => api.createBookmark(
        itemId: any(named: 'itemId'),
        charOffset: any(named: 'charOffset'),
        progressPercent: any(named: 'progressPercent'),
        note: any(named: 'note'),
        clientOperationId: any(named: 'clientOperationId'),
      ),
    );
  });

  test('flush marks malformed reader operation as failed', () async {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: ReaderSyncQueue.opProgress,
            payload: '{"itemId":',
            createdAt: DateTime(2026, 6, 30),
          ),
        );

    await ReaderSyncQueue.flush(api: api);

    final operations = await db.select(db.syncOperations).get();
    expect(operations.single.status, 'failed');
    expect(operations.single.retryCount, 1);
    verifyNever(
      () => api.updateProgress(
        itemId: any(named: 'itemId'),
        charOffset: any(named: 'charOffset'),
        progressPercent: any(named: 'progressPercent'),
        readingMode: any(named: 'readingMode'),
        chapterId: any(named: 'chapterId'),
      ),
    );
  });

  test('离线补传保留进度的记录时刻', () async {
    // 服务端围栏比的是"这条进度何时记录"，补传若换成发送时刻，离线一小时的
    // 旧读数就会反过来赢过在线设备刚写入的位置。
    final reportedAt = DateTime.utc(2026, 10, 8, 1, 2, 3);
    await ReaderSyncQueue.enqueueProgress(
      itemId: 'item-1',
      charOffset: 900,
      progressPercent: 0.3,
      readingMode: 'page',
      chapterId: 'chapter_1',
      clientUpdatedAt: reportedAt,
    );
    when(
      () => api.updateProgress(
        itemId: 'item-1',
        charOffset: 900,
        progressPercent: 0.3,
        readingMode: 'page',
        chapterId: 'chapter_1',
        pageId: null,
        pageIndex: null,
        pageFingerprint: null,
        sourceId: null,
        sourcePageIndex: null,
        catalogKey: null,
        manifestVersion: null,
        intraPageOffset: null,
        clientUpdatedAt: reportedAt,
      ),
    ).thenAnswer((_) async {});

    await ReaderSyncQueue.flush(api: api);

    verify(
      () => api.updateProgress(
        itemId: 'item-1',
        charOffset: 900,
        progressPercent: 0.3,
        readingMode: 'page',
        chapterId: 'chapter_1',
        pageId: null,
        pageIndex: null,
        pageFingerprint: null,
        sourceId: null,
        sourcePageIndex: null,
        catalogKey: null,
        manifestVersion: null,
        intraPageOffset: null,
        clientUpdatedAt: reportedAt,
      ),
    ).called(1);
  });
}
