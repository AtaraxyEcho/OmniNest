import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

class _MockReaderApi extends Mock implements ReaderApi {}

void main() {
  late _MockReaderApi api;

  setUp(() {
    api = _MockReaderApi();
  });

  test('comic service loads manifest through reader API', () async {
    const manifest = ComicManifest(
      itemId: 'comic-1',
      sources: [],
      catalog: [],
      pages: [],
      importStatus: 'READY',
    );
    when(
      () => api.getComicManifest('comic-1'),
    ).thenAnswer((_) async => manifest);

    final result = await ReaderComicService(api).loadManifest('comic-1');

    expect(result, same(manifest));
    verify(() => api.getComicManifest('comic-1')).called(1);
  });

  test('progress service queues progress when remote update fails', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    ReaderSyncQueue.init(database);
    addTearDown(database.close);
    when(
      () => api.updateProgress(
        itemId: 'book-1',
        charOffset: 120,
        progressPercent: 0.4,
        readingMode: 'scroll',
        chapterId: 'chapter-2',
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
    ).thenThrow(Exception('offline'));

    await ReaderProgressSyncService(api).sync(
      itemId: 'book-1',
      charOffset: 120,
      progressPercent: 0.4,
      readingMode: 'scroll',
      chapterId: 'chapter-2',
    );

    final operations = await database.select(database.syncOperations).get();
    expect(operations, hasLength(1));
    expect(operations.single.type, ReaderSyncQueue.opProgress);
    expect(operations.single.payload, contains('chapter-2'));
  });
}
