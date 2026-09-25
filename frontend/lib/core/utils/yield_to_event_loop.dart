import 'dart:async';

/// 将控制权交还事件循环一拍，避免 Web 主线程被长同步计算独占。
///
/// Web 上 `compute` 会退化为同步执行；原生平台应优先 isolate。
/// 分片调用本函数可让出帧预算，保持滚动/手势可响应。
Future<void> yieldToEventLoop() {
  return Future<void>.delayed(Duration.zero);
}

/// 在重同步计算前后各让出一拍，并返回结果。
///
/// 适用于无法 isolate 的短-中等耗时计算；超大计算应继续分片。
Future<T> runWithEventLoopYield<T>(T Function() work) async {
  await yieldToEventLoop();
  final result = work();
  await yieldToEventLoop();
  return result;
}

/// 按固定长度分片处理 [chunks]，片间让出事件循环。
Future<void> forEachChunkYielding(
  Iterable<Iterable<int>> chunks,
  void Function(Iterable<int> chunk) onChunk, {
  int yieldEvery = 8,
}) async {
  var count = 0;
  for (final chunk in chunks) {
    onChunk(chunk);
    count++;
    if (count % yieldEvery == 0) {
      await yieldToEventLoop();
    }
  }
}
