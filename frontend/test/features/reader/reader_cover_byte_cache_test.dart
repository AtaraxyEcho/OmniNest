import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';

/// 阅读封面字节 LRU：跨组件卸载复用字节，避免焦点切换重复请求认证接口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List bytes(int mark) => Uint8List.fromList([mark]);

  tearDown(() {
    for (var i = 0; i < 300; i++) {
      ReaderCoverByteCache.remove('item-$i');
    }
  });

  test('写入后可读取，未写入返回 null', () {
    ReaderCoverByteCache.write('item-a', bytes(1));

    expect(ReaderCoverByteCache.read('item-a'), bytes(1));
    expect(ReaderCoverByteCache.read('item-missing'), isNull);
  });

  test('容量 64 封顶，最早条目被逐出', () {
    for (var i = 0; i < 64; i++) {
      ReaderCoverByteCache.write('item-$i', bytes(i));
    }
    ReaderCoverByteCache.write('item-64', bytes(64));

    expect(ReaderCoverByteCache.read('item-0'), isNull);
    expect(ReaderCoverByteCache.read('item-63'), bytes(63));
    expect(ReaderCoverByteCache.read('item-64'), bytes(64));
  });

  test('读取会刷新热度，热点条目不被逐出', () {
    for (var i = 0; i < 64; i++) {
      ReaderCoverByteCache.write('item-$i', bytes(i));
    }
    // item-0 变为热点后，继续写入 1 条应逐出的是 item-1。
    expect(ReaderCoverByteCache.read('item-0'), bytes(0));
    ReaderCoverByteCache.write('item-64', bytes(64));

    expect(ReaderCoverByteCache.read('item-0'), bytes(0));
    expect(ReaderCoverByteCache.read('item-1'), isNull);
  });

  test('remove 后失效（封面上传后旧字节必须作废）', () {
    ReaderCoverByteCache.write('item-a', bytes(1));
    ReaderCoverByteCache.remove('item-a');

    expect(ReaderCoverByteCache.read('item-a'), isNull);
  });
}
