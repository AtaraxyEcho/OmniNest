import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 滚动位置恢复器。
///
/// ## 策略
///
/// 1. **主动恢复期**：maxScrollExtent 变化时重算目标并 jumpTo，直到位置稳定。
/// 2. **监控期**：settle 后**不再 jumpTo**。图片渐进加载只会撑高列表，
///    视口内容相对偏移基本保持；若监控期再 jumpTo，会与用户慢速滚动
///    对抗，表现为「遇见图片突然跳进度」。
/// 3. 监控期只做两件事：检测用户明显滚离（结束监控）、检测越界钳制。
class ScrollRestore {
  ScrollRestore({
    int stableFramesThreshold = 10,
    double driftThreshold = 10.0,
    double maxChangeThreshold = 8.0,
    Duration monitorDuration = const Duration(seconds: 5),
  }) : _stableFramesThreshold = stableFramesThreshold,
       _driftThreshold = driftThreshold,
       _maxChangeThreshold = maxChangeThreshold,
       _monitorDuration = monitorDuration;

  final int _stableFramesThreshold;
  final double _driftThreshold;
  final double _maxChangeThreshold;
  final Duration _monitorDuration;

  int _generation = 0;
  bool _active = false;
  bool _monitoring = false;

  bool get isActive => _active && !_monitoring;
  bool get shouldSuppressWrites => _active;

  void cancel() {
    _active = false;
    _monitoring = false;
  }

  void start({
    required ScrollController scrollController,
    required double Function() targetOffsetBuilder,
    required ValueChanged<bool> onSettled,
    bool Function()? isUserScrolling,
    Duration totalTimeout = const Duration(seconds: 10),
    void Function()? onTimedOut,
    void Function()? onMonitorEnd,
  }) {
    _generation++;
    final myGeneration = _generation;
    _active = true;
    _monitoring = false;
    final startedAt = DateTime.now();

    int stableFrames = 0;
    int pendingFrames = 0;
    double lastMax = 0;
    double settledOffset = 0;
    double lastObservedOffset = -1;
    bool settled = false;
    DateTime? settledAt;
    bool selfJump = false;

    const maxPendingFrames = 180;

    void finish({required bool completed}) {
      _active = false;
      _monitoring = false;
      onSettled(completed);
    }

    double maxScrollExtentSafe() {
      if (!scrollController.hasClients) return 0;
      final m = scrollController.position.maxScrollExtent;
      return m < 0 ? 0 : m;
    }

    void safeJump(double value) {
      selfJump = true;
      scrollController.jumpTo(value.clamp(0.0, maxScrollExtentSafe()));
      lastObservedOffset =
          scrollController.hasClients ? scrollController.offset : value;
      selfJump = false;
    }

    void tick() {
      if (!_active || myGeneration != _generation) return;
      if (isUserScrolling != null && isUserScrolling()) {
        finish(completed: false);
        return;
      }
      if (DateTime.now().difference(startedAt) > totalTimeout) {
        onTimedOut?.call();
        finish(completed: false);
        return;
      }
      if (!scrollController.hasClients) {
        pendingFrames++;
        if (pendingFrames >= maxPendingFrames) {
          if (kDebugMode) {
            readerDebugLog('ScrollRestore: timed out waiting for layout');
          }
          finish(completed: false);
          return;
        }
        SchedulerBinding.instance.addPostFrameCallback((_) => tick());
        return;
      }

      final max = scrollController.position.maxScrollExtent;
      if (max <= 0) {
        pendingFrames++;
        if (pendingFrames >= maxPendingFrames) {
          if (kDebugMode) {
            readerDebugLog('ScrollRestore: timed out, maxScrollExtent <= 0');
          }
          finish(completed: false);
          return;
        }
        SchedulerBinding.instance.addPostFrameCallback((_) => tick());
        return;
      }

      final currentOffset = scrollController.offset;
      // 非自身 jump 且 offset 变化：视为用户滚轮/拖动。
      if (!selfJump &&
          lastObservedOffset >= 0 &&
          (currentOffset - lastObservedOffset).abs() > 2.0) {
        if (kDebugMode) {
          readerDebugLog(
            'ScrollRestore: offset changed without jump, yielding to user',
          );
        }
        finish(completed: false);
        return;
      }
      lastObservedOffset = currentOffset;

      final target = targetOffsetBuilder().clamp(0.0, max);
      final drift = (currentOffset - target).abs();
      final maxChanged = (max - lastMax).abs() > _maxChangeThreshold;
      final overflowed = currentOffset > max + 1.0;

      if (!settled) {
        if (maxChanged || overflowed || drift > _driftThreshold) {
          lastMax = max;
          stableFrames = 0;
          safeJump(target);
        } else {
          stableFrames++;
          if (stableFrames >= _stableFramesThreshold) {
            settled = true;
            settledAt = DateTime.now();
            settledOffset = currentOffset;
            _monitoring = true;
            lastMax = max;
            onSettled(true);
            if (kDebugMode) {
              readerDebugLog(
                'ScrollRestore: settled, entering monitor period '
                '(${_monitorDuration.inSeconds}s)',
              );
            }
          }
        }
      } else {
        // 监控期：绝不 jumpTo 对齐目标，避免图片加载把用户拉回。
        if (overflowed) {
          safeJump(max);
          settledOffset = max;
        }
        final leftSettled = (currentOffset - settledOffset).abs();
        if (leftSettled > _driftThreshold * 4) {
          if (kDebugMode) {
            readerDebugLog(
              'ScrollRestore: user scroll detected during monitor, stopping',
            );
          }
          finish(completed: true);
          return;
        }
        if (DateTime.now().difference(settledAt!) > _monitorDuration) {
          _active = false;
          _monitoring = false;
          onMonitorEnd?.call();
          if (kDebugMode) {
            readerDebugLog('ScrollRestore: monitor period ended, stopping');
          }
          return;
        }
      }

      if (_active && myGeneration == _generation) {
        SchedulerBinding.instance.addPostFrameCallback((_) => tick());
      }
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => tick());

    if (kDebugMode) {
      readerDebugLog('ScrollRestore: started (generation=$_generation)');
    }
  }

  String get debugLabel => 'ScrollRestore(gen=$_generation, active=$_active)';
}
