import 'dart:async';

import 'package:flutter/animation.dart' show Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_delegate.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_identity.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scroll_effect.dart';

/// 手动帧调度容器：测试显式驱动每一帧（B6 §7.5 编排单测范式）。
class _ManualFrameScheduler {
  final _pending = <void Function()>[];

  void schedule(void Function() callback) => _pending.add(callback);

  int get pendingCount => _pending.length;

  /// 驱动一帧；callback 内若再次排帧（重试循环），计数进入下一帧。
  void pump() {
    if (_pending.isEmpty) {
      return;
    }
    final callbacks = List<void Function()>.of(_pending);
    _pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// 驱动至多 [maxFrames] 帧，直到不再排帧。
  void settle({int maxFrames = 500}) {
    var frames = 0;
    while (_pending.isNotEmpty && frames < maxFrames) {
      pump();
      frames++;
    }
  }
}

class _FakeScrollEffect implements ReaderScrollEffect {
  @override
  bool hasClients = true;
  @override
  double maxScrollExtent = 4000;
  double offsetValue = 600;
  int jumpCount = 0;

  @override
  double get offset => offsetValue;

  @override
  void jumpTo(double offset) {
    jumpCount++;
    offsetValue = offset;
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    offsetValue = offset;
  }
}

class _FakeRestoreDelegate implements ReaderRestoreDelegate {
  /// target.charOffset → 目标窗口 offset；null 表示布局/数据未就绪。
  final resolveMap = <int, double?>{};

  DateTime? userScrollSinceHit;
  bool userScrolling = false;
  final settledTargets = <int>[];
  int maxScrollExtentOverride = 0;

  @override
  double? resolveRestoreOffset(ReaderPositionTarget target) =>
      resolveMap[target.charOffset];

  @override
  bool isUserScrollingSince(DateTime since) {
    userScrollSinceHit = since;
    return userScrolling;
  }

  @override
  void onRestoreSettled(ReaderPositionTarget target) {
    settledTargets.add(target.charOffset);
  }
}

/// 时钟推进 + 帧泵送组合：tick 内超时/监控判定都读 clock.now。
void _pump(_ManualFrameScheduler frames, _FakeClock clock, Duration step) {
  clock.advance(step);
  frames.pump();
}

class _FakeScheduledTimer implements Timer {
  _FakeScheduledTimer(this._clock, this._deadline, this._callback);

  final _FakeClock _clock;
  final DateTime _deadline;
  final void Function() _callback;
  bool _cancelled = false;

  void fireIfDue() {
    if (!_cancelled && !_clock.now.isBefore(_deadline)) {
      _callback();
      _cancelled = true;
    }
  }

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _cancelled ? 1 : 0;
}

class _FakeClock implements ReaderRuntimeClock {
  DateTime _now = DateTime(2026, 1, 1);
  final _timers = <_FakeScheduledTimer>[];

  @override
  DateTime get now => _now;

  @override
  Timer schedule(Duration duration, void Function() callback) {
    final timer = _FakeScheduledTimer(this, _now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    _now = _now.add(duration);
    for (final timer in List<_FakeScheduledTimer>.of(_timers)) {
      timer.fireIfDue();
    }
    _timers.removeWhere((t) => !t.isActive);
  }
}

_ReaderReadingRuntimeHarness _buildHarness() {
  final clock = _FakeClock();
  final frames = _ManualFrameScheduler();
  final effect = _FakeScrollEffect();
  final delegate = _FakeRestoreDelegate();
  final runtime = ReaderReadingRuntime(clock: clock);
  runtime.scrollEffect = effect;
  runtime.restoreDelegate = delegate;
  runtime.frameScheduler = frames.schedule;
  return _ReaderReadingRuntimeHarness(
    runtime: runtime,
    clock: clock,
    frames: frames,
    effect: effect,
    delegate: delegate,
  );
}

class _ReaderReadingRuntimeHarness {
  _ReaderReadingRuntimeHarness({
    required this.runtime,
    required this.clock,
    required this.frames,
    required this.effect,
    required this.delegate,
  });

  final ReaderReadingRuntime runtime;
  final _FakeClock clock;
  final _ManualFrameScheduler frames;
  final _FakeScrollEffect effect;
  final _FakeRestoreDelegate delegate;

