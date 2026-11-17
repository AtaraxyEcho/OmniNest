import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/epub_parser_service.dart';
import 'package:omninest/features/reader/data/reader_content_preprocessor.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('epub-stream-test-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('条目选取按段边界锚定，尾部相同的杂项文件抢不了路径', () async {
    // 清单里的章节缺了一层前缀（真实条目是 `text/chapter1.xhtml`），而归档里先放了
    // 一个叫 `pter1.xhtml` 的杂项文件。旧兜底用裸 endsWith：目标串正好以它结尾，
    // 于是章节内容取自杂项文件，读者看到张冠李戴的一章，还不报错。
    final file = File('${directory.path}/decoy.epub');
    final archive = Archive();
    _addText(archive, 'mimetype', 'application/epub+zip');
    _addText(
      archive,
      'META-INF/container.xml',
      '<?xml version="1.0"?>'
          '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
          '</container>',
    );
    _addText(
      archive,
      'OEBPS/content.opf',
      '<?xml version="1.0"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1">'
          '<dc:title>错配测试</dc:title></metadata>'
          '<manifest><item id="c1" href="text/chapter1.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="c1"/></spine></package>',
    );
    _addText(archive, 'pter1.xhtml', '<html><body><p>杂项文件</p></body></html>');
    _addText(
      archive,
      'text/chapter1.xhtml',
      '<html><body><p>真章节</p></body></html>',
    );
    await file.writeAsBytes(ZipEncoder().encode(archive));
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter =
        (await service.parseChapterFile(
          file.path,
          'OEBPS/text/chapter1.xhtml',
        ))?.xhtml;
    lease.release();
    service.releaseArchive();

    expect(chapter, contains('真章节'));
    expect(chapter, isNot(contains('杂项文件')));
  });

  test('解析章节后释放归档可关闭文件句柄', () async {
    final file = File('${directory.path}/valid.epub');
    await _writeEpub(
      file,
      '<html><body><h1>第一章</h1><p>流式章节正文</p></body></html>',
    );
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter =
        (await service.parseChapterFile(
          file.path,
          'OEBPS/chapter1.xhtml',
        ))?.xhtml;
    lease.release();

    expect(chapter, contains('流式章节正文'));

    service.releaseArchive();
    await file.delete();
    expect(await file.exists(), isFalse);
  });

  test('文件流解析拒绝超过章节容量限制的 EPUB', () async {
    final file = File('${directory.path}/oversized.epub');
    final oversized = 'a' * (8 * 1024 * 1024 + 1);
    await _writeEpub(file, oversized);
    final service = EpubParserService();

    final lease = await service.acquireLease();
    await expectLater(
      service.parseChapterFile(file.path, 'OEBPS/chapter1.xhtml'),
      throwsA(isA<EpubParseLimitException>()),
    );
    lease.release();
    service.releaseArchive();
  });

  test('文件流解析兼容服务端返回的归档根路径', () async {
    final file = File('${directory.path}/server-path.epub');
    await _writeEpub(
      file,
      '<html><body><h1>第一章</h1><p>服务端路径正文</p></body></html>',
    );
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter =
        (await service.parseChapterFile(
          file.path,
          'OEBPS/chapter1.xhtml',
        ))?.xhtml;
    lease.release();

    expect(chapter, contains('服务端路径正文'));
    service.releaseArchive();
  });

  test('租约互斥：预取必须等当前章归还后才能使用归档', () async {
    final file = File('${directory.path}/lease.epub');
    await _writeEpub(file, '<html><body><p>租约正文</p></body></html>');
    final service = EpubParserService();

    final first = await service.acquireLease();
    var secondGranted = false;
    final pending = service.acquireLease().then((lease) {
      secondGranted = true;
      return lease;
    });

    await Future<void>.delayed(Duration.zero);
    expect(secondGranted, isFalse, reason: '同一文件句柄不允许并发读取');

    first.release();
    final second = await pending;
    expect(secondGranted, isTrue);
    second.release();
    service.releaseArchive();
  });

  test('持有租约期间的释放请求延后到归还之后', () async {
    final file = File('${directory.path}/deferred.epub');
    await _writeEpub(file, '<html><body><p>延后释放正文</p></body></html>');
    final service = EpubParserService();

    final lease = await service.acquireLease();
    await service.parseChapterFile(file.path, 'OEBPS/chapter1.xhtml');
    expect(service.cachedArchive, isNotNull);

    // 模拟 invalidateBookCache 在当前章使用归档期间发起释放。
    service.releaseArchive();
    expect(service.cachedArchive, isNotNull, reason: '不能中途抽走正在使用的归档');

    lease.release();
    expect(service.cachedArchive, isNull, reason: '归还后才真正释放');
  });

  test('同一本书的连续章节复用同一个归档实例', () async {
    final file = File('${directory.path}/reuse.epub');
    await _writeEpub(file, '<html><body><p>复用正文</p></body></html>');
    final service = EpubParserService();

    final lease = await service.acquireLease();
    await service.parseChapterFile(file.path, 'OEBPS/chapter1.xhtml');
    final firstArchive = service.cachedArchive;
    await service.parseChapterFile(file.path, 'OEBPS/chapter1.xhtml');

    expect(firstArchive, isNotNull);
    expect(service.cachedArchive, same(firstArchive), reason: '不应重解压整本 ZIP');
    lease.release();
    service.releaseArchive();
  });

  test('GBK 字节命名的条目能匹配到 UTF-8 解码的章节路径', () async {
    // 旧中文打包工具的 ZIP 条目名是 GBK 字节；archive 对非 UTF-8 名逐字节回退成
    // Latin-1，字形错乱，与按 GBK 正确解码的 href 对不上，章节因此静默变 null。
    final file = File('${directory.path}/gbk-name.epub');
    final gbkChapterName = latin1.decode(const [
      0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2, // 「第一章」的 GBK 字节
    ]);
    final archive = Archive();
    _addText(archive, 'mimetype', 'application/epub+zip');
    _addText(
      archive,
      'META-INF/container.xml',
      '<?xml version="1.0"?>'
          '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="content.opf"/></rootfiles>'
          '</container>',
    );
    _addText(
      archive,
      '$gbkChapterName.xhtml',
      '<html><body><p>GBK 条目名正文</p></body></html>',
    );
    await file.writeAsBytes(ZipEncoder().encode(archive));
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter =
        (await service.parseChapterFile(file.path, '第一章.xhtml'))?.xhtml;
    lease.release();
    service.releaseArchive();

    expect(chapter, contains('GBK 条目名正文'));
  });

  test('百分号编码的中文章节路径可以解析', () async {
    final file = File('${directory.path}/pct-name.epub');
    await _writeEpub(file, '<html><body><p>百分号编码正文</p></body></html>');
    final service = EpubParserService();

    final lease = await service.acquireLease();
    // Uri.decodeComponent 对含裸非 ASCII 的路径会抛 ArgumentError，
    // 服务端下发的 contentPath 正是这种形态；此处同时覆盖编码与未编码两种输入。
    final encoded =
        (await service.parseChapterFile(
          file.path,
          Uri.encodeComponent('OEBPS/chapter1.xhtml'),
        ))?.xhtml;
    final plain =
        (await service.parseChapterFile(
          file.path,
          'OEBPS/chapter1.xhtml',
        ))?.xhtml;
    lease.release();
    service.releaseArchive();

    expect(encoded, contains('百分号编码正文'));
    expect(plain, contains('百分号编码正文'));
  });

  test('样式表与正文分开返回：正文里不再有那份 `<style>` 载体', () async {
    final file = File('${directory.path}/with-css.epub');
    await _writeEpubWithCss(
      file,
      '<html><body><p class="first">带样式正文</p></body></html>',
    );
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter = await service.parseChapterFile(file.path, 'chapter1.xhtml');
    // 同一本书的后续章节复用同一份样式表缓存，不再重复解归档。
    final second = await service.parseChapterFile(file.path, 'chapter1.xhtml');
    lease.release();
    service.releaseArchive();

    expect(chapter, isNotNull);
    expect(chapter!.xhtml, isNot(contains('<style')));
    // 本章 head 里没有 link：次序退回 manifest，指向池里那张表。
    expect(chapter.stylesheetRefs, ['OEBPS/styles/base.css']);
    expect(
      chapter.stylesheetPool['OEBPS/styles/base.css'],
      'p.first { text-indent: 0em; margin-bottom: 2em }',
    );
    expect(second?.stylesheetRefs, chapter.stylesheetRefs);

    final css = buildChapterStylesheetCss(
      chapter.stylesheetPool,
      chapter.stylesheetRefs,
    );
    final preprocessed = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item',
      xhtml: chapter.xhtml,
    );
    final blocks = parseBlocks(preprocessed.html, css: css);
    final paragraph = blocks.whereType<ParagraphBlock>().single;
    expect(paragraph.style?.firstLineIndentChars, 0);
    expect(paragraph.style?.paragraphSpacingScale, closeTo(2.0, 0.001));
    // 纯文本侧不能把 CSS 源码念出来：TTS 与章内检索都取这一份。
    expect(stripHtml(preprocessed.html), '带样式正文');
  });

  test('样式表的层叠次序取本章 head 的 link 顺序，不是 manifest 顺序', () async {
    // 真书证据：西遊記 content.opf 的 item 顺序是 pgepub→0→1，而每章 head 的
    // <link> 是 0→1→pgepub，完全倒置。同特异度的冲突规则（两边都写 p）胜负会反。
    final file = File('${directory.path}/link-order.epub');
    await _writeEpubWithLinkOrderCss(
      file,
      '<html><head>'
      '<link href="styles/book.css" rel="stylesheet" type="text/css"/>'
      '<link href="styles/public.css" rel="stylesheet" type="text/css"/>'
      '</head><body><p>顺序正文</p></body></html>',
    );
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter = await service.parseChapterFile(file.path, 'chapter1.xhtml');
    lease.release();
    service.releaseArchive();

    expect(chapter, isNotNull);
    expect(chapter!.stylesheetRefs, [
      'OEBPS/styles/book.css',
      'OEBPS/styles/public.css',
    ], reason: '次序必须按章存下来，池自己的插入序是 manifest 序');
    final paragraph =
        parseBlocks(
          chapter.xhtml,
          css: buildChapterStylesheetCss(
            chapter.stylesheetPool,
            chapter.stylesheetRefs,
          ),
        ).whereType<ParagraphBlock>().single;
    expect(
      paragraph.style?.paragraphSpacingScale,
      closeTo(3.0, 0.001),
      reason: 'link 里 public.css 写在 book.css 之后，同特异度必须后者胜出',
    );

    // 反证：拿池的插入序（manifest 序）拼一份给全书，同一条规则就翻了个。
    expect(
      parseBlocks(
        chapter.xhtml,
        css: buildChapterStylesheetCss(
          chapter.stylesheetPool,
          chapter.stylesheetPool.keys.toList(),
        ),
      ).whereType<ParagraphBlock>().single.style?.paragraphSpacingScale,
      closeTo(1.0, 0.001),
    );
  });

  test('没有样式表的书返回原样正文', () async {
    final file = File('${directory.path}/no-css.epub');
    await _writeEpub(file, '<html><body><p>无样式正文</p></body></html>');
    final service = EpubParserService();

    final lease = await service.acquireLease();
    final chapter = await service.parseChapterFile(file.path, 'chapter1.xhtml');
    lease.release();
    service.releaseArchive();

    expect(chapter, isNotNull);
    expect(chapter!.xhtml, contains('无样式正文'));
    expect(chapter.stylesheetRefs, isEmpty);
    expect(chapter.stylesheetPool, isEmpty);
  });
}

