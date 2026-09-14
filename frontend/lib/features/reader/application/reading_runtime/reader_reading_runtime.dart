import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;

import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_event_log.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_commit.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_invalidation.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_scheduler.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_store.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_operation_token.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_persistence_queue.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_state.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_publisher.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_identity.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scroll_effect.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_visual_extent_table.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_wheel_burst_tracker.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_window_manager.dart';

/// Reader Reading Runtime Facade（方案 §83/§64 终态）：页面只经此访问运行时。
///
/// 四个 Authority（Position / Geometry / Transaction / Progress）加上
/// Window 与 Restore 管理器在此聚合；[currentPosition] 是最近一次被
/// 接受的位置事实，供离场快照与诊断读取。
class ReaderReadingRuntime {
  ReaderReadingRuntime({
    ReaderTransactionManager? transactions,
    ReaderGeometryStore? geometry,
    ReaderPositionResolver? position,
    ReaderProgressProjection? progress,
    ReaderVisualProgressPublisher? publisher,
    ReaderWindowManager? window,
    ReaderRestoreManager? restore,
    ReaderRuntimeClock? clock,
    ReaderRuntimeDiagnostics? diagnostics,
    ReaderGeometryCommit? geometryCommit,
    ReaderOperationToken? operationToken,
    ReaderPositionState? positionState,
    ReaderGeometryScheduler? geometryScheduler,
    ReaderScrollEffect? scrollEffect,
    void Function(ReaderProgressSnapshot snapshot)? onPersistEnqueue,
  }) : transactions = transactions ?? ReaderTransactionManager(),
       geometry = geometry ?? ReaderGeometryStore(),
       position = position ?? const ReaderPositionResolver(),
       progress = progress ?? ReaderProgressProjection(),
       publisher =
           publisher ?? ReaderVisualProgressPublisher(ValueNotifier<double>(0)),
       window = window ?? ReaderWindowManager(),
       restore = restore ?? ReaderRestoreManager(),
       clock = clock ?? const SystemReaderRuntimeClock(),
       diagnostics = diagnostics ?? ReaderRuntimeDiagnostics(),
       geometryCommit = geometryCommit ?? const ReaderGeometryCommit(),
       operationToken = operationToken ?? ReaderOperationToken(),
       positionState = positionState ?? ReaderPositionState(),
       geometryScheduler = geometryScheduler ?? ReaderGeometryScheduler(),
       persistenceQueue = ReaderPersistenceQueue(
         onEnqueue: onPersistEnqueue ?? (_) {},
       ),
       wheelBurst = ReaderWheelBurstTracker(
         clock: clock ?? const SystemReaderRuntimeClock(),
       );

  final ReaderTransactionManager transactions;

  final ReaderGeometryStore geometry;

  final ReaderPositionResolver position;

  final ReaderProgressProjection progress;

  /// bookProgressNotifier 的唯一写者（方案 §50）。
  final ReaderVisualProgressPublisher publisher;

  final ReaderWindowManager window;

  final ReaderRestoreManager restore;

  final ReaderRuntimeClock clock;

  final ReaderRuntimeDiagnostics diagnostics;

  /// 结束性 Geometry Commit 与锚点保持修正（方案 §38/§94）。
  final ReaderGeometryCommit geometryCommit;

  /// 滚轮/触控板 burst 跟踪（方案 §30/§31，时钟经 §109 注入）。
  final ReaderWheelBurstTracker wheelBurst;

  /// 事件日志（方案 §103/§126）：环形缓冲 + 实机验收格式。
  final ReaderRuntimeEventLog eventLog = ReaderRuntimeEventLog();

  // ── 滚动编排器（新方案 §5/§7/§8/§62：信号进，决策内化）──

  _RuntimeScrollPhase _scrollPhase = _RuntimeScrollPhase.idle;
  Timer? _settleTimer;

  /// 布局快照供给（页面适配器注入：几何/视口/窗口版本采样）。
  ReaderLayoutSnapshot Function()? layoutProvider;

  /// 章节收养请求（页面执行收养提交，§64）。
  void Function(String chapterId)? onAdoptChapterRequested;

  /// 窗口扩挂请求（§42）。
  void Function({required bool forward})? onExpandWindowRequested;

  /// 窗口指标提交请求（settling 一次收敛；B4 内化为 WindowBuilder）。
  void Function()? onMetricsCommitRequested;

  /// 用户输入取消在途恢复的请求（页面清除恢复态）。
  void Function()? onRestoreCancelRequested;

  /// 是否处于用户手势中（拖动/惯性）；几何提交在此期间必须挂起。
  bool get isInActiveGesture =>
      _scrollPhase == _RuntimeScrollPhase.dragging ||
      _scrollPhase == _RuntimeScrollPhase.ballistic;

