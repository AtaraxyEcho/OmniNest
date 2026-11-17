import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';

/// 摘要：钉住 TXT 兜底解码服务的生命周期语义。
///
/// 该服务缓存整本解码文本，只在服务端派生正文不可用时用到。它是 autoDispose：
/// 没有监听者时每次 `read` 之后都会被回收，于是离线切章会反复重新解码整本书；
/// 阅读页必须像对待书籍句柄与 EPUB 服务那样监听它（D-39 的另一半）。
void main() {
  test('未被监听时，read 之后实例会被回收，下一章重新解码', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(txtParserServiceProvider);
    await pumpEventQueue();

    final second = container.read(txtParserServiceProvider);
    expect(
      identical(first, second),
      isFalse,
      reason: 'autoDispose 服务无人监听即回收，这正是必须 watch 它的原因',
    );
  });

  test('被监听期间跨章复用同一实例与整本解码缓存', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(
      txtParserServiceProvider,
      (previous, next) {},
    );

    final first = container.read(txtParserServiceProvider);
    await pumpEventQueue();
    final second = container.read(txtParserServiceProvider);
    expect(identical(first, second), isTrue);

    subscription.close();
    await pumpEventQueue();
    expect(
      identical(first, container.read(txtParserServiceProvider)),
      isFalse,
      reason: '页面离开后应随监听释放，不滞留整本文本',
    );
  });
}
