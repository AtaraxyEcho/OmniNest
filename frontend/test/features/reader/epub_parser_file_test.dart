import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/epub_parser_service.dart';

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

  test('从文件流解析元数据和章节并释放底层句柄', () async {
    final file = File('${directory.path}/valid.epub');
    await _writeEpub(
      file,
      '<html><body><h1>第一章</h1><p>流式章节正文</p></body></html>',
    );
    final service = EpubParserService();

    expect(service.isFixedLayoutFile(file.path), isFalse);
    final book = await service.parseMetadataFile(file.path);
    final lease = await service.acquireLease();
    final chapter = await service.parseChapterFile(
      file.path,
      book.chapters.single.contentPath!,
    );
    lease.release();

    expect(book.title, '流式测试');
    expect(book.author, '测试作者');
    expect(book.chapters.single.title, '第一章');
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

    await expectLater(
      service.parseMetadataFile(file.path),
      throwsA(isA<EpubParseLimitException>()),
    );
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
    final chapter = await service.parseChapterFile(
      file.path,
      'OEBPS/chapter1.xhtml',
    );
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
    final chapter = await service.parseChapterFile(file.path, '第一章.xhtml');
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
    final encoded = await service.parseChapterFile(
      file.path,
      Uri.encodeComponent('OEBPS/chapter1.xhtml'),
    );
    final plain = await service.parseChapterFile(
      file.path,
      'OEBPS/chapter1.xhtml',
    );
    lease.release();
    service.releaseArchive();

    expect(encoded, contains('百分号编码正文'));
    expect(plain, contains('百分号编码正文'));
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

void _addText(Archive archive, String path, String value) {
  final bytes = utf8.encode(value);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}
