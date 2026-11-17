import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 测试进程在 `test/flutter_test_config.dart` 里关闭有界等待。
///
/// fake async 不会推进真实平台通道，计时器只会挂在队列里被判为 pending
/// timer；关闭后走原始 Future，生产路径的超时降级不受影响。
@visibleForTesting
bool boundedAsyncStepsEnabled = true;

/// 给可能悬挂的异步步骤（安全存储读写、平台通道探测）加时间预算。
///
/// 不直接用 [Future.timeout]：它的计时器只在原 Future 完成时才会取消，而
/// 启动期正是要防「通道调用永不返回」，所以那条路径上计时器必然一直挂着。
/// widget 测试运行在 fake async 下，未触发的计时器会在测试结束时被判为
/// pending timer。这里把计时器同时挂到 provider 的 onDispose，widget 树卸载
/// 时一并取消；超时仍抛 [TimeoutException]，上层降级逻辑不变。
Future<T> boundedAsyncStep<T>(Ref ref, Future<T> work, Duration budget) {
  if (!boundedAsyncStepsEnabled) return work;
  final completer = Completer<T>.sync();
  final timer = Timer(budget, () {
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('平台通道步骤超时', budget));
    }
  });
  ref.onDispose(timer.cancel);
  work.then(
    (value) {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.complete(value);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.completeError(error, stackTrace);
      }
    },
  );
  return completer.future;
}
