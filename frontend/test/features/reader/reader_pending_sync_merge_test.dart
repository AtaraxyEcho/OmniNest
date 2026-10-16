import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/domain/reader_annotation.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/domain/reader_note.dart';

class MockReaderApi extends Mock implements ReaderApi {}

/// 摘要：书签/批注/笔记的远端拉取必须先 flush 队列，并按待同步操作合并。
///
/// 只读本地的书签列表让跨设备同步断联；远端快照全量覆写本地会让离线删除的记录
/// 复活、离线改过的内容回滚；创建请求在途期间用户删掉本地行时，回包不得把它写回。
void main() {
  late LocalDatabase db;
  late ReaderLocalStorage storage;
  late MockReaderApi api;
  late ReaderDataManager manager;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    storage = ReaderLocalStorage(db);
    api = MockReaderApi();
    ReaderSyncQueue.init(db);
    manager = ReaderDataManager(api: api, localStorage: storage);
    registerFallbackValue('');
  });

  tearDown(() async {
    await db.close();
  });

  test('loadBookmarks 拉取服务端书签并落到本地', () async {
    final remote = ReaderBookmark(
      id: 'server-bookmark',
      readerItemId: 'item-1',
      charOffset: 420,
      progressPercent: 0.42,
      createdAt: DateTime(2026, 7, 1),
    );
    when(() => api.bookmarks('item-1')).thenAnswer((_) async => [remote]);
    when(() => api.annotations(any())).thenAnswer((_) async => const []);
    when(() => api.notes(any())).thenAnswer((_) async => const []);

    final loaded = await manager.loadBookmarks('item-1');

    expect(loaded.map((bookmark) => bookmark.id), ['server-bookmark']);
    final cached = await storage.loadBookmarks('item-1');
    expect(cached, hasLength(1));
  });

  test('离线删除的记录不被远端快照复活', () async {
    final remote = ReaderNote(
      id: 'server-note',
      readerItemId: 'item-1',
      content: '旧内容',
      createdAt: DateTime(2026, 7, 1),
    );
    await storage.saveNote(remote);
    when(() => api.notes('item-1')).thenAnswer((_) async => [remote]);
    // 删除请求推不上去（离线）：队列里那条待删操作是"用户已经删了"的唯一凭证。
    // 若删除已成功，服务端就不会再返回这条记录，无需这一层遮挡。
    when(
      () => api.deleteNote('server-note'),
    ).thenAnswer((_) async => throw Exception('网络不可用'));

    await manager.deleteNote('server-note');
    expect(await storage.loadNotes('item-1'), isEmpty);

    final loaded = await manager.loadNotes('item-1');

    expect(loaded, isEmpty, reason: '删除尚未同步成功时远端回来的旧记录必须被挡掉');
    final cached = await storage.loadNotes('item-1');
    expect(cached, isEmpty);
  });

  test('离线改过的内容不被远端旧值覆盖', () async {
    final remote = ReaderAnnotation(
      id: 'server-annotation',
      readerItemId: 'item-1',
      chapterId: 'chapter-1',
      startOffset: 10,
      endOffset: 20,
      note: '服务端旧值',
      color: '#FFEB3B',
      createdAt: DateTime(2026, 7, 1),
    );
    await storage.saveAnnotation(remote);
    when(() => api.annotations('item-1')).thenAnswer((_) async => [remote]);
    // 更新还没推上去：远端这份还是旧文字，按快照覆写就是把用户的编辑回滚。
    when(
      () => api.updateAnnotation(
        'server-annotation',
        note: any(named: 'note'),
        color: any(named: 'color'),
      ),
    ).thenAnswer((_) async => throw Exception('网络不可用'));

    await manager.updateAnnotation(
      annotationId: 'server-annotation',
      note: '离线写的新批注',
    );

    final loaded = await manager.loadAnnotations('item-1');

    expect(loaded.single.note, '离线写的新批注');
    final cached = await storage.loadAnnotations('item-1');
    expect(cached.single.note, '离线写的新批注');
  });

  test('在途创建被删除后不复活，并补发服务端删除', () async {
    await storage.saveBookmark(
      ReaderBookmark(
        id: 'local-vanishing',
        readerItemId: 'item-1',
        charOffset: 60,
        progressPercent: 0.06,
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await ReaderSyncQueue.enqueueBookmarkCreate(
      localId: 'local-vanishing',
      itemId: 'item-1',
      charOffset: 60,
      progressPercent: 0.06,
    );
    when(
      () => api.createBookmark(
        itemId: 'item-1',
        charOffset: 60,
        progressPercent: 0.06,
        clientOperationId: 'local-vanishing',
      ),
    ).thenAnswer(
      (_) async => ReaderBookmark(
        id: 'server-vanishing',
        readerItemId: 'item-1',
        charOffset: 60,
        progressPercent: 0.06,
        createdAt: DateTime(2026, 7, 2),
      ),
    );
    when(() => api.deleteBookmark('server-vanishing')).thenAnswer((_) async {});
    when(() => api.bookmarks(any())).thenAnswer((_) async => const []);
    when(() => api.annotations(any())).thenAnswer((_) async => const []);
    when(() => api.notes(any())).thenAnswer((_) async => const []);

    // 模拟"HTTP 在途期间用户删了这条本地书签"：本地行先消失，回包随后到达。
    await storage.deleteBookmark('local-vanishing');
    await ReaderSyncQueue.flush(api: api);

    expect(
      await storage.loadBookmarkById('server-vanishing'),
      isNull,
      reason: '回包不得把已删记录写回本地',
    );
    final pending = await ReaderSyncQueue.pendingMutations(
      deleteType: ReaderSyncQueue.opBookmarkDelete,
      idField: 'bookmarkId',
    );
    expect(pending.deletingIds, contains('server-vanishing'));
  });
}
