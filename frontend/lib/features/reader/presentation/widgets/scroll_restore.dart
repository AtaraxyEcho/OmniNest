import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 滚动位置恢复器。
///
/// 封装 [addPersistentFrameCallback] 的生命周期管理，解决回调累积问题。
/// 通过代际计数器自动失效旧回调，确保同一时间只有一个恢复流程在运行。
///
/// ## 恢复策略
///
/// 由于 ListView 懒加载 + 图片异步加载，[ScrollPosition.maxScrollExtent]
/// 在布局过程中持续变化。恢复分两个阶段：
///
/// 1. **主动恢复**：检测 max 变化时重新跳转，直到位置稳定
/// 2. **监控期**：settle 后继续监控 max 变化，如果 max 再次显著变化
///   （说明有新内容加载导致布局偏移），重新激活恢复
///
/// 监控期结束后（默认 5 秒），恢复流程彻底结束，`isActive` 变为 false。
class ScrollRestore {
  ScrollRestore({
    int stableFramesThreshold = 10,
    double driftThreshold = 10.0,
    double maxChangeThreshold = 1.0,
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

  /// 当前是否正在主动恢复中（不包括监控期）。
  bool get isActive => _active && !_monitoring;

  /// 是否应抑制外部进度保存（包括主动恢复期和监控期）。
  /// 监控期内 maxScrollExtent 仍在变化，保存会写入错误位置。
  bool get shouldSuppressWrites => _active;

  /// 取消当前恢复流程（不触发 [onSettled] 回调）。
  void cancel() {
    _active = false;
    _monitoring = false;
    // generation 在 start() 中递增，此处不递增避免累积
  }

  /// 启动恢复流程。
  ///
  /// 使用 [addPostFrameCallback] 自循环，每帧检查偏移量与目标的偏差。
  /// 恢复完成或取消后自动停止调度，不会积累永久回调。
  ///
  /// [onSettled] 在恢复流程结束时触发（无论是否到达目标）：参数为
  /// true 表示已稳定到达目标位置；false 表示被 [isUserScrolling] 的
  /// 用户主动滚动中断或超过 [totalTimeout]，此时调用方不得把恢复
  /// 目标写入位置追踪，只能结束恢复态。[cancel] 不触发回调，由调用
  /// 方自行清理。
  ///
  /// 恢复完成后进入监控期（[_monitorDuration]），期间如果 maxScrollExtent
  /// 再次显著变化会重新激活恢复；maxScrollExtent 因图片渐进加载而持续
  /// 变化时，用户活动探针与总超时保证循环必然终止。
  void start({
    required ScrollController scrollController,
    required double Function() targetOffsetBuilder,
    required ValueChanged<bool> onSettled,
    bool Function()? isUserScrolling,
    Duration totalTimeout = const Duration(seconds: 10),
  }) {
    _generation++;
    final myGeneration = _generation;
    _active = true;
    _monitoring = false;
    final startedAt = DateTime.now();

    int stableFrames = 0;
    int pendingFrames = 0;
    double lastMax = 0;
    bool settled = false;
    DateTime? settledAt;

    // 布局等待阶段最大帧数（约 3 秒 @60fps），超时后放弃恢复
    const maxPendingFrames = 180;

    void tick() {
      // 检查是否应继续
      if (!_active || myGeneration != _generation) return;
      // 用户主动滚动（滚轮/拖动/点击）立即让位，绝不与用户争抢滚动位置
      if (isUserScrolling != null && isUserScrolling()) {
        _active = false;
        _monitoring = false;
        onSettled(false);
        return;
      }
      // 总时长硬上限：图片渐进加载等导致 maxScrollExtent 持续变化时，
      // 重新激活分支会无限 jumpTo 拉回用户位置，必须整体兜底
      if (DateTime.now().difference(startedAt) > totalTimeout) {
        _active = false;
        _monitoring = false;
        onSettled(false);
        return;
      }
      if (!scrollController.hasClients) {
        pendingFrames++;
        if (pendingFrames >= maxPendingFrames) {
          _active = false;
          if (kDebugMode) {
            readerDebugLog('ScrollRestore: timed out waiting for layout');
          }
          onSettled(false);
          return;
        }
        SchedulerBinding.instance.addPostFrameCallback((_) => tick());
        return;
      }

      final max = scrollController.position.maxScrollExtent;
      if (max <= 0) {
        pendingFrames++;
        if (pendingFrames >= maxPendingFrames) {
          _active = false;
          if (kDebugMode) {
            readerDebugLog('ScrollRestore: timed out, maxScrollExtent <= 0');
          }
          onSettled(false);
          return;
        }
        SchedulerBinding.instance.addPostFrameCallback((_) => tick());
        return;
      }

      final target = targetOffsetBuilder().clamp(0.0, max);
      final currentOffset = scrollController.offset;
      final drift = (currentOffset - target).abs();
      final maxChanged = (max - lastMax).abs() > _maxChangeThreshold;
      final overflowed = currentOffset > max + 1.0;

      if (maxChanged || overflowed) {
        lastMax = max;
        if (settled) {
          settled = false;
          settledAt = null;
          _monitoring = false;
          stableFrames = 0;
          if (kDebugMode) {
            readerDebugLog(
              'ScrollRestore: max changed during monitor, re-activating '
              '(drift=${drift.toStringAsFixed(1)}, max=${max.toStringAsFixed(1)})',
            );
          }
        } else {
          stableFrames = 0;
        }
        scrollController.jumpTo(target);
      } else if (!settled) {
        if (drift <= _driftThreshold) {
          stableFrames++;
          if (stableFrames >= _stableFramesThreshold) {
            settled = true;
            settledAt = DateTime.now();
            _monitoring = true;
            onSettled(true);
            if (kDebugMode) {
              readerDebugLog(
                'ScrollRestore: settled, entering monitor period '
                '(${_monitorDuration.inSeconds}s)',
              );
            }
          }
        } else {
          stableFrames = 0;
          scrollController.jumpTo(target);
        }
      } else {
        // 监控期
        if (DateTime.now().difference(settledAt!) > _monitorDuration) {
          _active = false;
          _monitoring = false;
          if (kDebugMode) {
            readerDebugLog('ScrollRestore: monitor period ended, stopping');
          }
          return; // 停止调度
        }
        if (drift > _driftThreshold * 3) {
          _active = false;
          _monitoring = false;
          if (kDebugMode) {
            readerDebugLog(
              'ScrollRestore: user scroll detected during monitor, stopping',
            );
          }
          return; // 停止调度
        }
      }

      // 调度下一帧（自循环）
      if (_active && myGeneration == _generation) {
        SchedulerBinding.instance.addPostFrameCallback((_) => tick());
      }
    }

    // 启动第一帧
    SchedulerBinding.instance.addPostFrameCallback((_) => tick());

    if (kDebugMode) {
      readerDebugLog('ScrollRestore: started (generation=$_generation)');
    }
  }

  String get debugLabel => 'ScrollRestore(gen=$_generation, active=$_active)';
}
