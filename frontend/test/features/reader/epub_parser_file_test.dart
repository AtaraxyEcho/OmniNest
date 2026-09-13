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
    final chapter = await service.parseChapterFile(
      file.path,
      book.chapters.single.contentPath!,
    );

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

    final chapter = await service.parseChapterFile(
      file.path,
      'OEBPS/chapter1.xhtml',
    );

    expect(chapter, contains('服务端路径正文'));
    service.releaseArchive();
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
