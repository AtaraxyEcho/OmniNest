import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/data/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 摘要：本地进度必须带得全书比例，并且按账号归属隔离。
///
/// 停在非首章章首（偏移与章内比例都是 0）时，本地行没有任何"我读过这里"的数值证据，
/// 对账会被服务端停在旧章的位置无条件覆盖；共享书籍在不同账号下复用同一个 itemId，
/// 归属不进主键时换号会读到上一个账号的进度。
void main() {
  late LocalDatabase db;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('本地行保留全书比例，章首进度仍可被对账认出', () async {
    final store = DatabaseReaderLocalProgressStore(db, userId: 'user-a');
    await store.save(
      itemId: 'item-1',
      chapterId: 'chapter-10',
      charOffset: 0,
      chapterProgress: 0,
      bookProgress: 0.62,
      mode: 'scroll',
      updatedAt: DateTime(2026, 6, 2),
    );

    final payload = await store.load('item-1', 'chapter-10');
    expect(payload, isNotNull);
    final local = ReaderProgressSnapshot.fromLocal(payload);
    expect(local.bookProgress, closeTo(0.62, 1e-9));
    expect(local.hasReadableProgress, isTrue);

    final server = ReaderProgressSnapshot.fromServer(
      ReaderProgress(
        readerItemId: 'item-1',
        chapterId: 'chapter-2',
        charOffset: 4_000,
        progressPercent: 12,
        readingMode: 'scroll',
        updatedAt: DateTime(2026, 6, 1),
      ),
    );
    expect(
      ReaderProgressSnapshot.latest(local, server),
      same(local),
      reason: '本地章首位置带更新的时间戳，必须胜过服务端的旧章位置',
    );
  });

  test('进度按账号归属读写，换号读不到上一个账号的位置', () async {
    final ownerA = DatabaseReaderLocalProgressStore(db, userId: 'user-a');
    final ownerB = DatabaseReaderLocalProgressStore(db, userId: 'user-b');
    await ownerA.save(
      itemId: 'shared-item',
      chapterId: 'chapter-3',
      charOffset: 900,
      chapterProgress: 0.3,
      bookProgress: 0.3,
      mode: 'scroll',
      updatedAt: DateTime(2026, 6, 2),
    );

    expect(await ownerB.loadLatest('shared-item'), isNull);
    expect(await ownerA.loadLatest('shared-item'), isNotNull);

    // 同一本书在两个账号下各自成行，互不覆盖。
    await ownerB.save(
      itemId: 'shared-item',
      chapterId: 'chapter-7',
      charOffset: 100,
      chapterProgress: 0.1,
      bookProgress: 0.7,
      mode: 'scroll',
      updatedAt: DateTime(2026, 6, 3),
    );
    final kept = await ownerA.load('shared-item', 'chapter-3');
    expect(kept?['chapterId'], 'chapter-3');
    expect(kept?['charOffset'], 900);
  });

  test('未登录态只认空归属行，不误读也不误删具名账号的进度', () async {
    final anonymous = DatabaseReaderLocalProgressStore(db);
    final ownerA = DatabaseReaderLocalProgressStore(db, userId: 'user-a');
    await ownerA.save(
      itemId: 'shared-item',
      chapterId: 'chapter-5',
      charOffset: 1200,
      chapterProgress: 0.5,
      bookProgress: 0.5,
      mode: 'scroll',
      updatedAt: DateTime(2026, 6, 5),
    );

    // 退出登录的瞬间（或 provider 还没拿到 userId）读到的必须是匿名自己的那一份，
    // 而不是上一个账号停过的章节。
    expect(await anonymous.loadLatest('shared-item'), isNull);
    expect(await anonymous.load('shared-item', 'chapter-5'), isNull);

    // 匿名态清库只清 user_id 为空的行，具名账号的位置必须原样留下。
    await anonymous.clear('shared-item');
    expect(await ownerA.loadLatest('shared-item'), isNotNull);

    // 旧库升级行与未登录写入行的归属都是空串，匿名态照常读写。
    await anonymous.save(
      itemId: 'shared-item',
      chapterId: 'chapter-1',
      charOffset: 10,
      chapterProgress: 0.1,
      bookProgress: 0.1,
      mode: 'scroll',
      updatedAt: DateTime(2026, 6, 6),
    );
    expect(await anonymous.loadLatest('shared-item'), isNotNull);
    expect(await ownerA.load('shared-item', 'chapter-1'), isNull);
  });
}
