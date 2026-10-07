import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/reader_content_preprocessor.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';

void main() {
  setUp(() {
    ReaderImageCache.init(const DisabledReaderImageRepository());
  });

  test('超过单章数量上限的图片降级为不加载，章节仍可读出', () async {
    ReaderImageCache.init(_MemoryReaderImageRepository());
    final archive = Archive();
    final html = StringBuffer('<body>');
    for (var index = 0; index <= 100; index++) {
      final path = 'images/$index.png';
      final bytes = utf8.encode('image-$index');
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
      html.write('<img src="../$path">');
    }
    html.write('</body>');

    final result = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item-1',
      xhtml: html.toString(),
      archive: archive,
      contentPath: 'text/chapter.xhtml',
    );

    expect(result, isNotEmpty);
    expect('<img'.allMatches(result).length, 101, reason: '图片标签不得被吞掉');
    expect('src="__IMG_'.allMatches(result).length, 101);
  });

  test('data-src 懒加载属性不被改写', () async {
    ReaderImageCache.init(_MemoryReaderImageRepository());
    final archive = Archive();
    final bytes = utf8.encode('real-image');
    archive.addFile(ArchiveFile('images/real.png', bytes.length, bytes));
    archive.addFile(ArchiveFile('images/ph.png', bytes.length, bytes));

    final result = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item-lazy',
      xhtml:
          '<body><img data-src="images/real.png" src="images/ph.png"></body>',
      archive: archive,
      contentPath: 'text/chapter.xhtml',
    );

    // 旧写法 `[^>]*src=` 会吃到 data-src 的 "src="，把占位符写进 data-src，
    // 真正的 src 保持相对路径而加载不到图片。
    expect(result, contains('data-src="images/real.png"'));
    expect(result, contains('src="__IMG_'));
  });

  test('没有 src 属性的懒加载 img 不被破坏', () async {
    ReaderImageCache.init(_MemoryReaderImageRepository());

    const input = '<body><img data-src="images/x.png"></body>';
    final result = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item-no-src',
      xhtml: input,
      archive: Archive(),
      contentPath: 'text/chapter.xhtml',
    );

    expect(result, contains('<img data-src="images/x.png">'));
    expect(result, isNot(contains('__IMG_')));
  });

  test('不同写法指向同一归档条目时只落盘一次', () async {
    final repository = _MemoryReaderImageRepository();
    ReaderImageCache.init(repository);
    final archive = Archive();
    final bytes = utf8.encode('shared-image');
    archive.addFile(ArchiveFile('images/Art.PNG', bytes.length, bytes));

    final result = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item-dedupe',
      xhtml:
          '<body><img src="images/Art.PNG"><img src="images/art.png"></body>',
      archive: archive,
      contentPath: 'text/chapter.xhtml',
    );

    expect(result.contains('__IMG_'), isTrue);
    expect(repository.images.length, 1, reason: '同一条目重复解压会重复计入容量');
  });

  test('内嵌 Base64 图片写入缓存并保留轻量占位符', () async {
    final repository = _MemoryReaderImageRepository();
    ReaderImageCache.init(repository);
    final encoded = base64Encode(<int>[0x89, 0x50, 0x4e, 0x47]);

    final html = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item-inline',
      xhtml: '<body><img src="data:image/png;base64,$encoded"></body>',
      contentPath: 'text/chapter.xhtml',
      archive: Archive(),
    );

    expect(html, contains('src="__IMG_inline/'));
    expect(html, isNot(contains('data:image/png;base64')));
    expect(repository.images.values.single, <int>[0x89, 0x50, 0x4e, 0x47]);
  });
}

class _MemoryReaderImageRepository implements ReaderImageRepository {
  final Map<String, Uint8List> images = {};

  @override
  Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {
    images['$itemId:$imagePath'] = bytes;
  }

  @override
  Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  }) async => images['$itemId:$imagePath'];

  @override
  Future<void> deleteForItem(String itemId) async {
    images.removeWhere((key, _) => key.startsWith('$itemId:'));
  }

  @override
  Future<void> cleanOld({int maxAgeDays = 30}) async {}

  @override
  Future<void> clearAll() async => images.clear();
}
