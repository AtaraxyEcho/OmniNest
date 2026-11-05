import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';

void main() {
  tearDown(clearFileDownloadUrlCaches);

  test('下载地址缓存超过上限时淘汰最久未使用条目', () {
    final at = DateTime.now();
    for (var i = 0; i < 256; i++) {
      prewarmDownloadUrl('file-$i', 'https://example.test/$i', at);
    }
    // 命中即视为一次使用：file-0 变成最新，下一次淘汰应轮到 file-1。
    expect(debugHasCachedDownloadUrl('file-0'), isTrue);
    prewarmDownloadUrl('file-256', 'https://example.test/256', at);

    expect(debugHasCachedDownloadUrl('file-0'), isTrue);
    expect(debugHasCachedDownloadUrl('file-1'), isFalse);
    expect(debugHasCachedDownloadUrl('file-256'), isTrue);
  });

  test('清空缓存后不再命中任何下载地址', () {
    prewarmDownloadUrl('file-a', 'https://example.test/a', DateTime.now());
    expect(debugHasCachedDownloadUrl('file-a'), isTrue);

    clearFileDownloadUrlCaches();

    expect(debugHasCachedDownloadUrl('file-a'), isFalse);
  });
}
