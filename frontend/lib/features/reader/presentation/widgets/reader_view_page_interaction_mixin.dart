import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scrolling_input.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_session.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 模式切换事务相位（方案 §19）。
enum ReaderModeSwitchPhase {
  /// 无切换事务。
  idle,

  /// 已捕获旧模式锚点，目标模式构建中。
  buildingTarget,

  /// 目标模式就绪，锚点恢复中。
  restoring,

  /// 切换失败，已统一退出。
  failed,
}

/// 阅读页面的滚动交互、设置应用与重新分页逻辑。
mixin ReaderViewPageInteractionMixin
    on ConsumerState<ReaderViewPage>, ReaderViewPageMixin {
  static const restoreSilenceMs = 400;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 滚动模式交互
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 滚动事件处理。
  void onScroll() {
    if (!scrollController.hasClients) return;
    if (isLoadingChapter) return;
    dismissReturnSnackBar();
    lastScrollActivityAt = DateTime.now();
    final max = scrollController.position.maxScrollExtent;
    if (max <= 0) return;

    if (restore.shouldSuppressWrites ||
        isRestoringProgress ||
        isSwitchingChapter) {
      return;
    }

    if (runtime.restore.isSilenced(runtime.clock.now)) return;

    // 连续滚动：进度由 ReaderContinuousScrollView 的 onScrollOffsetChanged
    // 上抛后经 Runtime 解析驱动。
    if (max - scrollController.offset < max * 0.5) {
      preloadAdjacent();
    }
  }

  /// Live 布局快照缓存（方案 §84 idle 路径）：按几何/窗口版本复用同一
  /// 不可变快照，保证 Resolver 快照视图缓存命中，滚动帧零拷贝。
  ReaderLayoutSnapshot? _cachedLiveLayout;
  int? _cachedLiveLayoutGeometryRevision;
  int? _cachedLiveLayoutWindowRevision;

  ReaderLayoutSnapshot currentLiveLayout() {
    final geometryRevision = continuousScrollController.geometryRevision;
    final windowRevision = continuousScrollController.windowRevision;
    final cached = _cachedLiveLayout;
    if (cached != null &&
        _cachedLiveLayoutGeometryRevision == geometryRevision &&
        _cachedLiveLayoutWindowRevision == windowRevision) {
      return cached;
    }
    final layout = ReaderLayoutSnapshot(
      geometry: continuousScrollController.buildGeometrySnapshot(),
      viewport: currentRuntimeViewport(),
      windowRevision: windowRevision,
    );
    _cachedLiveLayout = layout;
    _cachedLiveLayoutGeometryRevision = geometryRevision;
    _cachedLiveLayoutWindowRevision = windowRevision;
    return layout;
  }

  /// 实际滚动 offset 唯一入口（方案 §84/§87）：listener 只上抛 offset，
  /// 解析经 Runtime PositionResolver 完成；事务持有冻结布局，idle 用
  /// Live 布局快照；stale 事务回调按 §84 丢弃。
  void onActualScrollOffsetChanged(double offset) {
    if (!mounted || isPageMode) return;
    if (restore.shouldSuppressWrites ||
        isRestoringProgress ||
        isSwitchingChapter) {
      return;
    }
    final now = runtime.clock.now;
    if (runtime.restore.isSilenced(now)) return;
    lastScrollActivityAt = now;
    dismissReturnSnackBar();

    final tx = runtime.transactions.current;
    if (tx != null && tx.phase == ReaderTransactionPhase.cancelled) {
      return;
    }
    final session = _scrollSession;
    final ReaderLayoutSnapshot layout;
    final int transactionId;
    if (session != null && tx != null && tx.id == session.id) {
      layout = tx.layout;
      transactionId = tx.id;
    } else {
      layout = currentLiveLayout();
      transactionId = 0;
    }
    final snapshot = runtime.position.resolve(
      scrollOffset: offset,
      layout: layout,
      transactionId: transactionId,
    );
    if (snapshot == null) {
      return;
    }
    handleResolvedPosition(snapshot);
  }

  /// 以 Runtime 解析出的位置事实（方案 §5）更新锚点章、进度与邻章窗口。
  ///
  /// 滚动回调与程序化滚动（scrollBy / jumpToOffsetProgrammatic）共用：
  /// 键盘不产生指针事件，由程序化路径主动调用绕过指针守卫。
  void handleResolvedPosition(ReaderPositionSnapshot position) {
    dismissReturnSnackBar();

    final loader = contentLoader;
    if (loader == null) return;

    // 会话同源校验（方案 §45-46/§85）：生产模式下旧会话/旧几何的回调
    // 直接丢弃，不再重新解释（DEBUG 断言之外也有运行时防线）。
    final session = _scrollSession;
    if (session != null) {
      if (!runtime.transactions.isCurrent(session.id)) {
        runtime.diagnostics.stalePositionDropCount++;
        return;
      }
      // 方案 §26/§86：位置快照的布局版本必须与事务布局一致。
      if (position.layoutRevision.geometryRevision !=
          session.geometry.revision) {
        runtime.diagnostics.stalePositionDropCount++;
        if (kDebugMode) {
          readerDebugLog(
            'ReaderScroll: discard stale position session=${session.id} '
            'positionRevision=${position.layoutRevision.geometryRevision}',
          );
        }
        return;
      }
    }

    // 顺序滚动进入邻章：会话期间只记录挂起收养（方案 §31），
    // SETTLING 一次提交——不得在用户滚动手势中途改写窗口几何。
    if (position.chapterId != currentChapterId) {
      if (session != null) {
        // 会话/事务期间只记录挂起收养（方案 §31/§64），SETTLING 一次提交。
        runtime.transactions.current?.pendingChapterId = position.chapterId;
      } else {
        adoptContinuousAnchorChapter(position.chapterId);
      }
    }

    // 视觉进度实时更新：物理 Y 直接查会话冻结映射（方案 §22-24），
    // 图片内部滚动连续变化；收敛期抑制仅约束逻辑进度，不限制视觉进度。
    lastChapterVisualCursor = position.chapterVisualCursor;
    lastVisualProgressChapterId = position.chapterId;
    if (!isPageMode) {
      final offsetNowForDirection =
          scrollController.hasClients ? scrollController.offset : 0.0;
      if (session != null) {
        session.forward = offsetNowForDirection >= session.lastScrollOffset;
        session.lastScrollOffset = offsetNowForDirection;
      }
      final nextProgress =
          session == null
              ? bookVisualProgressFor(
                position.chapterId,
                position.chapterVisualCursor,
              )
              : session.visualMap.progressAt(
                    (offsetNowForDirection + session.viewport.anchorY).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ) ??
                  session.displayedProgress;
      final displayed = _applyDirectionalProgressClamp(nextProgress);
      if (session != null) {
        session.lastVisualProgress = displayed;
      }
      publishVisualProgress(session, displayed);
    }

    // 图片主导的封面等章节 totalChars 为 0：不要用 charOffset=0 覆盖进度。
    final chapterData = loader.getByChapterId(position.chapterId);
    final totalChars = chapterData?.totalChars ?? 0;
    if (totalChars <= 0) {
      if (scrollController.hasClients) {
        final max = scrollController.position.maxScrollExtent;
        if (max - scrollController.offset < max * 0.5) {
          preloadAdjacent();
        }
      }
      return;
    }

    // 连续滚动：以窗口控制器的块级映射为准，避免与 contentYToCharOffset 双路径不一致。
    final charOffset = position.charOffset;
    final newProgress = (charOffset / totalChars).clamp(0.0, 1.0);

    // 测高收敛期间（估算→精测分批替换），同一滚动位置的字符映射会来回
    // 漂移；前向滚动中的映射回退不是真实回滚（真实回滚 offset 必减小），
    // 抑制本次回写，避免进度显示与落库值在收敛期反复横跳。章节切换帧
    // （此前显示值属于旧章）与本章精测已完成时不抑制。
    final offsetNow =
        scrollController.hasClients ? scrollController.offset : 0.0;
    final forwardScroll =
        _lastResolvedOffset == null || offsetNow >= _lastResolvedOffset! - 0.5;
    final wasSameChapter = _lastResolvedProgressChapterId == position.chapterId;
    final converging = !(chapterData?.hasPreciseHeights ?? true);
    _lastResolvedOffset = offsetNow;
    var applyPosition = true;
    if (converging &&
        forwardScroll &&
        wasSameChapter &&
        newProgress < scrollProgress - 0.0005) {
      applyPosition = false;
      // 收敛期映射回退被抑制：这是图片/精测跳进度的首要诊断信号。
      _debugContinuousPosition(
        position,
        chapterData,
        event: 'convergingDriftSuppressed',
        detail:
            'displayed=$scrollProgress newProgress=$newProgress '
            'offsetNow=$offsetNow lastOffset=$_lastResolvedOffset',
      );
    }

    if (applyPosition) {
      _lastResolvedProgressChapterId = position.chapterId;
      positionTracker.updateFromScroll(
        offset: scrollController.hasClients ? scrollController.offset : 0,
        maxExtent:
            scrollController.hasClients
                ? scrollController.position.maxScrollExtent
                : 0,
        totalChars: totalChars,
        chapterId: position.chapterId,
        charOffset: charOffset,
      );
      if ((newProgress - scrollProgress).abs() > 0.004 ||
          (position.chapterId == currentChapterId &&
              (charOffset - (_lastSavedScrollCharOffset ?? -1)).abs() >= 48)) {
        // 热路径：只更新通知器；写盘经 coordinator 合并。
        // 阈值避免滚动每帧都 schedule，降低写入与 noteOwnProgressSave 开销。
        scrollProgress = newProgress;
        _lastSavedScrollCharOffset = charOffset;
        scheduleLocalProgressSave(
          chapterProgress: newProgress,
          mode: 'scroll',
          charOffset: charOffset,
        );
        _debugContinuousPosition(
          position,
          chapterData,
          event: 'positionApplied',
          detail: 'chapterProgress=$newProgress',
        );
      }
    }

    if (scrollController.hasClients) {
      final max = scrollController.position.maxScrollExtent;
      final offset = scrollController.offset;
      if (max > 0 && max - offset < max * 0.5) {
        _throttledPreloadAdjacent();
      }
      if (max > 0 && max - offset < max * 0.35) {
        if (_scrollSession != null) {
          // 事务期间只记录挂起扩窗（方案 §32/§67），SETTLING 一次提交。
          runtime.transactions.current?.pendingExpandForward = true;
        } else {
          _throttledExpandForward();
        }
      }
      if (offset < 240) {
        if (_scrollSession != null) {
          runtime.transactions.current?.pendingExpandBackward = true;
        } else {
          _throttledExpandBackward();
        }
      }
    }
  }

  /// 会话期间物理 offset 相对上次汇报是否发生了可判方向的变化。
  bool offsetNowForDirectionDelta(ReaderScrollSession session) {
    return true;
  }

  int? _lastSavedScrollCharOffset;
  double? _lastResolvedOffset;
  String? _lastResolvedProgressChapterId;
  Timer? _preloadDebounce;
  Timer? _expandForwardDebounce;
  Timer? _expandBackwardDebounce;
  bool _expandForwardInFlight = false;

  // ── 模式切换事务（方案 §17-29）──

  /// 同一时刻只有一个模式切换事务有效；旧回调按代次丢弃。
  int _modeSwitchGeneration = 0;
  ReaderModeSwitchPhase _modeSwitchPhase = ReaderModeSwitchPhase.idle;

  /// 模式切换统一提交入口：清除全部切换期状态，进入 idle。
  void completeModeSwitchGeneration(int generation) {
    if (generation != _modeSwitchGeneration) {
      return;
    }
    if (_modeSwitchPhase == ReaderModeSwitchPhase.idle) {
      return;
    }
    _modeSwitchPhase = ReaderModeSwitchPhase.idle;
    modeSwitchInProgress = false;
    modeSwitchAnchor = null;
    isRestoringProgress = false;
    if (kDebugMode) {
      readerDebugLog('ReaderModeTxn: commit generation=$generation');
    }
  }

  /// 模式切换统一失败退出：不能只清 isRestoringProgress（方案 §28），
  /// 否则可能遗留 modeSwitchAnchor / modeSwitchInProgress / pendingRestore。
  void abortModeSwitchGeneration(int generation) {
    if (generation != _modeSwitchGeneration) {
      return;
    }
    if (kDebugMode) {
      readerDebugLog('ReaderModeTxn: abort generation=$generation');
    }
    completeModeSwitchGeneration(generation);
  }

  // ── 滚动相位与事务会话（方案 §4-7/§21-§26）──

  ReaderScrollPhase _scrollPhase = ReaderScrollPhase.idle;
  Timer? _settleToIdleTimer;
  Timer? _wheelIdleTimer;

  /// 当前滚动会话（方案 §9/§20/§136）：会话是事务的冻结快照视图，
  /// 生命周期与 ReaderTransactionManager 中的事务一一对应；null = idle。
  ReaderScrollSession? _scrollSession;

  /// 最后一次发布的视觉进度（无会话的非 idle 帧保持该值，§25）。
  double _lastPublishedVisualProgress = 0;

  @override
  int get modeSwitchGeneration => _modeSwitchGeneration;

  @override
  ReaderScrollPhase get scrollPhase => _scrollPhase;

  @override
  bool get isScrollPhaseActive =>
      _scrollPhase == ReaderScrollPhase.userDragging ||
      _scrollPhase == ReaderScrollPhase.ballistic;

  @override
  ReaderScrollSession? get scrollSession => _scrollSession;

  /// 相位转移入口：指针拖动超阈值 → active，ScrollEnd → settling。
  /// ScrollNotification 不创建会话（程序化滚动同样产生通知，方案 §35）。
  @override
  void onScrollPhaseChanged(ReaderScrollPhase phase) {
    if (_scrollPhase == phase) {
      return;
    }
    _scrollPhase = phase;
    if (phase == ReaderScrollPhase.userDragging) {
      _beginScrollTransaction(ReaderTransactionKind.userDrag);
      return;
    }
    if (phase == ReaderScrollPhase.settling) {
      // 滚轮/触控板 burst 存续期间（§30）ScrollEnd 逐 tick 到达，
      // 不在此提交，统一由 burst 空闲超时一次提交。
      if (_isWheelBurstOngoing) {
        return;
      }
      // ScrollEnd：挂起收养/扩窗 + 一次 metrics 提交 + 最多一次修正
      // （方案 §25/§31-36）。
      _commitScrollSession();
      _settleToIdleTimer?.cancel();
      _settleToIdleTimer = Timer(const Duration(milliseconds: 150), () {
        if (_scrollPhase == ReaderScrollPhase.settling) {
          _scrollPhase = ReaderScrollPhase.idle;
        }
      });
    }
  }

  bool get _isWheelBurstOngoing {
    final tx = runtime.transactions.current;
    if (tx == null ||
        (tx.kind != ReaderTransactionKind.wheel &&
            tx.kind != ReaderTransactionKind.touchpad)) {
      return false;
    }
    return _wheelIdleTimer?.isActive ?? false;
  }

  /// 当前冻结视口快照（方案 §8：完整布局上下文一次冻结）。
  @override
  ReaderViewportSnapshot currentRuntimeViewport() {
    final size = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final layout = ReaderControlLayout.resolve(
      viewport: size,
      fontSize: settings.fontSize,
      textScale: textScale,
    );
    return ReaderViewportSnapshot(
      viewportSize: size,
      anchorY: viewportAnchorY,
      contentWidth: layout.textColumnWidth,
      textScale: textScale,
      safeAreaTop: settings.immersiveMode ? 0.0 : viewPadding.top,
      safeAreaBottom: viewPadding.bottom,
    );
  }

  /// Runtime Restore 事务创建（方案 §55/§96）：恢复入口统一登记目标。
  @override
  ReaderRestoreTransaction beginRuntimeRestore(ReaderPositionTarget target) {
    return runtime.restore.begin(
      target: target,
      layout: ReaderLayoutSnapshot(
        geometry: continuousScrollController.buildGeometrySnapshot(),
        viewport: currentRuntimeViewport(),
        windowRevision: continuousScrollController.windowRevision,
      ),
      itemId: itemId,
      readingMode: settings.readingMode,
    );
  }

  /// 事务会话唯一创建入口（方案 §25 原子切换）：取消旧事务（含在途
  /// Restore）并冻结新事务的几何/视口/进度映射。
  ReaderScrollSession _beginScrollTransaction(ReaderTransactionKind kind) {
    _ensureBookVisualExtentTable();
    runtime.restore.cancel();
    final geometry = continuousScrollController.buildGeometrySnapshot();
    final viewport = currentRuntimeViewport();
    final tx = runtime.transactions.beginOrReplace(
      kind: kind,
      layout: ReaderLayoutSnapshot(
        geometry: geometry,
        viewport: viewport,
        windowRevision: continuousScrollController.windowRevision,
      ),
      initialOffset:
          scrollController.hasClients ? scrollController.offset : 0.0,
      initialVisualProgress: bookProgressNotifier.value,
    );
    final session = ReaderScrollSession(
      id: tx.id,
      geometry: geometry,
      viewport: viewport,
      visualMap: ReaderVisualProgressMap.fromGeometry(geometry),
      initialScrollOffset: tx.lastScrollOffset,
      initialVisualProgress: tx.lastVisualProgress,
    );
    if (kDebugMode) {
      readerDebugLog(
        'ReaderTx: tx=${tx.id} started kind=${tx.kind.name} '
        'geometry=${geometry.revision}/${continuousScrollController.windowRevision} '
        'anchorY=${viewport.anchorY.toStringAsFixed(1)}',
      );
    }
    return session;
  }

  /// SETTLING 提交（方案 §31-36/§37）：挂起的章节收养与窗口扩容一次完成，
  /// 随后重建窗口并应用单次锚点修正；事务在提交完成后才结束。
  void _commitScrollSession() {
    final session = _scrollSession;
    final tx = runtime.transactions.current;
    if (session != null && tx != null) {
      final pendingChapter = tx.pendingChapterId;
      if (pendingChapter != null && pendingChapter != currentChapterId) {
        adoptContinuousAnchorChapter(pendingChapter);
      }
      if (tx.pendingExpandForward) {
        onContinuousWindowExpand(forward: true);
      }
      if (tx.pendingExpandBackward) {
        onContinuousWindowExpand(forward: false);
      }
    }
    commitPendingContinuousMetrics();
    _scrollSession = null;
    if (tx != null) {
      runtime.transactions.finish(tx.id);
      if (kDebugMode) {
        readerDebugLog('ReaderTx: tx=${tx.id} completed kind=${tx.kind.name}');
      }
    }
  }

  /// 滚动输入适配器（方案 §89/§137）：原生事件经适配器归一为输入源后
  /// 进入事务入口；输入源不携带位置信息。
  late final ReaderScrollInputAdapter scrollInput = ReaderScrollInputAdapter(
    onInput: _onScrollInput,
  );

  void _onScrollInput(ReaderScrollInputSource source) {
    switch (source) {
      case ReaderScrollInputSource.mouseWheel:
      case ReaderScrollInputSource.touchpad:
        onPointerScrollInput();
      case ReaderScrollInputSource.pointerDrag:
        // 拖动阈值由视图驱动相位转移；事务在 userDragging 中原子创建，
        // 重复通知被相位守卫吸收。
        onScrollPhaseChanged(ReaderScrollPhase.userDragging);
      case ReaderScrollInputSource.keyboard:
        // 键盘无独立手势事件：事务由 scrollBy(kind: keyboard) 直接创建。
        break;
    }
  }

  /// 滚轮/触控板输入（方案 §29-§31）：Pointer Event 只声明输入来源，
  /// 不推算位置；burst 内复用同一事务，200ms 无事件进入 SETTLING。
  void onPointerScrollInput() {
    final tx = runtime.transactions.current;
    // 用户拖动拥有当前坐标系，滚轮信号不抢占（§23 单一 active 事务）。
    if (tx != null &&
        tx.kind == ReaderTransactionKind.userDrag &&
        isScrollPhaseActive) {
      return;
    }
    _cancelOngoingRestoreForUserScroll();
    final session = _scrollSession;
    if (session == null ||
        tx == null ||
        (tx.kind != ReaderTransactionKind.wheel &&
            tx.kind != ReaderTransactionKind.touchpad)) {
      _scrollSession = _beginScrollTransaction(ReaderTransactionKind.wheel);
    }
    _wheelIdleTimer?.cancel();
    _wheelIdleTimer = Timer(const Duration(milliseconds: 200), () {
      if (_scrollPhase == ReaderScrollPhase.idle) {
        _commitScrollSession();
      }
    });
  }

  /// 滚动期间的视觉进度：物理 Y 直接查冻结映射（方案 §22-24），
  /// 不经过 charOffset；无 Live fallback（§25-26）。
  double visualProgressDuringScroll(double contentY) {
    final session = _scrollSession;
    if (session == null) {
      // 非 idle 且无会话（程序化滚动窗口期）：保持最后合法进度，
      // 绝不回退 Live Geometry 重新解释（方案 §25）。
      return _lastPublishedVisualProgress;
    }
    return session.visualMap.progressAt(contentY.clamp(0.0, double.infinity)) ??
        session.displayedProgress;
  }

  /// 唯一视觉进度发布入口（方案 §44/§50）：整个模块只允许经
  /// ReaderVisualProgressPublisher 写 bookProgressNotifier；旧会话的
  /// 回调按 id 丢弃（§45-46）。
  void publishVisualProgress(ReaderScrollSession? session, double value) {
    if (session != null && _scrollSession?.id != session.id) {
      return;
    }
    if (session != null) {
      session.displayedProgress = value;
    }
    _lastPublishedVisualProgress = value;
    runtime.publisher.publish(value);
  }

  /// 方向性单调钳制（方案 §42-43）：会话活跃期间（userDragging/
  /// ballistic/settling）同一单调规则，最后一道防线不污染持久化。
  double _applyDirectionalProgressClamp(double nextProgress) {
    final session = _scrollSession;
    if (session == null || _scrollPhase == ReaderScrollPhase.idle) {
      return nextProgress;
    }
    return session.forward
        ? math.max(session.lastVisualProgress, nextProgress)
        : math.min(session.lastVisualProgress, nextProgress);
  }

  // ── 全书视觉进度表（D4：VisualProgress 与 LogicalProgress 语义独立） ──

  /// 末次解析的章体视觉游标与所属章（视觉进度显示的事实源）。
  double lastChapterVisualCursor = 0;
  String? lastVisualProgressChapterId;
  List<ContinuousChapterEntry>? _visualExtentCacheSource;
  List<String> _visualExtentChapterIds = const [];
  List<double> _visualExtentStarts = const [];
  double _visualExtentTotal = 0;

  /// 全书视觉进度：章前缀视觉高度 + 当前章视觉游标，除以全书视觉总高。
  ///
  /// 视觉进度基于窗口几何而非 maxScrollExtent（动态窗口下后者不可用）；
  /// 图片内部滚动时连续变化，逻辑进度可以保持不变。
  double bookVisualProgressFor(String chapterId, double chapterVisualCursor) {
    _ensureBookVisualExtentTable();
    if (_visualExtentTotal <= 0 || _visualExtentChapterIds.isEmpty) {
      return 0;
    }
    final idx = _visualExtentChapterIds.indexOf(chapterId);
    if (idx < 0) {
      return 0;
    }
    final start = _visualExtentStarts[idx];
    final end =
        idx + 1 < _visualExtentStarts.length
            ? _visualExtentStarts[idx + 1]
            : _visualExtentTotal;
    final extent = end - start;
    return ((start + chapterVisualCursor.clamp(0.0, extent)) /
            _visualExtentTotal)
        .clamp(0.0, 1.0);
  }

  /// 视觉进度条拖动 →（目标章，目标 charOffset）。
  ///
  /// 窗口内章经 Resolver 精确换算；窗口外章按视觉比例折算（与既有
  /// 字数比例换算同一精度级别），跳转仍走稳定的逻辑位置。
  (String, int)? resolveVisualSeekTarget(double ratio) {
    _ensureBookVisualExtentTable();
    final loader = contentLoader;
    if (loader == null ||
        _visualExtentTotal <= 0 ||
        _visualExtentChapterIds.isEmpty) {
      return null;
    }
    final target = ratio.clamp(0.0, 1.0) * _visualExtentTotal;
    var idx = 0;
    while (idx < _visualExtentChapterIds.length - 1 &&
        target >= _visualExtentStarts[idx + 1]) {
      idx++;
    }
    final chapterId = _visualExtentChapterIds[idx];
    final chapterStart = _visualExtentStarts[idx];
    final chapterEnd =
        idx + 1 < _visualExtentStarts.length
            ? _visualExtentStarts[idx + 1]
            : _visualExtentTotal;
    final cursor = (target - chapterStart).clamp(
      0.0,
      chapterEnd - chapterStart,
    );

    final windowEntry = continuousScrollController.entryFor(chapterId);
    if (windowEntry != null) {
      final offset = continuousScrollController.resolver
          .charOffsetForVisualCursor(chapterId, cursor);
      if (offset != null) {
        return (chapterId, offset);
      }
    }
    final data = loader.getByChapterId(chapterId);
    if (data != null && data.totalChars > 0 && chapterEnd > chapterStart) {
      final offset = (cursor / (chapterEnd - chapterStart) * data.totalChars)
          .round()
          .clamp(0, data.totalChars);
      return (chapterId, offset);
    }
    return null;
  }

  /// 构建/复用全书视觉进度表：窗口章用实测高度，缓存章用已测高度，
  /// 其余按已测「高度/字符」比率折算；窗口条目身份变化时重建。
  void _ensureBookVisualExtentTable() {
    final loader = contentLoader;
    final entries = continuousScrollController.entries;
    if (loader == null || entries.isEmpty) {
      return;
    }
    if (identical(_visualExtentCacheSource, entries)) {
      return;
    }
    _visualExtentCacheSource = entries;
    double measuredExtent = 0;
    var measuredChars = 0;
    for (final entry in entries) {
      if (entry.totalChars > 0 && entry.isReady && entry.totalHeight > 0) {
        measuredExtent += entry.totalHeight;
        measuredChars += entry.totalChars;
      }
    }
    final heightPerChar =
        measuredChars > 0 ? measuredExtent / measuredChars : 0.0;
    final ids = <String>[];
    final starts = <double>[];
    var running = 0.0;
    for (final id in loader.chapterIds) {
      ids.add(id);
      starts.add(running);
      running += _chapterVisualExtentOf(id, heightPerChar);
    }
    _visualExtentChapterIds = ids;
    _visualExtentStarts = starts;
    _visualExtentTotal = running;
  }

  double _chapterVisualExtentOf(String chapterId, double heightPerChar) {
    final entry = continuousScrollController.entryFor(chapterId);
    if (entry != null && entry.totalHeight > 0) {
      return entry.totalHeight;
    }
    final data = contentLoader?.getByChapterId(chapterId);
    final heights = data?.cumulativeHeights;
    if (heights != null && heights.isNotEmpty && heights.last > 0) {
      return heights.last;
    }
    final chars = charCountForChapter(chapterId);
    if (chars != null && chars > 0 && heightPerChar > 0) {
      return chars * heightPerChar;
    }
    return ReaderContinuousScrollController.fallbackPlaceholderHeight;
  }

  /// 章节字数由 ReaderViewPageMixin 抽象提供（builders 实现）。

  /// 连续滚动位置诊断快照（D0 观测）。
  void _debugContinuousPosition(
    ReaderPositionSnapshot position,
    ChapterData? chapterData, {
    required String event,
    String? detail,
  }) {
    readerDebugLog(
      'ReaderContinuousPosition: $event '
      'phase=${_scrollPhase.name} '
      'chapter=${position.chapterId} charOffset=${position.charOffset} '
      'chapterProgress=${(chapterData != null && chapterData.totalChars > 0 ? position.charOffset / chapterData.totalChars : 0.0).toStringAsFixed(4)} '
      'visualBlock=${position.blockIndex} '
      'visualRatio=${position.blockRatio.toStringAsFixed(3)} '
      'visualCursor=${position.chapterVisualCursor.toStringAsFixed(1)} '
      'displayedProgress=${bookProgressNotifier.value.toStringAsFixed(4)} '
      'contentY=${position.contentY.toStringAsFixed(1)} '
      'geometryRevision=${position.layoutRevision.geometryRevision} '
      'sessionGeometryRevision=${_scrollSession?.geometry.revision} '
      'layoutVersion=${chapterData?.layoutVersion} '
      'precise=${chapterData?.hasPreciseHeights} '
      'windowStart=${continuousScrollController.prefixHeightOf(position.chapterId).toStringAsFixed(1)} '
      'windowEnd=${continuousScrollController.totalHeight.toStringAsFixed(1)}'
      '${detail == null ? '' : ' | $detail'}',
    );
  }

  void _throttledPreloadAdjacent() {
    if (_preloadDebounce?.isActive ?? false) {
      return;
    }
    preloadAdjacent();
    _preloadDebounce = Timer(const Duration(milliseconds: 400), () {});
  }

  void _throttledExpandForward() {
    if (_expandForwardInFlight || (_expandForwardDebounce?.isActive ?? false)) {
      return;
    }
    _expandForwardInFlight = true;
    onContinuousWindowExpand(forward: true);
    _expandForwardDebounce = Timer(const Duration(milliseconds: 600), () {
      _expandForwardInFlight = false;
    });
  }

  void _throttledExpandBackward() {
    if (_expandBackwardDebounce?.isActive ?? false) {
      return;
    }
    onContinuousWindowExpand(forward: false);
    _expandBackwardDebounce = Timer(const Duration(milliseconds: 600), () {});
  }

  /// 释放滚动节流 Timer（由 State.dispose 调用）。
  void disposeScrollThrottles() {
    _preloadDebounce?.cancel();
    _expandForwardDebounce?.cancel();
    _expandBackwardDebounce?.cancel();
    _settleToIdleTimer?.cancel();
    _wheelIdleTimer?.cancel();
  }

  /// 顺序滚动进入邻章：只更新锚点，不重建整棵阅读树。
  void adoptContinuousAnchorChapter(String chapterId) {
    if (chapterId == currentChapterId) return;
    // 加载中改写 currentChapterId 会使在途 loadCurrentChapter 判定失效；
    // 但若正文/块均已就绪，仍允许收养，避免封面章后锚点卡死。
    if (isLoadingChapter || isSwitchingChapter) {
      final ready =
          contentLoader?.getByChapterId(chapterId) != null &&
          contentLoader?.contentFor(chapterId) != null;
      if (!ready) {
        return;
      }
    }
    // 就绪判定通过后经统一提交入口收养：收养不得绕过位置状态收口。
    commitChapterAdoption(chapterId);
  }

  /// 连续滚动窗口扩挂：以窗口边缘章为基准预取并重建。
  void onContinuousWindowExpand({required bool forward}) {
    if (!mounted || isPageMode) return;
    final loader = contentLoader;
    if (loader == null) return;
    final chapterIds = loader.chapterIds;
    // 以窗口边缘而非 currentChapterId 为基准：锚点收养滞后时避免重复扩同一章。
    final windowIds = continuousScrollController.entries
        .map((e) => e.chapterId)
        .toList(growable: false);
    final edgeId =
        windowIds.isNotEmpty
            ? (forward ? windowIds.last : windowIds.first)
            : currentChapterId;
    final idx = chapterIds.indexOf(edgeId);
    if (idx < 0) return;
    final targetIndex = forward ? idx + 1 : idx - 1;
    if (targetIndex < 0 || targetIndex >= chapterIds.length) {
      return;
    }
    final targetId = chapterIds[targetIndex];
    final targetData = loader.getByChapterId(targetId);
    if (targetData != null) {
      // blocks 已就绪：只补滚动测高（未就绪时），不重取正文 HTML。
      if (!loader.isScrollLayoutReady(targetId)) {
        loader.ensureScrollLayoutForNeighbors(
          edgeId,
          pageWidth: computePageWidth(),
          settings: settings,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
        );
      }
      invalidateContinuousWindowFingerprint();
      rebuildContinuousWindow();
      return;
    }
    unawaited(() async {
      await prefetchChapter(targetId);
      if (!mounted) return;
      loader.ensureScrollLayoutForNeighbors(
        edgeId,
        pageWidth: computePageWidth(),
        settings: settings,
        textScale: MediaQuery.textScalerOf(context).scale(1.0),
      );
      invalidateContinuousWindowFingerprint();
      rebuildContinuousWindow();
      if (mounted) {
        setState(() {});
      }
    }());
  }

  /// 用户主动滚动前终止进行中的进度恢复。
  ///
  /// ScrollRestore 在恢复期与监控期都会 jumpTo 锚点，会与本次滚动对抗，
  /// 导致滚动位移归零被误判为章末并触发跳章；同时清掉恢复遮罩，
  /// 并使 Runtime 层的 Restore 事务失效（方案 §59）。
  void _cancelOngoingRestoreForUserScroll() {
    runtime.restore.cancel();
    if (!restore.shouldSuppressWrites && !isRestoringProgress) {
      return;
    }
    restore.cancel();
    isRestoringProgress = false;
    pendingChapterProgress = null;
    pendingRestoreCharOffset = null;
    if (mounted) {
      setState(() {});
    }
  }

  /// 侧边点击处理。
  Future<void> handleSideTap(
    ReaderItemDetail detail, {
    required bool forward,
  }) async {
    if (isSwitchingChapter || isLoadingChapter) return;
    _cancelOngoingRestoreForUserScroll();
    final viewportDelta =
        (forward ? 1 : -1) * MediaQuery.sizeOf(context).height * 0.8;
    final didScroll = await scrollBy(viewportDelta);
    if (!mounted) return;
    if (!didScroll) {
      // 连续滚动窗口：先扩挂邻章再尝试；大章测高需更长等待。
      onContinuousWindowExpand(forward: forward);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      final again = await scrollBy(viewportDelta);
      if (!again && mounted) {
        onContinuousWindowExpand(forward: forward);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        final retry = await scrollBy(viewportDelta);
        if (!retry && mounted) {
          tryNavigateChapter(forward ? 1 : -1);
        }
      }
    }
  }

  /// 程序化 animateTo（方案 §33/§34）：显式事务包裹动画滚动，动画结束
  /// 由 ScrollEnd/SETTLING 路径完成提交；用户手势进行中不抢占（§23）。
  Future<void> animateToOffsetProgrammatic(
    double targetOffset, {
    ReaderTransactionKind kind = ReaderTransactionKind.navigation,
  }) async {
    if (!scrollController.hasClients) {
      return;
    }
    final max = scrollController.position.maxScrollExtent;
    final target = targetOffset.clamp(0.0, max);
    if (!isScrollPhaseActive) {
      _cancelOngoingRestoreForUserScroll();
      _scrollSession = _beginScrollTransaction(kind);
    }
    await scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// 程序化 jumpTo（方案 §33）：显式事务包裹即时跳转，跳转后按事务冻结
  /// 几何解析位置并一次提交（§40 Commit 后重新 Resolve 同源口径）。
  void jumpToOffsetProgrammatic(
    double targetOffset, {
    ReaderTransactionKind kind = ReaderTransactionKind.layoutCorrection,
  }) {
    if (!scrollController.hasClients) {
      return;
    }
    final max = scrollController.position.maxScrollExtent;
    final target = targetOffset.clamp(0.0, max);
    if (!isScrollPhaseActive) {
      _cancelOngoingRestoreForUserScroll();
      _scrollSession = _beginScrollTransaction(kind);
    }
    scrollController.jumpTo(target);
    final session = _scrollSession;
    final tx = runtime.transactions.current;
    final ReaderLayoutSnapshot layout;
    final int transactionId;
    if (session != null && tx != null && tx.id == session.id) {
      layout = tx.layout;
      transactionId = tx.id;
    } else {
      layout = currentLiveLayout();
      transactionId = 0;
    }
    final snapshot = runtime.position.resolve(
      scrollOffset: scrollController.offset,
      layout: layout,
      transactionId: transactionId,
    );
    if (snapshot != null) {
      handleResolvedPosition(snapshot);
    }
    if (!isScrollPhaseActive) {
      _commitScrollSession();
    }
  }

  /// 滚动指定距离。返回 true 表示实际执行了滚动。
  ///
  /// [kind] 声明程序化滚动来源（方案 §33）：侧边点击 sideTap、键盘
  /// keyboard；滚动全程属于显式事务，不得伪装成用户滚动（§35）。
  Future<bool> scrollBy(
    double delta, {
    ReaderTransactionKind kind = ReaderTransactionKind.sideTap,
  }) async {
    if (!scrollController.hasClients) return false;
    final currentOffset = scrollController.offset;
    final max = scrollController.position.maxScrollExtent;
    final target = (currentOffset + delta).clamp(0.0, max);
    if ((target - currentOffset).abs() < 1.0) return false;
    // 程序化滚动开启显式事务并终止在途恢复（§59）；用户手势进行中
    // 不抢占其会话（§23 单一 active 事务）。
    if (!isScrollPhaseActive) {
      _cancelOngoingRestoreForUserScroll();
      _scrollSession = _beginScrollTransaction(kind);
    }
    await scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !scrollController.hasClients) return true;
    // 键盘/侧点滚动不产生指针事件：主动按窗口控制器解析结果汇报位置，
    // 绕过"距上次指针事件 >2s"守卫的停更。
    final scrollSession = _scrollSession;
    final tx = runtime.transactions.current;
    final ReaderLayoutSnapshot layout;
    final int transactionId;
    if (scrollSession != null && tx != null && tx.id == scrollSession.id) {
      layout = tx.layout;
      transactionId = tx.id;
    } else {
      layout = currentLiveLayout();
      transactionId = 0;
    }
    final snapshot = runtime.position.resolve(
      scrollOffset: scrollController.offset,
      layout: layout,
      transactionId: transactionId,
    );
    if (snapshot != null) {
      handleResolvedPosition(snapshot);
    }
    unawaited(syncProgressAsync());
    return true;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 设置变更
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 设置变更回调。
  void onSettingsChanged(ReaderViewSettings newSettings) {
    if (showControls) startHideTimer();
    if (isAnimating) {
      pendingSettings = newSettings;
      return;
    }
    applySettings(newSettings);
  }

  /// 动画完成后检查延迟的设置变更。
  void onAnimationComplete() {
    if (pendingSettings != null) {
      applySettings(pendingSettings!);
      pendingSettings = null;
    }
  }

  /// 应用阅读设置变更。
  void applySettings(ReaderViewSettings newSettings) {
    if (!supportsPageMode && newSettings.readingMode != 'scroll') {
      newSettings = newSettings.copyWith(readingMode: 'scroll');
    }

    final fontChanged =
        newSettings.fontSize != settings.fontSize ||
        newSettings.lineHeight != settings.lineHeight ||
        newSettings.fontFamily != settings.fontFamily;
    final modeChanged = newSettings.readingMode != settings.readingMode;
    final immersiveChanged =
        newSettings.immersiveMode != settings.immersiveMode;
    final layoutChanged = fontChanged || modeChanged || immersiveChanged;

    // 模式切换事务开始（方案 §19-20）：任何状态变更前先捕获旧模式锚点。
    if (modeChanged) {
      _modeSwitchGeneration++;
      _modeSwitchPhase = ReaderModeSwitchPhase.buildingTarget;
      if (kDebugMode) {
        readerDebugLog(
          'ReaderModeTxn: start generation=$_modeSwitchGeneration '
          '${settings.readingMode}→${newSettings.readingMode}',
        );
      }
    }
    final modeSwitchGeneration = _modeSwitchGeneration;

    // 冻结当前阅读锚点：优先从滚动位置计算（比 tracker 更精确），
    // 因为翻页模式的 onPageChanged 可能已将 tracker 更新为页首。
    int savedCharOffset = 0;
    if (layoutChanged) {
      if (!isPageMode &&
          scrollController.hasClients &&
          scrollController.position.maxScrollExtent > 0) {
        // 滚动模式：从实际滚动位置计算精确锚点（窗口坐标统一换算）
        savedCharOffset = windowContentYToCharOffset(
          currentChapterId,
          scrollController.offset + viewportAnchorY,
        );
        if (savedCharOffset <= 0) {
          savedCharOffset = positionTracker.charOffset;
        }
      } else {
        savedCharOffset = positionTracker.charOffset;
      }
    }

    if (immersiveChanged) {
      applyImmersiveMode(newSettings.immersiveMode);
      if (newSettings.immersiveMode) {
        hideTimer?.cancel();
        showControls = false;
      }
    }
    settings = newSettings;
    persistSettings(newSettings);

    if (layoutChanged) {
      if (modeChanged) {
        modeSwitchInProgress = true;
        // 冻结锚点，防止 onPageChanged 用页首覆盖
        modeSwitchAnchor = savedCharOffset;
      }

      if (kDebugMode) {
        readerDebugLog(
          'ApplySettings: modeChanged=$modeChanged, fontChanged=$fontChanged, '
          'immersiveChanged=$immersiveChanged, '
          'savedCharOffset=$savedCharOffset, isPageMode=$isPageMode',
        );
      }

      if (isPageMode) {
        _modeSwitchPhase = ReaderModeSwitchPhase.restoring;
        // 主动预热目标章分页（方案 §29）：不等用户交互触发。
        unawaited(warmChapterPages(currentChapterId, pageCount: 3));
        // 翻页跨章窗口内多章同步失效，避免邻章仍用旧排版分页。
        final windowIds =
            contentLoader?.chapterIds
                .where((id) {
                  final all = contentLoader?.chapterIds ?? const [];
                  final idx = all.indexOf(currentChapterId);
                  final i = all.indexOf(id);
                  return idx >= 0 && (i - idx).abs() <= 2;
                })
                .toList(growable: false) ??
            [currentChapterId];
        for (final id in windowIds) {
          contentLoader?.getByChapterId(id)?.invalidatePageNavigator();
        }
        contentLoader?.rekeyAndRecomputeHeights(
          currentChapterId,
          computePageWidth(),
          settings,
          MediaQuery.textScalerOf(context).scale(1.0),
          prepareScrollLayout: false,
        );
        repaginateCurrentChapter(restoreCharOffset: savedCharOffset);
      } else {
        // 运行时重排双锚点（§23/§24/§28）：变化前冻结视觉+逻辑位置，
        // 重排后一律优先按视觉锚点保持视口（§24 禁止 charOffset 反推
        // contentY）；视觉锚点不可解析时回退逻辑恢复（§23 状态回退）。
        final runtimeAnchor = _captureRuntimeAnchorForReflow();
        contentLoader?.rekeyAndRecomputeHeights(
          currentChapterId,
          computePageWidth(),
          settings,
          MediaQuery.textScalerOf(context).scale(1.0),
        );
        contentLoader?.ensureScrollLayoutForNeighbors(
          currentChapterId,
          pageWidth: computePageWidth(),
          settings: settings,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
        );
        rebuildContinuousWindow();
        if (runtimeAnchor != null) {
          restoreRuntimeAnchor(runtimeAnchor);
        } else {
          restoreScrollPositionFromOffset(savedCharOffset);
        }
        // 滚动模式恢复期由 isRestoringProgress 守卫，切换事务即此提交。
        _modeSwitchPhase = ReaderModeSwitchPhase.restoring;
        completeModeSwitchGeneration(modeSwitchGeneration);
      }
    }

    setState(() {});
  }

  /// 变化前冻结运行时双锚点（§23）：视觉锚点用于重排后按块内比例保持
  /// 视口；逻辑位置用于一致性确认与锚点不可解析时的状态回退。
  RuntimeAnchor? _captureRuntimeAnchorForReflow() {
    if (isPageMode || !scrollController.hasClients) {
      return null;
    }
    final visual = continuousScrollController.visualAnchorAt(
      scrollController.offset + viewportAnchorY,
    );
    final entry =
        visual == null
            ? null
            : continuousScrollController.entryFor(visual.chapterId);
    if (visual == null || entry == null) {
      return null;
    }
    if (visual.blockIndex < 0 || visual.blockIndex >= entry.blocks.length) {
      return null;
    }
    return RuntimeAnchor(
      visual: visual,
      logical: LogicalPosition(
        chapterId: currentChapterId,
        charOffset: positionTracker.charOffset,
      ),
      oldEntry: entry,
    );
  }

  /// 运行时重排后按冻结视觉锚点恢复：块内比例在新布局中保持。
  void restoreRuntimeAnchor(RuntimeAnchor anchor) {
    final remapped = continuousScrollController.remapVisualAnchor(
      anchor.visual,
      oldEntry: anchor.oldEntry,
    );
    final anchorY =
        remapped == null
            ? null
            : continuousScrollController.contentYForVisualAnchor(remapped);
    if (anchorY == null) {
      // 视觉锚点不可解析：回退逻辑恢复。
      restoreScrollPositionFromOffset(anchor.logical.charOffset);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      final max = scrollController.position.maxScrollExtent;
      final target = (anchorY - viewportAnchorY).clamp(0.0, max);
      jumpToOffsetProgrammatic(
        target,
        kind: ReaderTransactionKind.layoutCorrection,
      );
    });
  }

  /// 重新分页当前章节。
  void repaginateCurrentChapter({required int restoreCharOffset}) {
    final chapterData = contentLoader?.get(currentChapterId, settings);
    if (chapterData == null) return;

    if (isPageMode) {
      chapterData.invalidatePageNavigator();
      // 邻章分页器一并失效（页流窗口 ±2），保持窗口内页数与切片一致。
      final all = contentLoader?.chapterIds ?? const <String>[];
      final idx = all.indexOf(currentChapterId);
      if (idx >= 0) {
        for (var i = idx - 2; i <= idx + 2; i++) {
          if (i < 0 || i >= all.length) continue;
          contentLoader?.getByChapterId(all[i])?.invalidatePageNavigator();
        }
      }
      pageLocator.cancel();
      isRestoringProgress = true;
      pendingRestoreCharOffset = restoreCharOffset;
      setState(() {});
      return;
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    contentLoader?.rekeyAndRecomputeHeights(
      currentChapterId,
      computePageWidth(),
      settings,
      textScale,
    );
    restoreScrollPosition();
  }

  /// 恢复滚动位置（累积高度已由调用方重算）。
  void restoreScrollPosition() {
    restoreScrollPositionFromOffset(positionTracker.charOffset);
  }

  /// 视口变化时保持当前阅读锚点并重新分页/重测。
  void repaginateForViewportChange(Size newSize) {
    final previousSize = lastViewportSize;
    if (previousSize == newSize) return;
    final widthChanged =
        previousSize == null ||
        (previousSize.width - newSize.width).abs() > 0.5;
    lastViewportSize = newSize;
    pageViewportSize = newSize;
    if (contentLoader == null) return;
    repaginateTimer?.cancel();
    repaginateTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (isPageMode) {
        final trackedAnchor = modeSwitchAnchor ?? positionTracker.charOffset;
        final anchor =
            trackedAnchor > 0
                ? trackedAnchor
                : computePageCharOffset(pageModePage);
        repaginateCurrentChapter(restoreCharOffset: anchor);
        return;
      }
      if (!widthChanged) {
        // 高度变化不改变换行；仅刷新窗口启发与布局。
        rebuildContinuousWindow();
        return;
      }
      _repaginateContinuousForViewportWidth();
    });
  }

  /// 连续滚动：视口宽度变化后重测窗口内章节并恢复阅读锚点。
  void _repaginateContinuousForViewportWidth() {
    final loader = contentLoader;
    if (loader == null) return;
    // 先冻结当前锚点（优先真实滚动位置，避免 tracker 滞后）。
    var anchorCharOffset = positionTracker.charOffset;
    if (scrollController.hasClients &&
        scrollController.position.maxScrollExtent > 0) {
      // 锚点冻结统一经 Runtime PositionResolver（方案 §18/§134）。
      final resolved = runtime.position.resolve(
        scrollOffset: scrollController.offset,
        layout: currentLiveLayout(),
        transactionId: 0,
      );
      if (resolved != null) {
        anchorCharOffset = resolved.charOffset;
        if (resolved.chapterId != currentChapterId) {
          currentChapterId = resolved.chapterId;
          annotationHandler?.updateChapter(resolved.chapterId);
        }
      } else {
        final mapped = windowContentYToCharOffset(
          currentChapterId,
          scrollController.offset + viewportAnchorY,
        );
        if (mapped > 0) {
          anchorCharOffset = mapped;
        }
      }
    }
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final pageWidth = computePageWidth();
    final windowIds = continuousScrollController.entries
        .map((e) => e.chapterId)
        .toList(growable: false);
    loader.rekeyAndRecomputeHeightsForChapters(
      windowIds.isEmpty ? [currentChapterId] : windowIds,
      pageWidth,
      settings,
      textScale,
    );
    loader.ensureScrollLayoutForNeighbors(
      currentChapterId,
      pageWidth: pageWidth,
      settings: settings,
      textScale: textScale,
    );
    positionTracker.setCharOffset(anchorCharOffset, currentChapterId);
    rebuildContinuousWindow();
    restoreScrollPositionFromOffset(anchorCharOffset);
    if (mounted) {
      setState(() {});
    }
  }

  /// 用指定 charOffset 恢复滚动位置（模式切换专用）。
  void restoreScrollPositionFromOffset(int charOffset) {
    if (charOffset <= 0) return;
    isRestoringProgress = true;
    restoreSilenceUntil = DateTime.now().add(
      const Duration(milliseconds: restoreSilenceMs),
    );
    pendingChapterProgress = null;
    pendingRestoreCharOffset = charOffset;
  }

  /// 重新分页所有章节。
  void repaginateAll() {
    contentLoader?.invalidateAll();
    repaginateCurrentChapter(restoreCharOffset: positionTracker.charOffset);
  }
}
