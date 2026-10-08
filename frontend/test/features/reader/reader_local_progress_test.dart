import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/data/reader_local_progress.dart';

void main() {
  test('本地行沿用进度自己的记录时刻', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DatabaseReaderLocalProgressStore(db);
    final recordedAt = DateTime.utc(2026, 10, 8, 1, 2, 3);

    await store.save(
      itemId: 'book-1',
      chapterProgress: 0.4,
      mode: 'scroll',
      chapterId: 'chapter-1',
      charOffset: 500,
      updatedAt: recordedAt,
    );

    final row = await db.select(db.cachedReaderProgress).getSingle();
    // drift 取回的是本地无时区的同一时刻，比较必须换算到 UTC。
    expect(
      row.updatedAt.toUtc(),
      recordedAt,
      reason:
          '写盘时刻顶掉记录时刻后，延迟落盘或失败重放的旧读数会被打成"刚刚"，'
          '与服务端行的时间戳混比时会被误判为最新',
    );
  });

  test('未指定记录时刻时退回写盘时刻', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DatabaseReaderLocalProgressStore(db);
    final before = DateTime.now();

    await store.save(
      itemId: 'book-1',
      chapterProgress: 0.4,
      mode: 'scroll',
      chapterId: 'chapter-1',
      charOffset: 500,
    );

    final row = await db.select(db.cachedReaderProgress).getSingle();
    expect(
      row.updatedAt.isAfter(before.subtract(const Duration(seconds: 5))),
      isTrue,
    );
  });

  test('阅读进度门面将操作委托给注入的存储端口', () async {
    final store = _FakeReaderLocalProgressStore();
    ReaderLocalProgress.init(store);

    await ReaderLocalProgress.save(
      itemId: 'book-1',
      chapterProgress: 0.42,
      mode: 'page',
      chapterId: 'chapter-2',
      charOffset: 128,
      pageId: 'page-3',
      pageIndex: 2,
    );

    expect(store.savedItemId, 'book-1');
    expect(store.savedChapterId, 'chapter-2');
    expect(store.savedCharOffset, 128);
    expect(await ReaderLocalProgress.load('book-1', 'chapter-2'), {
      'kind': 'chapter',
    });
    expect(await ReaderLocalProgress.loadLatest('book-1'), {'kind': 'latest'});

    await ReaderLocalProgress.clear('book-1');
    expect(store.clearedItemId, 'book-1');
  });
}

class _FakeReaderLocalProgressStore implements ReaderLocalProgressStore {
  String? savedItemId;
  String? savedChapterId;
  int? savedCharOffset;
  String? clearedItemId;

  @override
  Future<void> save({
    required String itemId,
    required double chapterProgress,
    required String mode,
    String? chapterId,
    int charOffset = 0,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
    DateTime? updatedAt,
  }) async {
    savedItemId = itemId;
    savedChapterId = chapterId;
    savedCharOffset = charOffset;
  }

  @override
  Future<Map<String, dynamic>?> load(String itemId, String chapterId) async {
    return {'kind': 'chapter'};
  }

  @override
  Future<Map<String, dynamic>?> loadLatest(String itemId) async {
    return {'kind': 'latest'};
  }

  @override
  Future<void> clear(String itemId) async {
    clearedItemId = itemId;
  }
}
