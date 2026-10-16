import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';

class MockReaderApi extends Mock implements ReaderApi {}

/// 详情页的批注与书签页签必须与阅读页同源（离线优先的 ReaderDataManager）。
///
/// 阅读页里的增删改先写 SQLite、再排进同步队列，退出时并不保证已经 flush：页签直连
/// 服务端就看不到未上传的那份，断网时整个页签报错。
void main() {
  late LocalDatabase db;
  late ReaderLocalStorage storage;
  late MockReaderApi api;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    storage = ReaderLocalStorage(db);
    api = MockReaderApi();
    ReaderSyncQueue.init(db);
    registerFallbackValue('');
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        readerApiProvider.overrideWithValue(api),
        readerLocalStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('离线时书签页签返回本地那份，不抛错也不空列表', () async {
    await storage.saveBookmark(
      ReaderBookmark(
        id: 'local-bookmark',
        readerItemId: 'item-1',
        charOffset: 420,
        progressPercent: 0.42,
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    when(() => api.bookmarks(any())).thenThrow(Exception('offline'));

    final bookmarks = await buildContainer().read(
      readerItemBookmarksProvider('item-1').future,
    );

    expect(bookmarks.map((bookmark) => bookmark.id), ['local-bookmark']);
  });

  test('离线时批注页签返回本地那份，不抛错也不空列表', () async {
    await storage.saveAnnotation(
      ReaderAnnotation(
        id: 'local-annotation',
        readerItemId: 'item-1',
        startOffset: 10,
        endOffset: 20,
        highlightText: '原句',
        color: '#FFEB3B',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    when(() => api.annotations(any())).thenThrow(Exception('offline'));

    final annotations = await buildContainer().read(
      readerItemAnnotationsProvider('item-1').future,
    );

    expect(annotations.map((annotation) => annotation.id), [
      'local-annotation',
    ]);
  });
}
