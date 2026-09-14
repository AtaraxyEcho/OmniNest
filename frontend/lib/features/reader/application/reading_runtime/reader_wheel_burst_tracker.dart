import 'dart:async';

import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';

/// 滚轮/触控板 burst 跟踪（方案 §30/§31）。
///
/// burst 内复用同一事务；空闲 [idleTimeout] 无新信号后触发超时回调
/// （进入 SETTLING 一次提交）。时钟经 §109 抽象注入，测试环境用 Fake
/// 稳定验证超时与竞态；高频小 delta（触控板 100+ 事件）始终属于同一
/// burst，不产生事务抖动。
class ReaderWheelBurstTracker {
  ReaderWheelBurstTracker({
    required this.clock,
    this.idleTimeout = const Duration(milliseconds: 200),
  });

  final ReaderRuntimeClock clock;

  final Duration idleTimeout;

  Timer? _timer;

  /// 当前 burst 已收集的信号数（观测 §116 无事务抖动）。
  int signalCount = 0;

  /// burst 是否仍存活（超时窗口未到期）。
  bool get isBurstOngoing => _timer?.isActive ?? false;

  /// 输入信号：刷新存续窗口；窗口到期后回调 [onTimeout] 恰好一次。
  void onSignal({required void Function() onTimeout}) {
    _timer?.cancel();
    _timer = clock.schedule(idleTimeout, () {
      _timer = null;
      signalCount = 0;
      onTimeout();
    });
    signalCount++;
  }

  /// 取消当前 burst（页面离开或事务被其他来源接管时调用）。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    signalCount = 0;
  }
}
