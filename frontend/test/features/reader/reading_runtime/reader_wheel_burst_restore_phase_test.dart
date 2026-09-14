import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_wheel_burst_tracker.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';

import 'geometry_fixtures.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this._clock, this._expireAt, this._callback);

  final _FakeClock _clock;
  final DateTime _expireAt;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  void fireIfDue() {
    if (_cancelled || _fired) {
      return;
    }
    if (!_clock.now.isBefore(_expireAt)) {
      _fired = true;
      _callback();
    }
  }

  @override
  int get tick => 0;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled && !_fired;
}

class _FakeClock implements ReaderRuntimeClock {
  DateTime _now = DateTime(2026, 1, 1);
  final _timers = <_FakeTimer>[];

  @override
  DateTime get now => _now;

  @override
  Timer schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer(this, _now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    _now = _now.add(duration);
    for (final timer in List<_FakeTimer>.of(_timers)) {
      timer.fireIfDue();
    }
  }
}

void main() {
  group('ReaderWheelBurstTracker（方案 §30/§31/§115/§116）', () {
    test('burst 内复用存续窗口，超时回调恰好一次', () {
      final clock = _FakeClock();
      var timeouts = 0;
      final tracker = ReaderWheelBurstTracker(
        clock: clock,
        idleTimeout: const Duration(milliseconds: 200),
      );

      // 高频信号（触控板 100+ delta 场景的压缩表示）。
      for (var i = 0; i < 100; i++) {
        clock.advance(const Duration(milliseconds: 1));
        tracker.onSignal(onTimeout: () => timeouts++);
      }
      expect(tracker.isBurstOngoing, isTrue);
      expect(tracker.signalCount, 100);

      // 超时窗口到期：一次超时回调，burst 归零。
      clock.advance(const Duration(milliseconds: 200));
      expect(timeouts, 1);
      expect(tracker.isBurstOngoing, isFalse);
      expect(tracker.signalCount, 0);

      // 新 burst 重新计数。
      tracker.onSignal(onTimeout: () => timeouts++);
      expect(tracker.isBurstOngoing, isTrue);
      expect(tracker.signalCount, 1);
      tracker.cancel();
    });
  });

  group('ReaderRestorePhase（方案 §97/§98）', () {
    test('applying→stabilizing→completed 全程推进', () {
      final manager = ReaderRestoreManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final tx = manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 0),
        layout: layout,
        itemId: 'item',
        readingMode: 'scroll',
      );
      expect(manager.phase, ReaderRestorePhase.applying);

      manager.markStabilizing();
      expect(manager.phase, ReaderRestorePhase.stabilizing);
      // 监控期回调仍有效（§57）。
      expect(
        manager.isCallbackValid(tx, itemId: 'item', readingMode: 'scroll'),
        isTrue,
      );

      manager.markCompleted();
      expect(manager.phase, ReaderRestorePhase.completed);
    });

    test('用户取消与超时是互斥终态，物理位置即事实', () {
      final manager = ReaderRestoreManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 0),
        layout: layout,
        itemId: 'item',
        readingMode: 'scroll',
      );
      manager.markTimedOut();
      expect(manager.phase, ReaderRestorePhase.timedOut);

      manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 5),
        layout: layout,
        itemId: 'item',
        readingMode: 'scroll',
      );
      expect(manager.phase, ReaderRestorePhase.applying);
      manager.cancel();
      expect(manager.phase, ReaderRestorePhase.cancelled);
      expect(manager.current, isNull);
    });
  });
}
