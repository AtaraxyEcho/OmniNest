import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/utils/yield_to_event_loop.dart';

void main() {
  test('yieldToEventLoop 会异步让出', () async {
    var tick = 0;
    Future<void>.microtask(() => tick = 1);
    expect(tick, 0);
    await yieldToEventLoop();
    expect(tick, 1);
  });

  test('runWithEventLoopYield 返回工作结果且不吞错', () async {
    final value = await runWithEventLoopYield(() => 42);
    expect(value, 42);
    await expectLater(
      () => runWithEventLoopYield<int>(() => throw StateError('x')),
      throwsStateError,
    );
  });

  test('forEachChunkYielding 按间隔让出并处理全部分片', () async {
    final seen = <int>[];
    await forEachChunkYielding(
      List.generate(20, (i) => [i]),
      (chunk) => seen.add(chunk.first),
      yieldEvery: 5,
    );
    expect(seen, List.generate(20, (i) => i));
  });
}