  /// 驱动至多 500 帧直到不再排帧。
  void settle({int maxFrames = 500}) => frames.settle(maxFrames: maxFrames);
}

void main() {
  const target = ReaderPositionTarget(chapterId: 'c1', charOffset: 1200);

  test('多帧重试收敛：布局未就绪等待 → 解析 → 稳定 10 帧 → stabilizing 回写', () {
    final h = _buildHarness();
    // 布局未就绪（hasClients=false）→ 引擎重排帧等待。
    h.effect.hasClients = false;
    h.runtime.startRestore(target);
    expect(h.runtime.restore.isBusy, isTrue);
    h.frames.pump();
    expect(h.effect.jumpCount, 0);
    expect(h.frames.pendingCount, 1);

    // 布局就绪、目标可解析：连续 10 帧无漂移后稳定。
    h.effect.hasClients = true;
    h.effect.offsetValue = 600;
    h.delegate.resolveMap[target.charOffset] = 1200;
    for (var i = 0; i < 10; i++) {
      h.frames.pump();
    }
    // 目标偏移 600 > drift 阈值 10：第一帧会 jumpTo 对齐。
    expect(h.effect.offsetValue, 1200);
    // 之后帧稳定累积；由于 jump 后 offset==target，最终应进入 stabilizing。
    h.settle();
    expect(h.runtime.restore.phase, ReaderRestorePhase.stabilizing);
    expect(h.delegate.settledTargets, [target.charOffset]);
  });

  test('resolve 持续返回 null 时等待，不消耗 pendingFrames 上限', () {
    final h = _buildHarness();
    h.delegate.resolveMap.remove(target.charOffset);
    h.runtime.startRestore(target);
    for (var i = 0; i < 60; i++) {
      _pump(h.frames, h.clock, const Duration(milliseconds: 16));
    }
    // 60 帧 ≈ 1s，远小于 10s 总超时：仍在 applying 等待。
    expect(h.runtime.restore.phase, ReaderRestorePhase.applying);
    expect(h.effect.jumpCount, 0);
  });

  test('用户滚动让位：相位取消 + restoreInvalidated + 停止排帧', () {
    final h = _buildHarness();
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    h.frames.pump();
    expect(h.runtime.restore.isBusy, isTrue);

    h.delegate.userScrolling = true;
    h.frames.pump();
    expect(h.runtime.restore.phase, ReaderRestorePhase.cancelled);
    expect(h.runtime.restore.target, isNull);
    expect(h.frames.pendingCount, 0);
    // 让位判定收到的是发起时刻（startedAt）。
    expect(h.delegate.userScrollSinceHit, isNotNull);
  });

  test('总超时：10s 未收敛进入 timedOut 终态', () {
    final h = _buildHarness();
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    // 每帧 maxScrollExtent 变化 > 8（图片渐进测高）：稳定判定永不满足，
    // 引擎反复 jumpTo 直至总超时。
    for (var i = 0; i < 700; i++) {
      if (h.frames.pendingCount == 0) {
        break;
      }
      h.effect.maxScrollExtent = 4000 + i * 20.0;
      _pump(h.frames, h.clock, const Duration(milliseconds: 16));
    }
    expect(h.runtime.restore.phase, ReaderRestorePhase.timedOut);
    expect(h.frames.pendingCount, 0);
  });

  test('监控期滚离完成：逐帧慢速漂移累积 > 4×drift 判 completed', () {
    final h = _buildHarness();
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    h.frames.pump(); // 首帧 jumpTo 1200
    for (var i = 0; i < 11; i++) {
      h.frames.pump(); // 此后 11 帧无漂移 → 稳定 10 帧
    }
    expect(h.runtime.restore.phase, ReaderRestorePhase.stabilizing);

    // 监控期用户慢速滚动（每帧 1.2px < 2px 外力判定阈值），累积 > 40px。
    for (var i = 0; i < 40; i++) {
      if (h.frames.pendingCount == 0) {
        break;
      }
      h.effect.offsetValue = 1200 + (i + 1) * 1.2;
      h.frames.pump();
    }
    expect(h.runtime.restore.phase, ReaderRestorePhase.completed);
    expect(h.frames.pendingCount, 0);
  });

  test('监控期快速滚动（单帧 > 2px）被判外力让位进入 cancelled', () {
    final h = _buildHarness();
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    h.settle();
    expect(h.runtime.restore.phase, ReaderRestorePhase.stabilizing);

    h.effect.offsetValue = 1200 + 60;
    h.frames.pump();
    expect(h.runtime.restore.phase, ReaderRestorePhase.cancelled);
    expect(h.frames.pendingCount, 0);
  });

  test('监控期 5s 超时：无滚离则 markCompleted（绝不 jumpTo 对抗用户）', () {
    final h = _buildHarness();
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    h.frames.pump();
    for (var i = 0; i < 10; i++) {
      h.frames.pump();
    }
    expect(h.runtime.restore.phase, ReaderRestorePhase.stabilizing);

    // 监控期内慢速漂移（< 40px），推钟 5s。
    for (var i = 0; i < 400; i++) {
      if (h.frames.pendingCount == 0) {
        break;
      }
      h.effect.offsetValue = 1200 + (i / 100.0);
      _pump(h.frames, h.clock, const Duration(milliseconds: 16));
    }
    expect(h.runtime.restore.phase, ReaderRestorePhase.completed);
    expect(h.effect.offsetValue, closeTo(1200, 40));
  });

  test('场景 C：恢复中新输入失效 operationToken，在途帧中止', () {
    final h = _buildHarness();
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    h.frames.pump();
    expect(h.frames.pendingCount, 1);

    // 恢复进行中出现新操作（滚轮/新恢复/程序化滚动都会 invalidate）。
    h.runtime.operationToken.invalidate();
    h.frames.pump();
    // 在途帧直接中止：既不推进相位也不排后续帧。
    expect(h.runtime.restore.phase, ReaderRestorePhase.applying);
    expect(h.frames.pendingCount, 0);

    // 新恢复重新接管。
    h.runtime.startRestore(
      const ReaderPositionTarget(chapterId: 'c2', charOffset: 30),
    );
    h.delegate.resolveMap[30] = 100;
    h.settle();
    expect(h.runtime.restore.phase, ReaderRestorePhase.stabilizing);
    expect(h.delegate.settledTargets.last, 30);
  });

  test('身份不符：发起后 item/mode 变更，稳定回写被丢弃并计数（§57）', () {
    final h = _buildHarness();
    var identity = const ReaderRuntimeIdentity(
      itemId: 'item-1',
      readingMode: 'scroll',
    );
    h.runtime.identityProvider = () => identity;
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    // 发起后身份变更（如模式切换先行提交）：回写必须被拦截。
    identity = const ReaderRuntimeIdentity(
      itemId: 'item-1',
      readingMode: 'page',
    );
    h.settle();
    expect(h.runtime.restore.phase, ReaderRestorePhase.stabilizing);
    expect(h.delegate.settledTargets, isEmpty);
    expect(h.runtime.diagnostics.restoreCallbackDropCount, 1);
  });

  test('身份相符：稳定回写 tracker 目标一次', () {
    final h = _buildHarness();
    final identity = const ReaderRuntimeIdentity(
      itemId: 'item-1',
      readingMode: 'scroll',
    );
    h.runtime.identityProvider = () => identity;
    h.delegate.resolveMap[target.charOffset] = 1200;
    h.runtime.startRestore(target);
    h.settle();
    expect(h.delegate.settledTargets, [target.charOffset]);
    expect(h.runtime.diagnostics.restoreCallbackDropCount, 0);
  });

  test('未注入 delegate 时 startRestore 直接返回，不进入相位', () {
    final clock = _FakeClock();
    final frames = _ManualFrameScheduler();
    final runtime = ReaderReadingRuntime(clock: clock);
    runtime.frameScheduler = frames.schedule;
    runtime.startRestore(target);
    expect(runtime.restore.phase, ReaderRestorePhase.idle);
    expect(frames.pendingCount, 0);
  });

  test('页模式相位超时：定位回调缺失时 10s 后 timedOut 解除占用', () {
    final h = _buildHarness();
    h.runtime.beginRestorePhase(target);
    expect(h.runtime.restore.phase, ReaderRestorePhase.applying);
    expect(h.runtime.isRestoreApplying, isTrue);

    // 定位链未回调（chapter 数据滞缺/调度断裂）：推钟至总超时。
    h.clock.advance(const Duration(seconds: 10));
    expect(h.runtime.restore.phase, ReaderRestorePhase.timedOut);
    expect(h.runtime.restorePhaseTarget, isNull);
    expect(h.runtime.isRestoreApplying, isFalse);
    expect(
      h.runtime.eventLog.events.any(
        (e) =>
            e.type == ReaderRuntimeEventType.restoreFinished &&
            e.phase == ReaderRestorePhase.timedOut.name,
      ),
      isTrue,
    );
  });

  test('页模式相位完成/取消清除超时计时器，超时不再触发', () {
    final h = _buildHarness();
    h.runtime.beginRestorePhase(target);
    h.runtime.completeRestorePhase();
    expect(h.runtime.restore.phase, ReaderRestorePhase.completed);

    h.runtime.beginRestorePhase(target);
    h.runtime.cancelRestorePhase();
    expect(h.runtime.restore.phase, ReaderRestorePhase.cancelled);

    // 计时器已清除：推钟超过总超时不改变终态。
    h.clock.advance(const Duration(seconds: 20));
    expect(h.runtime.restore.phase, ReaderRestorePhase.cancelled);
  });
}
