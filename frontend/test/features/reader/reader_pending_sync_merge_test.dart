import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/errors/app_exception.dart';
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

  /// 拉取书籍 A 时手里只有 A 的远端 ID 集合，而待删操作横跨整库。
  ///
  /// 早先的实现据此"清理服务端已不存在的待删项"，等于把书籍 B 尚未同步的删除
  /// 当成已删成功丢掉——下次打开书籍 B，服务端那条书签又回来了。
  test('打开另一本书不会丢掉别本书尚未同步的删除墓碑', () async {
    when(() => api.deleteBookmark('bm-book-b')).thenThrow(Exception('网络不可用'));
    await ReaderSyncQueue.enqueueBookmarkDelete(bookmarkId: 'bm-book-b');
    await ReaderSyncQueue.flush(api: api);

    when(() => api.bookmarks('item-a')).thenAnswer(
      (_) async => [
        ReaderBookmark(
          id: 'bm-book-a',
          readerItemId: 'item-a',
          charOffset: 10,
          progressPercent: 0.1,
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
    );
    await manager.loadBookmarks('item-a');

    final pending = await ReaderSyncQueue.pendingMutations(
      deleteType: ReaderSyncQueue.opBookmarkDelete,
      idField: 'bookmarkId',
    );
    expect(
      pending.deletingIds,
      contains('bm-book-b'),
      reason: '别本书的待删 ID 不在当前书的远端快照里，不代表服务端已经删掉了它',
    );
  });

  /// `_doFlush` 只捞 `pending`，而断网期间试传过一次的操作停在 `failed`。
  /// 拉取列表前不先 `retryFailed`，那条删除就永远不会再发出去。
  test('网络恢复后的列表拉取会唤醒并重放失败过的删除', () async {
    when(() => api.deleteBookmark('bm-stale')).thenThrow(Exception('网络不可用'));
    await ReaderSyncQueue.enqueueBookmarkDelete(bookmarkId: 'bm-stale');
    await ReaderSyncQueue.flush(api: api);

    when(() => api.deleteBookmark('bm-stale')).thenAnswer((_) async {});
    when(() => api.bookmarks('item-1')).thenAnswer((_) async => const []);
    await manager.loadBookmarks('item-1');

    verify(() => api.deleteBookmark('bm-stale')).called(2);
    final pending = await ReaderSyncQueue.pendingMutations(
      deleteType: ReaderSyncQueue.opBookmarkDelete,
      idField: 'bookmarkId',
    );
    expect(pending.deletingIds, isEmpty);
  });

  /// 目标在另一端已被删掉：删除操作按幂等完成清行，否则失败行长期占表并让本地
  /// 删除一直显示"尚未同步"。同一个错误名落在更新上不能吞——内容只有本地那一份。
  test('服务端报"记录不存在"时删除幂等完成、更新保留失败', () async {
    const gone = AppException(
      code: '5001',
      message: '记录不存在',
      details: {'errorName': 'MEDIA_NOT_FOUND'},
    );
    when(() => api.deleteBookmark('bm-gone')).thenThrow(gone);
    await ReaderSyncQueue.enqueueBookmarkDelete(bookmarkId: 'bm-gone');
    await ReaderSyncQueue.flush(api: api);

    final deletes = await ReaderSyncQueue.pendingMutations(
      deleteType: ReaderSyncQueue.opBookmarkDelete,
      idField: 'bookmarkId',
    );
    expect(deletes.deletingIds, isEmpty);

    when(
      () => api.updateAnnotation(
        'an-1',
        note: any(named: 'note'),
        color: any(named: 'color'),
      ),
    ).thenThrow(gone);
    await ReaderSyncQueue.enqueueAnnotationUpdate(
      annotationId: 'an-1',
      note: '离线写的批注',
    );
    await ReaderSyncQueue.flush(api: api);

    final updates = await ReaderSyncQueue.pendingMutations(
      updateType: ReaderSyncQueue.opAnnotationUpdate,
      deleteType: ReaderSyncQueue.opAnnotationDelete,
      idField: 'annotationId',
    );
    expect(
      updates.updatingPayloads.keys,
      contains('an-1'),
      reason: '更新遇到同一业务错误不能标成完成：那条内容只有本地这一份',
    );
  });
}
