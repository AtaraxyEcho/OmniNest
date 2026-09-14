import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;

import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_consume_delegate.dart';
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

  // ── 消费管线（B3 §6.2：物理 offset 的唯一消费入口，四步拆分）──

  /// 物理滚动 offset 消费入口（B3 §6.2）：页面薄转发守卫后调用。
  /// 解析 → positionResolved 事件 → 同源守卫接受 → 视觉进度 →
  /// 窗口意图 → 逻辑位置确认。
  void onPhysicalOffsetChanged(double offset) {
    final tx = transactions.current;
    if (tx != null && tx.phase == ReaderTransactionPhase.cancelled) {
      return;
    }
    final layout = tx?.layout ?? layoutProvider?.call();
    if (layout == null) {
      return;
    }
    final snapshot = position.resolve(
      scrollOffset: offset,
      layout: layout,
      transactionId: tx?.id ?? 0,
    );
    if (snapshot == null) {
      return;
    }
    emitEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.positionResolved,
        at: clock.now,
        transactionId: snapshot.transactionId,
        layoutRevision:
            '${snapshot.layoutRevision.geometryRevision}/'
            '${snapshot.layoutRevision.windowRevision}',
        offset: snapshot.scrollOffset,
        chapterId: snapshot.chapterId,
        blockIndex: snapshot.blockIndex,
        charOffset: snapshot.charOffset,
        visualProgress: progress.visual.project(snapshot, layout.geometry),
        logicalProgress: progress.logical.project(snapshot, layout.geometry),
      ),
    );
    _acceptPosition(snapshot, tx);
  }

  /// 接受一次解析位置（§62 唯一写口）：事务同源双守卫后写入位置状态，
  /// 顺序驱动视觉进度、窗口意图与逻辑位置确认。
  void _acceptPosition(ReaderPositionSnapshot snapshot, ReaderTransaction? tx) {
    // 事务同源校验（方案 §45-46/§85-§86）：旧事务/旧几何的回调直接
    // 丢弃，不再重新解释（DEBUG 断言之外也有运行时防线）。
    if (tx != null) {
      if (snapshot.transactionId != tx.id) {
        diagnostics.stalePositionDropCount++;
        return;
      }
      if (snapshot.layoutRevision.geometryRevision !=
          tx.layout.geometry.revision) {
        diagnostics.stalePositionDropCount++;
        if (kDebugMode) {
          readerDebugLog(
            'ReaderScroll: discard stale position tx=${tx.id} '
            'positionRevision=${snapshot.layoutRevision.geometryRevision}',
          );
        }
        return;
      }
    }
    positionState.acceptTransient(snapshot);
    _updateVisualProgress(snapshot, tx);
    _updateWindowIntent(snapshot, tx);
    _confirmLogicalPosition(snapshot);
  }

  /// 视觉进度更新（§44）：章体视觉游标登记、事务方向推进、冻结映射
  /// 查询与方向性钳制后唯一发布。
  void _updateVisualProgress(
    ReaderPositionSnapshot snapshot,
    ReaderTransaction? tx,
  ) {
    lastChapterVisualCursor = snapshot.chapterVisualCursor;
    lastVisualProgressChapterId = snapshot.chapterId;
    final hasClients = scrollEffect?.hasClients ?? false;
    final offsetNow = hasClients ? scrollEffect!.offset : 0.0;
    if (tx != null) {
      tx.forward = offsetNow >= tx.lastScrollOffset;
      tx.lastScrollOffset = offsetNow;
    }
    final double nextProgress;
    if (tx == null) {
      // 无事务（程序化滚动窗口期）：全书视觉表兜底，绝不回退
      // Live Geometry 重新解释（方案 §25）。
      nextProgress =
          consumeDelegate?.visualProgressFallback(
            snapshot.chapterId,
            snapshot.chapterVisualCursor,
          ) ??
          _lastPublishedVisualProgress;
    } else {
      nextProgress =
          tx.visualMap.progressAt(
            (offsetNow + tx.layout.viewport.anchorY).clamp(
              0.0,
              double.infinity,
            ),
          ) ??
          tx.displayedProgress;
    }
    final displayed = _applyDirectionalProgressClamp(nextProgress, tx);
    if (tx != null) {
      tx.lastVisualProgress = displayed;
    }
    _publishVisualProgress(tx, displayed);
  }

  /// 窗口意图判定（§31/§32/§41/§64）：邻章收养与尾部扩窗。事务期间只
  /// 挂起（SETTLING 一次提交），空事务经 delegate 即时节流执行。
  void _updateWindowIntent(
    ReaderPositionSnapshot snapshot,
    ReaderTransaction? tx,
  ) {
    // 顺序滚动进入邻章：不得在用户滚动手势中途改写窗口几何。
    if (snapshot.chapterId != anchorChapterId) {
      if (tx != null) {
        tx.pendingChapterId = snapshot.chapterId;
        window.requestChapter(snapshot.chapterId);
      } else {
        consumeDelegate?.adoptChapter(snapshot.chapterId);
      }
    }
    final hasClients = scrollEffect?.hasClients ?? false;
    if (!hasClients) {
      return;
    }
    final max = scrollEffect!.maxScrollExtent;
    final offset = scrollEffect!.offset;
    if (max > 0 && max - offset < max * 0.35) {
      if (tx != null) {
        // 事务期间只记录挂起扩窗（方案 §32/§67），SETTLING 一次提交；
        // 事件仅在挂起翻转时发射一次（§103）。
        if (!tx.pendingExpandForward) {
          tx.pendingExpandForward = true;
          _emitWindowRequested(forward: true);
        }
      } else {
        _requestWindowExpand(forward: true);
        consumeDelegate?.expandWindow(forward: true);
      }
    }
    if (offset < 240) {
      if (tx != null) {
        if (!tx.pendingExpandBackward) {
          tx.pendingExpandBackward = true;
          _emitWindowRequested(forward: false);
        }
      } else {
        _requestWindowExpand(forward: false);
        consumeDelegate?.expandWindow(forward: false);
      }
    }
  }

  /// 空事务扩窗：意图记录进 WindowManager（§41）并按新意图发射一次事件。
  void _requestWindowExpand({required bool forward}) {
    final wasPending = forward ? window.pendingForward : window.pendingBackward;
    if (forward) {
      window.requestForward();
    } else {
      window.requestBackward();
    }
    if (!wasPending) {
      _emitWindowRequested(forward: forward);
    }
  }

  void _emitWindowRequested({required bool forward}) {
    emitEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.windowRequested,
        at: clock.now,
        blockIndex: forward ? 1 : 0,
      ),
    );
  }

  /// 逻辑位置确认（§28）：零字符章直达预取、测高收敛期漂移抑制、
  /// tracker 应用与阈值化持久化调度。
  void _confirmLogicalPosition(ReaderPositionSnapshot snapshot) {
    final delegate = consumeDelegate;
    if (delegate == null) {
      return;
    }
    // 图片主导的封面等章节 totalChars 为 0：不要用 charOffset=0 覆盖进度。
    final totalChars = delegate.totalCharsOf(snapshot.chapterId);
    if (totalChars <= 0) {
      delegate.preloadAdjacentAtTail();
      return;
    }
    delegate.preloadAdjacentThrottled();

    final charOffset = snapshot.charOffset;
    final newProgress = (charOffset / totalChars).clamp(0.0, 1.0);
    final currentProgress = delegate.currentChapterProgress;

    // 测高收敛期间（估算→精测分批替换），同一滚动位置的字符映射会来回
    // 漂移；前向滚动中的映射回退不是真实回滚（真实回滚 offset 必减小），
    // 抑制本次回写，避免进度显示与落库值在收敛期反复横跳。章节切换帧
    // （此前显示值属于旧章）与本章精测已完成时不抑制。
    final hasClients = scrollEffect?.hasClients ?? false;
    final offsetNow = hasClients ? scrollEffect!.offset : 0.0;
    final forwardScroll =
        lastResolvedOffset == null || offsetNow >= lastResolvedOffset! - 0.5;
    final wasSameChapter = lastResolvedProgressChapterId == snapshot.chapterId;
    final converging = delegate.isChapterHeightConverging(snapshot.chapterId);
    lastResolvedOffset = offsetNow;
    var applyPosition = true;
    if (converging &&
        forwardScroll &&
        wasSameChapter &&
        newProgress < currentProgress - 0.0005) {
      applyPosition = false;
      if (kDebugMode) {
        // 收敛期映射回退被抑制：这是图片/精测跳进度的首要诊断信号。
        readerDebugLog(
          'ReaderConsume: convergingDriftSuppressed '
          'chapter=${snapshot.chapterId} charOffset=$charOffset '
          'displayed=$currentProgress newProgress=$newProgress '
          'offsetNow=$offsetNow lastOffset=$lastResolvedOffset',
        );
      }
    }

    if (!applyPosition) {
      return;
    }
    lastResolvedProgressChapterId = snapshot.chapterId;
    delegate.confirmAppliedPosition(snapshot: snapshot, totalChars: totalChars);
    // 热路径：阈值避免滚动每帧都 schedule，降低写入与进度回写开销。
    if ((newProgress - currentProgress).abs() > 0.004 ||
        (snapshot.chapterId == anchorChapterId &&
            (charOffset - (_lastSavedScrollCharOffset ?? -1)).abs() >= 48)) {
      _lastSavedScrollCharOffset = charOffset;
      delegate.persistProgress(
        chapterId: snapshot.chapterId,
        charOffset: charOffset,
        chapterProgress: newProgress,
      );
    }
  }

  /// 方向性单调钳制（方案 §42-43）：事务活跃期间（dragging/ballistic/
  /// settling）同一单调规则，最后一道防线不污染持久化。
  double _applyDirectionalProgressClamp(
    double nextProgress,
    ReaderTransaction? tx,
  ) {
    if (tx == null || _scrollPhase == _RuntimeScrollPhase.idle) {
      return nextProgress;
    }
    return tx.forward
        ? math.max(tx.lastVisualProgress, nextProgress)
        : math.min(tx.lastVisualProgress, nextProgress);
  }

  /// 唯一视觉进度发布入口（方案 §44/§50）：整个模块只允许经
  /// ReaderVisualProgressPublisher 写 bookProgressNotifier。
  void _publishVisualProgress(ReaderTransaction? tx, double value) {
    if (tx != null) {
      tx.displayedProgress = value;
    }
    _lastPublishedVisualProgress = value;
    publisher.publish(value);
    emitEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.progressPublished,
        at: clock.now,
        transactionId: tx?.id ?? 0,
        visualProgress: value,
      ),
    );
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

  /// 消费管线页面供给（B3 §6.1）：initState 注入，见 [ReaderConsumeDelegate]。
  ReaderConsumeDelegate? consumeDelegate;

  /// 当前锚点章（B3 §6.3）：收养/切章/规范化统一经 set currentChapterId
  /// 同步到此处，是窗口意图判定的章节身份基准。
  String? anchorChapterId;

  /// 运行时身份（新方案 §57）：模式切换时更新。
  ReaderRuntimeIdentity? identity;

  /// 最近一次被接受的位置事实（B3 起只读，transient 投影；
  /// 供离场快照与诊断读取）。
  ReaderPositionSnapshot? get currentPosition => positionState.transient;

  /// 全书视觉进度表（方案 §81 自 Widget 迁入；idle 显示与视觉 seek 用）。
  final ReaderVisualExtentTable visualExtent = ReaderVisualExtentTable();

  /// 末次解析的章体视觉游标与所属章（视觉进度显示的事实源，§44）。
  double lastChapterVisualCursor = 0;

  String? lastVisualProgressChapterId;

  /// 收敛期守卫缓存（方案 §81）：上次解析的物理 offset 与章节身份。
  double? lastResolvedOffset;

  String? lastResolvedProgressChapterId;

  /// 持久化去重锚点（B3 §6.2 自页面迁入）：上次触发保存的 charOffset。
  int? _lastSavedScrollCharOffset;

  /// 最后一次发布的视觉进度（无事务的非 idle 帧保持该值，§25）。
  double _lastPublishedVisualProgress = 0;

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
