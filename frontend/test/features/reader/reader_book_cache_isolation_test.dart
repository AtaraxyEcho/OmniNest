import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';

/// 书籍正文缓存的账号归属与元数据重写行为。
///
/// `processed_html`、`stylesheet_refs_json` 与 `stylesheet_pool_json` 用当前登录
/// 用户的密钥加密；共享书籍在不同账号下复用同一个 itemId，行不归户就会让换号后
/// 的账号拿别人的密钥解自己的密文。
void main() {
  late LocalDatabase db;

  ReaderLocalStorage storeFor(String userId) =>
      ReaderLocalStorage(db, userId: userId);

  Future<void> seedChapter(
    ReaderLocalStorage store, {
    String itemId = 'book-1',
    String contentPath = 'OEBPS/ch1.xhtml',
  }) => store.saveChapterContent(
    itemId: itemId,
    contentPath: contentPath,
    title: '第一章',
    chapterNumber: 1,
    charCount: 24,
    processedHtml: '<html><body><p>正文一段</p></body></html>',
    stylesheetRefs: const ['OEBPS/styles/a.css'],
  );

  Future<void> seedBookMeta(
    ReaderLocalStorage store, {
    String itemId = 'book-1',
  }) => store.saveBookMeta(
    itemId: itemId,
    title: '测试书',
    chaptersJson: '[]',
    totalChars: 120,
    itemType: 'EPUB',
    cacheVersion: 'v1',
  );

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('另一个账号读不到别人的章节切片与样式表池', () async {
    final alice = storeFor('alice');
    await seedBookMeta(alice);
    await alice.saveStylesheetPool(
      itemId: 'book-1',
      pool: const {'OEBPS/styles/a.css': 'p { margin-bottom: 1em }'},
    );
    await seedChapter(alice);

    final bob = storeFor('bob');
    expect(await bob.loadBookMeta('book-1'), isNull);
    expect(await bob.loadStylesheetPool('book-1'), isEmpty);
    expect(
      await bob.loadChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/ch1.xhtml',
      ),
      isNull,
    );

    // 同账号仍然命中自己的缓存，归属过滤没有把缓存整体打死。
    expect(await alice.loadBookMeta('book-1'), isNotNull);
    expect(await alice.loadStylesheetPool('book-1'), isNotEmpty);
  });

  test('同一本书在两个账号下各存一份切片', () async {
    await seedChapter(storeFor('alice'));
    await seedChapter(storeFor('bob'));

    final rows = await db.select(db.cachedReaderChapters).get();
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.userId).toSet(), {'alice', 'bob'});
  });

  test('重写元数据不会抹掉已写入的样式表池', () async {
    final store = storeFor('alice');
    await seedBookMeta(store);
    expect(
      await store.saveStylesheetPool(
        itemId: 'book-1',
        pool: const {'OEBPS/styles/a.css': 'p { margin-bottom: 1em }'},
      ),
      isTrue,
    );

    await seedBookMeta(store);

    final row = await db.select(db.cachedReaderBooks).getSingle();
    expect(jsonDecode(row.stylesheetPoolJson), {
      'OEBPS/styles/a.css': isNotNull,
    });
  });

  test('删除条目连带清掉元数据与章节切片', () async {
    final store = storeFor('alice');
    await seedBookMeta(store);
    await seedChapter(store);

    await store.deleteAllForItem('book-1');

    expect(await db.select(db.cachedReaderBooks).get(), isEmpty);
    expect(await db.select(db.cachedReaderChapters).get(), isEmpty);
  });

  test('章节行清完后只回收同账号的孤儿样式表池', () async {
    final alice = storeFor('alice');
    final bob = storeFor('bob');
    await seedBookMeta(alice);
    await seedBookMeta(bob, itemId: 'book-1');
    await alice.saveStylesheetPool(
      itemId: 'book-1',
      pool: const {'a.css': 'p {}'},
    );
    await bob.saveStylesheetPool(
      itemId: 'book-1',
      pool: const {'b.css': 'p {}}'},
    );
    // 两边都没有章节行：两条池都是孤儿，必须各自被清。
    await alice.cleanOldChapters(maxAgeDays: 0);

    final rows = await db.select(db.cachedReaderBooks).get();
    expect(rows, hasLength(2));
    expect(rows.every((row) => row.stylesheetPoolJson == '{}'), isTrue);
  });
}
