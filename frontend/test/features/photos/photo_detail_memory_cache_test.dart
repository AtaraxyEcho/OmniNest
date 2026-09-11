import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';

PhotoItem _photo(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024),
  );
}

void main() {
  test('详情内存缓存写入、覆盖与容量淘汰', () {
    final cache = PhotoDetailMemoryCache(maxEntries: 2);
    cache.put(_photo('a'));
    cache.put(_photo('b'));
    expect(cache.get('a')?.id, 'a');
    expect(cache.get('b')?.id, 'b');

    cache.put(_photo('c'));
    expect(cache.get('a'), isNull, reason: '超容量后淘汰最旧条目');
    expect(cache.get('c')?.id, 'c');

    cache.put(_photo('b'));
    cache.put(_photo('d'));
    expect(cache.get('c'), isNull, reason: '重新写入的 b 保留为较新条目');
    expect(cache.get('b')?.id, 'b');
  });

  test('invalidate 后不再命中', () {
    final cache = PhotoDetailMemoryCache();
    cache.put(_photo('a'));
    cache.invalidate('a');
    expect(cache.get('a'), isNull);
  });
}
