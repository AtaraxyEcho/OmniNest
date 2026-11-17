import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/epub_parser_service.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

/// 样式表的存储形态：书级池一份 + 章节次序引用，正文里不再有那份 `<style>` 载体。
///
/// 旧写法把整本书的 CSS 插进每一章的 body 再入库，393 章 ×12KB 就是 4.8MB，
/// 还让落库预算必须为它留放行额度。改成池 + 次序之后，跟着章变的只有那串路径。
void main() {
  /// 池自己的插入序是 manifest 序（a 在 b 前），本章的 link 序正好相反。
  const pool = <String, String>{
    'OEBPS/styles/a.css': 'p { margin-bottom: 1em }',
    'OEBPS/styles/b.css': 'p { margin-bottom: 3em }',
  };
  const chapterRefs = ['OEBPS/styles/b.css', 'OEBPS/styles/a.css'];
  const cleanBody = '<html><body><p>正文一段</p></body></html>';

  /// 旧载体的等价形态：样式表拼成一个 `<style>` 插在最后一个 `</body>` 之前。
  String carrierBody(String css) =>
      '<html><body><p>正文一段</p><style>$css</style></body></html>';

  double? spacingOf(ParagraphBlock block) => block.style?.paragraphSpacingScale;

  ParagraphBlock onlyParagraph(List<ContentBlock> blocks) =>
      blocks.whereType<ParagraphBlock>().single;

  ReaderLocalStorage store(LocalDatabase db) => ReaderLocalStorage(db);

  Future<void> seedBookMeta(
    ReaderLocalStorage localStore, {
    String itemId = 'book-1',
  }) => localStore.saveBookMeta(
    itemId: itemId,
    title: '测试书',
    chaptersJson: '[]',
    totalChars: 120,
    itemType: 'EPUB',
    cacheVersion: 'v1',
  );

  group('章节行', () {
    test('只带次序引用，正文与样式表分开存', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);
      final css = buildChapterStylesheetCss(pool, chapterRefs);
      expect(css, contains('margin-bottom'));

      await localStore.saveChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/chapter1.xhtml',
        title: '第一章',
        chapterNumber: 1,
        charCount: 4,
        processedHtml: '<p>正文一段</p>',
        stylesheetRefs: chapterRefs,
      );

      final row = await db.select(db.cachedReaderChapters).getSingle();
      expect(
        row.processedHtml,
        isNot(contains('margin-bottom')),
        reason: '正文里不能再有样式表：那正是逐章重复携带的那一份',
      );
      expect(row.stylesheetRefsJson, isNot(contains('margin-bottom')));

      final loaded = await localStore.loadChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/chapter1.xhtml',
      );
      expect(loaded?.html, '<p>正文一段</p>');
      expect(loaded?.refs, chapterRefs);
    });

    test('空次序读回来是空表，不是一章解析失败', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);
      await localStore.saveChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/chapter2.xhtml',
        title: '第二章',
        chapterNumber: 2,
        charCount: 4,
        processedHtml: '<p>正文一段</p>',
        stylesheetRefs: const [],
      );

      final loaded = await localStore.loadChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/chapter2.xhtml',
      );
      expect(loaded?.refs, isEmpty);
      expect(buildChapterStylesheetCss(pool, loaded!.refs), isEmpty);
    });
  });

  group('书级样式表池', () {
    test('单列补写，不动元数据的其余字段', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);
      await seedBookMeta(localStore);

      expect(
        await localStore.saveStylesheetPool(itemId: 'book-1', pool: pool),
        isTrue,
      );

      final row = await db.select(db.cachedReaderBooks).getSingle();
      expect(row.title, '测试书');
      expect(row.chaptersJson, '[]');
      expect(row.cacheVersion, 'v1');
      expect(await localStore.loadStylesheetPool('book-1'), pool);
    });

    test('元数据行还没落地时写不进去，交回调用方重试', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);

      expect(
        await localStore.saveStylesheetPool(itemId: 'missing', pool: pool),
        isFalse,
        reason: '整行覆盖会连带重写清单与元数据，那里手上的信息不足以重建这一行',
      );
      expect(await localStore.loadStylesheetPool('missing'), isEmpty);
    });

    test('池按引用它的次序拼，不是按池自己的插入序', () {
      // 池的键序来自 manifest（a→b），本章 link 是 b→a：拿前者当后者会让
      // 同特异度冲突规则的胜负反掉，西遊記整本书就是这个形态。
      expect(
        buildChapterStylesheetCss(pool, chapterRefs),
        '\n${pool['OEBPS/styles/b.css']}\n${pool['OEBPS/styles/a.css']}',
      );
      expect(
        buildChapterStylesheetCss(pool, pool.keys.toList()),
        isNot(buildChapterStylesheetCss(pool, chapterRefs)),
      );
    });

    test('引用了池里没有的路径只跳过那一张，不挪位后面的次序', () {
      expect(
        buildChapterStylesheetCss(pool, const ['missing.css', ...chapterRefs]),
        buildChapterStylesheetCss(pool, chapterRefs),
      );
    });

    test('空池配非空次序是合法降级：拼出空串而不是抛', () {
      expect(buildChapterStylesheetCss(const {}, chapterRefs), isEmpty);
      final blocks = parseBlocks(cleanBody, css: '');
      expect(onlyParagraph(blocks).style, isNull);
    });

    test('空池不写，避免每次 ingest 都重盖一次', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);
      await seedBookMeta(localStore);

      expect(
        await localStore.saveStylesheetPool(itemId: 'book-1', pool: const {}),
        isFalse,
      );
      expect(await localStore.loadStylesheetPool('book-1'), isEmpty);
    });

    test('章节被清扫后池一起回收，不留没人读的孤儿', () async {
      // 池只在章节 ingest 时写、只在某章带着次序引用时被读。章节行没了它还留着，
      // 就是每本读过的书最坏 256KB 的死数据。
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);
      await seedBookMeta(localStore);
      await localStore.saveStylesheetPool(itemId: 'book-1', pool: pool);
      await localStore.saveChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/chapter1.xhtml',
        title: '第一章',
        chapterNumber: 1,
        charCount: 4,
        processedHtml: '<p>正文一段</p>',
        stylesheetRefs: chapterRefs,
      );

      await localStore.cleanOldChapters(maxAgeDays: -30);

      expect(
        await localStore.loadChapterContent(
          itemId: 'book-1',
          contentPath: 'OEBPS/chapter1.xhtml',
        ),
        isNull,
      );
      expect(await localStore.loadStylesheetPool('book-1'), isEmpty);
      final meta = await localStore.loadBookMeta('book-1');
      expect(meta?['title'], '测试书', reason: '章节清扫不带走书目元数据');
    });

    test('还有章节行时不动池', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localStore = store(db);
      await seedBookMeta(localStore);
      await localStore.saveStylesheetPool(itemId: 'book-1', pool: pool);
      await localStore.saveChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/chapter1.xhtml',
        title: '第一章',
        chapterNumber: 1,
        charCount: 4,
        processedHtml: '<p>正文一段</p>',
        stylesheetRefs: chapterRefs,
      );

      await localStore.cleanOldChapters();

      expect(await localStore.loadStylesheetPool('book-1'), pool);
    });
  });

  group('与旧载体的等价性', () {
    test('同一章按池 + 次序解析，与按内联载体解析得到同一份书样式', () {
      final css = buildChapterStylesheetCss(pool, chapterRefs);
      final viaCarrier = onlyParagraph(parseBlocks(carrierBody(css)));
      final viaPool = onlyParagraph(parseBlocks(cleanBody, css: css));

      // a.css 排在最后，同特异度必须它胜出：1em。次序一反就变成 3em。
      expect(spacingOf(viaCarrier), closeTo(1.0, 0.001));
      expect(spacingOf(viaPool), spacingOf(viaCarrier));

      final byManifestOrder = onlyParagraph(
        parseBlocks(
          cleanBody,
          css: buildChapterStylesheetCss(pool, pool.keys.toList()),
        ),
      );
      expect(
        byManifestOrder.style?.paragraphSpacingScale,
        closeTo(3.0, 0.001),
        reason: '按 manifest 序拼一份给全书会把胜负翻过来，所以次序必须按章存',
      );
    });

    test('正文里没有样式表时，纯文本侧不会被 CSS 撑大', () {
      final content = ReaderChapterContent(
        title: '第一章',
        content: cleanBody,
        stylesheetCss: buildChapterStylesheetCss(pool, chapterRefs),
      );
      expect(content.content, isNot(contains('margin-bottom')));
      expect(content.stylesheetCss, contains('margin-bottom'));
    });
  });
}