Future<void> _writeEpub(File file, String chapterContent) async {
  final archive = Archive();
  _addText(archive, 'mimetype', 'application/epub+zip');
  _addText(
    archive,
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
        '</container>',
  );
  _addText(
    archive,
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>流式测试</dc:title><dc:creator>测试作者</dc:creator>'
        '</metadata>'
        '<manifest><item id="chapter-1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="chapter-1"/></spine>'
        '</package>',
  );
  _addText(archive, 'OEBPS/chapter1.xhtml', chapterContent);
  await file.writeAsBytes(ZipEncoder().encode(archive));
}

Future<void> _writeEpubWithCss(File file, String chapterContent) async {
  final archive = Archive();
  _addText(archive, 'mimetype', 'application/epub+zip');
  _addText(
    archive,
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
        '</container>',
  );
  _addText(
    archive,
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>带样式测试</dc:title></metadata>'
        '<manifest>'
        '<item id="chapter-1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '<item id="base" href="styles/base.css" media-type="text/css"/>'
        '</manifest>'
        '<spine><itemref idref="chapter-1"/></spine>'
        '</package>',
  );
  _addText(
    archive,
    'OEBPS/styles/base.css',
    'p.first { text-indent: 0em; margin-bottom: 2em }',
  );
  _addText(archive, 'OEBPS/chapter1.xhtml', chapterContent);
  await file.writeAsBytes(ZipEncoder().encode(archive));
}

Future<void> _writeEpubWithLinkOrderCss(
  File file,
  String chapterContent,
) async {
  final archive = Archive();
  _addText(archive, 'mimetype', 'application/epub+zip');
  _addText(
    archive,
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
        '</container>',
  );
  // manifest 里 public.css 排在 book.css 之后；本章 head 的 link 顺序正好相反。
  _addText(
    archive,
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>次序测试</dc:title></metadata>'
        '<manifest>'
        '<item id="chapter-1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '<item id="public" href="styles/public.css" media-type="text/css"/>'
        '<item id="book" href="styles/book.css" media-type="text/css"/>'
        '</manifest>'
        '<spine><itemref idref="chapter-1"/></spine>'
        '</package>',
  );
  _addText(archive, 'OEBPS/styles/book.css', 'p { margin-bottom: 1em }');
  _addText(archive, 'OEBPS/styles/public.css', 'p { margin-bottom: 3em }');
  _addText(archive, 'OEBPS/chapter1.xhtml', chapterContent);
  await file.writeAsBytes(ZipEncoder().encode(archive));
}

void _addText(Archive archive, String path, String value) {
  final bytes = utf8.encode(value);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}