  /// 滚动是否非空闲（含 settling）。
  bool get isScrollBusy => _scrollPhase != _RuntimeScrollPhase.idle;

  /// 指针拖动越过阈值（新方案 §5）：Runtime 决定事务创建。
  void onPointerDragStarted() {
    if (_scrollPhase == _RuntimeScrollPhase.dragging) {
      return;
    }
    _beginTransaction(ReaderTransactionKind.userDrag);
    _scrollPhase = _RuntimeScrollPhase.dragging;
  }

  /// 指针释放：惯性阶段沿用同一事务（§11）。
  void onPointerReleased() {
    if (_scrollPhase == _RuntimeScrollPhase.dragging) {
      _scrollPhase = _RuntimeScrollPhase.ballistic;
    }
  }

  /// ScrollEnd（新方案 §7）：由 Runtime 判断 burst/相位后决定是否 settle。
  void onPhysicalScrollEnd() {
    if (_isWheelBurstOngoing) {
      return;
    }
    _settle();
  }

  /// 滚轮/触控板信号（新方案 §8/§29-§31）。
  void onWheelSignal() {
    final tx = transactions.current;
    if (tx != null &&
        tx.kind == ReaderTransactionKind.userDrag &&
        isInActiveGesture) {
      return;
    }
    onRestoreCancelRequested?.call();
    if (tx == null ||
        (tx.kind != ReaderTransactionKind.wheel &&
            tx.kind != ReaderTransactionKind.touchpad)) {
      _beginTransaction(ReaderTransactionKind.wheel);
    }
    wheelBurst.onSignal(onTimeout: onWheelBurstTimeout);
  }

  /// 滚轮 burst 空闲超时（新方案 §8）：只是信号，settle 决策在 Runtime。
  void onWheelBurstTimeout() {
    if (_scrollPhase == _RuntimeScrollPhase.idle) {
      _settle();
    }
  }

  bool get _isWheelBurstOngoing {
    final tx = transactions.current;
    if (tx == null ||
        (tx.kind != ReaderTransactionKind.wheel &&
            tx.kind != ReaderTransactionKind.touchpad)) {
      return false;
    }
    return wheelBurst.isBurstOngoing;
  }

