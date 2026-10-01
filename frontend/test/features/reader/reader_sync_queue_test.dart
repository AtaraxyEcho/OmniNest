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
}
