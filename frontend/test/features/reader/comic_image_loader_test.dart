import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/reader/data/comic_image_provider.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';

class _MockReaderApi extends Mock implements ReaderApi {}

void main() {
  late _MockReaderApi api;

  setUp(() {
    api = _MockReaderApi();
  });

  test('缓存命中会更新 LRU 访问顺序', () async {
    when(() => api.getPageImage(any())).thenAnswer(
      (invocation) async => Uint8List.fromList(
        List<int>.filled(3, invocation.positionalArguments.first.hashCode),
      ),
    );
    final loader = ComicImageLoader(api, maxCacheBytes: 6);

    await loader.getImage('comic', 'a.jpg', pageId: 'a');
    await loader.getImage('comic', 'b.jpg', pageId: 'b');
    await loader.getImage('comic', 'a.jpg', pageId: 'a');
    await loader.getImage('comic', 'c.jpg', pageId: 'c');
    await loader.getImage('comic', 'a.jpg', pageId: 'a');
    await loader.getImage('comic', 'b.jpg', pageId: 'b');

    verify(() => api.getPageImage('a')).called(1);
    verify(() => api.getPageImage('b')).called(2);
    verify(() => api.getPageImage('c')).called(1);
  });

  test('预加载会跳过已缓存的复合页面键', () async {
    when(
      () => api.getPageImage('page-1'),
    ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    final loader = ComicImageLoader(api);
    const page = ComicPage(
      id: 'page-1',
      sourceId: 'source-1',
      pageIndex: 0,
      sourcePath: 'page-1.jpg',
    );

    await loader.getImage('comic-1', page.sourcePath, pageId: page.id);
    await loader.preloadImages('comic-1', const [page]);

    verify(() => api.getPageImage('page-1')).called(1);
  });

  test('同一页面的并发请求只访问一次 API', () async {
    final response = Completer<Uint8List>();
    when(() => api.getPageImage('page-1')).thenAnswer((_) => response.future);
    final loader = ComicImageLoader(api);

    final first = loader.getImage('comic-1', 'page.jpg', pageId: 'page-1');
    final second = loader.getImage('comic-1', 'page.jpg', pageId: 'page-1');
    verify(() => api.getPageImage('page-1')).called(1);

    response.complete(Uint8List.fromList([1, 2, 3]));

    expect(await first, orderedEquals([1, 2, 3]));
    expect(await second, orderedEquals([1, 2, 3]));
  });

  test('条目失效不会清除同前缀漫画的缓存', () async {
    when(() => api.getPageImage(any())).thenAnswer(
      (invocation) async =>
          Uint8List.fromList([invocation.positionalArguments.first.hashCode]),
    );
    final loader = ComicImageLoader(api);

    await loader.getImage('comic-1', 'a.jpg', pageId: 'a');
    await loader.getImage('comic-10', 'b.jpg', pageId: 'b');
    loader.invalidate('comic-1');
    await loader.getImage('comic-10', 'b.jpg', pageId: 'b');
    await loader.getImage('comic-1', 'a.jpg', pageId: 'a');

    verify(() => api.getPageImage('a')).called(2);
    verify(() => api.getPageImage('b')).called(1);
  });

  test('失效期间完成的请求不会重新写回缓存', () async {
    final firstResponse = Completer<Uint8List>();
    when(() => api.getPageImage('page-1')).thenAnswer((_) {
      if (!firstResponse.isCompleted) {
        return firstResponse.future;
      }
      return Future<Uint8List>.value(Uint8List.fromList([4, 5, 6]));
    });
    final loader = ComicImageLoader(api);

    final first = loader.getImage('comic-1', 'page-1.jpg', pageId: 'page-1');
    loader.invalidate('comic-1');
    firstResponse.complete(Uint8List.fromList([1, 2, 3]));
    await first;
    await loader.getImage('comic-1', 'page-1.jpg', pageId: 'page-1');

    verify(() => api.getPageImage('page-1')).called(2);
  });

  test('超预算单图不会淘汰已有缓存', () async {
    when(
      () => api.getPageImage('small'),
    ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    when(
      () => api.getPageImage('large'),
    ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]));
    final loader = ComicImageLoader(api, maxCacheBytes: 6);

    await loader.getImage('comic-1', 'small.jpg', pageId: 'small');
    await loader.getImage('comic-1', 'large.jpg', pageId: 'large');
    await loader.getImage('comic-1', 'small.jpg', pageId: 'small');

    verify(() => api.getPageImage('small')).called(1);
    verify(() => api.getPageImage('large')).called(1);
  });
}
