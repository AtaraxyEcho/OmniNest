import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/local_book_cache.dart';

/// 换号时清理上一账号的会话明文临时文件。
///
/// 解密正文只落在 `*.plain.session.*` 这些临时文件里；正常情况下退出阅读会删掉
/// 自己那份，进程被杀时则留在磁盘上，必须由换号链路兜底清掉。
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader_plain_purge_');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('删除全部会话明文，保留缓存本体与其它文件', () async {
    final cache = File('${directory.path}/book-1.onf')
      ..writeAsStringSync('cipher');
    final first = File('${directory.path}/book-1.onf.plain.session.aaa')
      ..writeAsStringSync('plain');
    final second = File('${directory.path}/book-2.onf.plain.session.bbb')
      ..writeAsStringSync('plain');
    final part = File('${directory.path}/book-1.onf.plain.part')
      ..writeAsStringSync('partial');

    final removed = await LocalBookCache.purgePlainSessionFilesIn(directory);

    expect(removed, 2);
    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isFalse);
    expect(cache.existsSync(), isTrue, reason: '密文本体不是明文，不能被清掉');
    expect(part.existsSync(), isTrue, reason: '断点续传分片另有清理路径');
  });

  test('目录不存在时返回 0 而不是抛异常', () async {
    final missing = Directory('${directory.path}/not-created');

    expect(await LocalBookCache.purgePlainSessionFilesIn(missing), 0);
  });

  test('空账号不做任何事', () async {
    final file = File('${directory.path}/book-1.onf.plain.session.ccc')
      ..writeAsStringSync('plain');

    await LocalBookCache.purgePlainSessionFiles('');

    expect(file.existsSync(), isTrue);
  });
}