  void _beginTransaction(ReaderTransactionKind kind) {
    // 新操作使全部在途异步续作失效（新方案 §59/场景 E）。
    operationToken.invalidate();
    final layout = layoutProvider?.call();
    if (layout == null) {
      return;
    }
    restore.cancel();
    final tx = transactions.beginOrReplace(
      kind: kind,
      layout: layout,
      initialOffset:
          scrollEffect?.hasClients == true ? scrollEffect!.offset : 0.0,
      initialVisualProgress: publisher.notifier.value,
    );
    emitEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.transactionStarted,
        at: clock.now,
        transactionId: tx.id,
        kind: tx.kind.name,
        layoutRevision: '${layout.geometry.revision}/${layout.windowRevision}',
        offset: tx.lastScrollOffset,
      ),
    );
  }

  void _settle() {
    final settlingTx = transactions.current;
    emitEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.settlingStarted,
        at: clock.now,
        transactionId: settlingTx?.id ?? 0,
        kind: settlingTx?.kind.name,
      ),
    );
    if (settlingTx != null) {
      final pendingChapter = settlingTx.pendingChapterId;
      if (pendingChapter != null) {
        onAdoptChapterRequested?.call(pendingChapter);
      }
      if (settlingTx.pendingExpandForward) {
        onExpandWindowRequested?.call(forward: true);
      }
      if (settlingTx.pendingExpandBackward) {
        onExpandWindowRequested?.call(forward: false);
      }
    }
    onMetricsCommitRequested?.call();
    window.clearPending();
    window.pendingMetricUpdate = false;
    geometryScheduler.consumePendingCommit();
    positionState.commitTransient();
    if (settlingTx != null) {
      transactions.finish(settlingTx.id);
      emitEvent(
        ReaderRuntimeEvent(
          type: ReaderRuntimeEventType.transactionCompleted,
          at: clock.now,
          transactionId: settlingTx.id,
          kind: settlingTx.kind.name,
        ),
      );
    }
    _scrollPhase = _RuntimeScrollPhase.settling;
    _settleTimer?.cancel();
    _settleTimer = clock.schedule(const Duration(milliseconds: 150), () {
      if (_scrollPhase == _RuntimeScrollPhase.settling) {
        _scrollPhase = _RuntimeScrollPhase.idle;
      }
    });
  }

  /// 程序化 scrollBy（新方案 §9/§45/§62）：显式事务 + Token 校验；
  /// 位置消费由物理 offset 监听链完成（§87），settle 由 ScrollEnd 触发。
  Future<bool> scrollBy(
    double delta, {
    ReaderTransactionKind kind = ReaderTransactionKind.sideTap,
  }) {
    final effect = scrollEffect;
    if (effect == null || !effect.hasClients) {
      return Future<bool>.value(false);
    }
    final target = (effect.offset + delta).clamp(0.0, effect.maxScrollExtent);
    if ((target - effect.offset).abs() < 1.0) {
      return Future<bool>.value(false);
    }
    return _runProgrammaticScroll(
      target,
      kind,
      const Duration(milliseconds: 250),
    );
  }

  /// 程序化 animateTo（新方案 §9/§45/§62）。
  Future<bool> animateToOffset(
    double targetOffset, {
    ReaderTransactionKind kind = ReaderTransactionKind.navigation,
  }) {
    final effect = scrollEffect;
    if (effect == null || !effect.hasClients) {
      return Future<bool>.value(false);
    }
    final target = targetOffset.clamp(0.0, effect.maxScrollExtent);
    return _runProgrammaticScroll(
      target,
      kind,
      const Duration(milliseconds: 220),
    );
  }

  /// 程序化 jumpTo（新方案 §9/§45/§62）。
  void jumpToOffset(
    double targetOffset, {
    ReaderTransactionKind kind = ReaderTransactionKind.layoutCorrection,
  }) {
    final effect = scrollEffect;
    if (effect == null || !effect.hasClients) {
      return;
    }
    final target = targetOffset.clamp(0.0, effect.maxScrollExtent);
    if (!isInActiveGesture) {
      onRestoreCancelRequested?.call();
      _beginTransaction(kind);
    }
    effect.jumpTo(target);
  }

  Future<bool> _runProgrammaticScroll(
    double target,
    ReaderTransactionKind kind,
    Duration duration,
  ) async {
    final effect = scrollEffect!;
    if (!isInActiveGesture) {
      onRestoreCancelRequested?.call();
      _beginTransaction(kind);
    }
    final token = operationToken.issue();
    await effect.animateTo(
      target,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
    // 场景 E：动画期间出现新操作（用户输入等）→ 本次续作整体丢弃。
    return operationToken.isCurrent(token);
  }

  /// 事件发射（方案 §103/§126）：debug 构建同步输出验收日志。
  void emitEvent(ReaderRuntimeEvent event) {
    eventLog.emit(event);
    if (kDebugMode) {
      readerDebugLog(eventLog.format(event));
    }
  }

  /// 页面离场释放内部计时资源。
  void dispose() {
    _settleTimer?.cancel();
    wheelBurst.cancel();
  }

  /// Runtime 操作令牌（新方案 §35/§43）：在途异步操作的生命周期凭证。
  final ReaderOperationToken operationToken;

  /// 位置状态（新方案 §30）：transient / committed 双位置。
  final ReaderPositionState positionState;

  /// Geometry 提交调度（新方案 §25/§42）：手势期间挂起、终端提交。
  final ReaderGeometryScheduler geometryScheduler;

  /// 持久化队列（新方案 §28/§30）：committedPosition 投影的唯一出口。
  final ReaderPersistenceQueue persistenceQueue;

  /// 物理滚动适配器（新方案 §43/§63）：页面注入，Runtime 不持有 Controller。
  ReaderScrollEffect? scrollEffect;

  /// 运行时身份（新方案 §57）：模式切换时更新。
  ReaderRuntimeIdentity? identity;

  ReaderPositionSnapshot? currentPosition;

  /// 全书视觉进度表（方案 §81 自 Widget 迁入；idle 显示与视觉 seek 用）。
  final ReaderVisualExtentTable visualExtent = ReaderVisualExtentTable();

  /// 收敛期守卫缓存（方案 §81）：上次解析的物理 offset 与章节身份。
  double? lastResolvedOffset;

  String? lastResolvedProgressChapterId;

  /// 几何失效回调（方案 §72）：页面在 initState 注入实际调度器；
  /// build / 事件只经 [requestGeometryUpdate] 声明失效，不同步提交。
  void Function(ReaderGeometryInvalidation reason)? onGeometryInvalidated;

  /// 几何失效请求唯一入口（方案 §72/§73）：请求与提交必须分离。
  void requestGeometryUpdate({required ReaderGeometryInvalidation reason}) {
    onGeometryInvalidated?.call(reason);
  }

  /// 释放 Facade 自建的通知器；页面自持通知器时通过自建 publisher 注入，
  /// 由页面负责其 dispose。
  void disposeOwnNotifier() {
    final notifier = publisher.notifier;
    notifier.dispose();
  }
}

/// Runtime 内部滚动相位（新方案 §5：Runtime 自持，Page 不可见）。
enum _RuntimeScrollPhase { idle, dragging, ballistic, settling }
