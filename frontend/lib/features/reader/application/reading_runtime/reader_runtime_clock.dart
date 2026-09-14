import 'dart:async';

import 'dart:ui' show VoidCallback;

/// Runtime 时钟（方案 §109）：把 DateTime.now() / Timer 从状态机中抽象
/// 出来，测试环境可注入 Fake 稳定验证 Wheel 超时、Restore 超时、Settling
/// 与防抖竞态。
abstract interface class ReaderRuntimeClock {
  DateTime get now;

  Timer schedule(Duration duration, VoidCallback callback);
}

/// 生产环境系统时钟。
class SystemReaderRuntimeClock implements ReaderRuntimeClock {
  const SystemReaderRuntimeClock();

  @override
  DateTime get now => DateTime.now();

  @override
  Timer schedule(Duration duration, VoidCallback callback) {
    return Timer(duration, callback);
  }
}
