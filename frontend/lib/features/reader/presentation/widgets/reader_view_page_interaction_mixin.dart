import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scrolling_input.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
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
    // 优先取 GeometryStore 的 Live 快照（方案 §13）；未就绪时现建并
    // 经 Store 提交，保证 idle 解析与产线提交同一几何来源。
    final storeLive = runtime.geometry.live;
    final ReaderGeometrySnapshot geometry;
    if (storeLive != null && storeLive.revision == geometryRevision) {
      geometry = storeLive;
    } else {
      geometry = continuousScrollController.buildGeometrySnapshot();
      runtime.geometry.publishCandidate(geometry);
      runtime.geometry.commitCandidate();
    }
    final layout = ReaderLayoutSnapshot(
      geometry: geometry,
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
    final layout = tx?.layout ?? currentLiveLayout();
    final snapshot = runtime.position.resolve(
      scrollOffset: offset,
      layout: layout,
      transactionId: tx?.id ?? 0,
    );
    if (snapshot == null) {
      return;
    }
    _emitRuntimeEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.positionResolved,
        at: runtime.clock.now,
        transactionId: snapshot.transactionId,
        layoutRevision:
            '${snapshot.layoutRevision.geometryRevision}/'
            '${snapshot.layoutRevision.windowRevision}',
        offset: snapshot.scrollOffset,
        chapterId: snapshot.chapterId,
        blockIndex: snapshot.blockIndex,
        charOffset: snapshot.charOffset,
        visualProgress: runtime.progress.visual.project(
          snapshot,
          layout.geometry,
        ),
        logicalProgress: runtime.progress.logical.project(
          snapshot,
          layout.geometry,
        ),
      ),
    );
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

    // 事务同源校验（方案 §45-46/§85-§86）：旧事务/旧几何的回调直接
    // 丢弃，不再重新解释（DEBUG 断言之外也有运行时防线）。
    final tx = runtime.transactions.current;
    if (tx != null) {
      if (position.transactionId != tx.id) {
        runtime.diagnostics.stalePositionDropCount++;
        return;
      }
      if (position.layoutRevision.geometryRevision !=
          tx.layout.geometry.revision) {
        runtime.diagnostics.stalePositionDropCount++;
        if (kDebugMode) {
          readerDebugLog(
            'ReaderScroll: discard stale position tx=${tx.id} '
            'positionRevision=${position.layoutRevision.geometryRevision}',
          );
        }
        return;
      }
    }

    // 顺序滚动进入邻章：事务期间只记录挂起收养（方案 §31/§64），
    // SETTLING 一次提交——不得在用户滚动手势中途改写窗口几何。
    if (position.chapterId != currentChapterId) {
      if (tx != null) {
        tx.pendingChapterId = position.chapterId;
        runtime.window.requestChapter(position.chapterId);
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
      if (tx != null) {
        tx.forward = offsetNowForDirection >= tx.lastScrollOffset;
        tx.lastScrollOffset = offsetNowForDirection;
      }
      final double nextProgress;
      if (tx == null) {
        nextProgress = bookVisualProgressFor(
          position.chapterId,
          position.chapterVisualCursor,
        );
      } else {
        nextProgress =
            tx.visualMap.progressAt(
              (offsetNowForDirection + tx.layout.viewport.anchorY).clamp(
                0.0,
                double.infinity,
              ),
            ) ??
            tx.displayedProgress;
      }
      final displayed = _applyDirectionalProgressClamp(nextProgress);
      if (tx != null) {
        tx.lastVisualProgress = displayed;
      }
      publishVisualProgress(tx, displayed);
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
        runtime.lastResolvedOffset == null ||
        offsetNow >= runtime.lastResolvedOffset! - 0.5;
    final wasSameChapter =
        runtime.lastResolvedProgressChapterId == position.chapterId;
    final converging = !(chapterData?.hasPreciseHeights ?? true);
    runtime.lastResolvedOffset = offsetNow;
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
            'offsetNow=$offsetNow lastOffset=${runtime.lastResolvedOffset}',
      );
    }

    if (applyPosition) {
      runtime.lastResolvedProgressChapterId = position.chapterId;
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
        if (tx != null) {
          // 事务期间只记录挂起扩窗（方案 §32/§67），SETTLING 一次提交。
          tx.pendingExpandForward = true;
        } else {
          _throttledExpandForward();
        }
      }
      if (offset < 240) {
        if (tx != null) {
          tx.pendingExpandBackward = true;
        } else {
          _throttledExpandBackward();
        }
      }
    }
  }

  int? _lastSavedScrollCharOffset;
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

  // ── 滚动事务的 Page 侧残留（仅服务程序化滚动，B2 迁移后删除）──

  /// 最后一次发布的视觉进度（无事务的非 idle 帧保持该值，§25）。
  double _lastPublishedVisualProgress = 0;

  @override
  int get modeSwitchGeneration => _modeSwitchGeneration;

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

  /// 生命周期事件发射（方案 §103/§126）：debug 构建同步输出验收日志。
  void _emitRuntimeEvent(ReaderRuntimeEvent event) {
    runtime.eventLog.emit(event);
    if (kDebugMode) {
      readerDebugLog(runtime.eventLog.format(event));
    }
  }

  /// 事务唯一创建入口（方案 §25 原子切换）：取消旧事务（含在途
  /// Restore）并冻结新事务的几何/视口/进度映射；滚动状态（方向、
  /// 显示进度、视觉映射、挂起操作）全部由事务对象承载（§136 终态）。
  ReaderTransaction _beginScrollTransaction(ReaderTransactionKind kind) {
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
    _emitRuntimeEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.transactionStarted,
        at: runtime.clock.now,
        transactionId: tx.id,
        kind: tx.kind.name,
        layoutRevision:
            '${geometry.revision}/${continuousScrollController.windowRevision}',
        offset: tx.lastScrollOffset,
      ),
    );
    return tx;
  }

  /// SETTLING 提交（方案 §31-36/§37）：挂起的章节收养与窗口扩容一次完成，
  /// 随后重建窗口并应用单次锚点修正；事务在提交完成后才结束。
  void _commitScrollTransaction() {
    final tx = runtime.transactions.current;
    if (tx != null) {
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
    runtime.window.clearPending();
    runtime.window.pendingMetricUpdate = false;
    if (tx != null) {
      runtime.transactions.finish(tx.id);
      _emitRuntimeEvent(
        ReaderRuntimeEvent(
          type: ReaderRuntimeEventType.transactionCompleted,
          at: runtime.clock.now,
          transactionId: tx.id,
          kind: tx.kind.name,
        ),
      );
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
        // 拖动阈值信号：事务与相位决策在 Runtime（新方案 §5）。
        runtime.onPointerDragStarted();
      case ReaderScrollInputSource.keyboard:
        // 键盘无独立手势事件：事务由 scrollBy(kind: keyboard) 直接创建。
        break;
    }
  }

  /// 滚轮/触控板输入（新方案 §8）：只声明信号，burst 与事务决策在 Runtime。
  void onPointerScrollInput() {
    runtime.onWheelSignal();
  }

  /// 滚动期间的视觉进度：物理 Y 直接查冻结映射（方案 §22-24），
  /// 不经过 charOffset；无 Live fallback（§25-26）。
  double visualProgressDuringScroll(double contentY) {
    final tx = runtime.transactions.current;
    if (tx == null) {
      // 无事务（程序化滚动窗口期）：保持最后合法进度，绝不回退
      // Live Geometry 重新解释（方案 §25）。
      return _lastPublishedVisualProgress;
    }
    return tx.visualMap.progressAt(contentY.clamp(0.0, double.infinity)) ??
        tx.displayedProgress;
  }

  /// 唯一视觉进度发布入口（方案 §44/§50）：整个模块只允许经
  /// ReaderVisualProgressPublisher 写 bookProgressNotifier；旧会话的
  /// 回调按 id 丢弃（§45-46）。
  void publishVisualProgress(ReaderTransaction? tx, double value) {
    if (tx != null && runtime.transactions.current?.id != tx.id) {
      return;
    }
    if (tx != null) {
      tx.displayedProgress = value;
    }
    _lastPublishedVisualProgress = value;
    runtime.publisher.publish(value);
    _emitRuntimeEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.progressPublished,
        at: runtime.clock.now,
        transactionId: tx?.id ?? 0,
        visualProgress: value,
      ),
    );
  }

  /// 方向性单调钳制（方案 §42-43）：会话活跃期间（userDragging/
  /// ballistic/settling）同一单调规则，最后一道防线不污染持久化。
  double _applyDirectionalProgressClamp(double nextProgress) {
    final tx = runtime.transactions.current;
    if (tx == null || !runtime.isScrollBusy) {
      return nextProgress;
    }
    return tx.forward
        ? math.max(tx.lastVisualProgress, nextProgress)
        : math.min(tx.lastVisualProgress, nextProgress);
  }

  // ── 全书视觉进度表（D4：VisualProgress 与 LogicalProgress 语义独立） ──

  /// 末次解析的章体视觉游标与所属章（视觉进度显示的事实源）。
  double lastChapterVisualCursor = 0;
  String? lastVisualProgressChapterId;

  /// 全书视觉进度：章前缀视觉高度 + 当前章视觉游标，除以全书视觉总高。
  double bookVisualProgressFor(String chapterId, double chapterVisualCursor) {
    _ensureBookVisualExtentTable();
    return runtime.visualExtent.progressFor(chapterId, chapterVisualCursor) ??
        0;
  }

  /// 视觉进度条拖动 →（目标章，目标 charOffset）。
  ///
  /// 窗口内章经 Resolver 精确换算；窗口外章按视觉比例折算（与既有
  /// 字数比例换算同一精度级别），跳转仍走稳定的逻辑位置。
  (String, int)? resolveVisualSeekTarget(double ratio) {
    _ensureBookVisualExtentTable();
    final loader = contentLoader;
    if (loader == null) {
      return null;
    }
    final located = runtime.visualExtent.locate(ratio);
    if (located == null) {
      return null;
    }
    final chapterId = located.$1;
    final cursor = located.$2;

    final windowEntry = continuousScrollController.entryFor(chapterId);
    if (windowEntry != null) {
      final offset = continuousScrollController.resolver
          .charOffsetForVisualCursor(chapterId, cursor);
      if (offset != null) {
        return (chapterId, offset);
      }
    }
    final data = loader.getByChapterId(chapterId);
    final extent = runtime.visualExtent.extentFor(chapterId) ?? 0;
    if (data != null && data.totalChars > 0 && extent > 0) {
      final offset = (cursor / extent * data.totalChars).round().clamp(
        0,
        data.totalChars,
      );
      return (chapterId, offset);
    }
    return null;
  }

  /// 构建全书视觉进度表：窗口章用实测高度，缓存章用已测高度，其余按
  /// 已测「高度/字符」比率折算；窗口条目身份变化时重建。
  void _ensureBookVisualExtentTable() {
    final loader = contentLoader;
    final entries = continuousScrollController.entries;
    if (loader == null || entries.isEmpty) {
      return;
    }
    runtime.visualExtent.rebuildIfStale(
      cacheSource: entries,
      windowEntries: entries,
      chapterIds: loader.chapterIds,
      measuredHeightOf: (chapterId) {
        final entry = continuousScrollController.entryFor(chapterId);
        if (entry != null && entry.totalHeight > 0) {
          return entry.totalHeight;
        }
        final heights = loader.getByChapterId(chapterId)?.cumulativeHeights;
        if (heights != null && heights.isNotEmpty && heights.last > 0) {
          return heights.last;
        }
        return null;
      },
      charCountOf: charCountForChapter,
      fallbackExtent:
          ReaderContinuousScrollController.fallbackPlaceholderHeight,
    );
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
      'phase=${runtime.isInActiveGesture ? 'active' : (runtime.isScrollBusy ? 'settling' : 'idle')} '
      'chapter=${position.chapterId} charOffset=${position.charOffset} '
      'chapterProgress=${(chapterData != null && chapterData.totalChars > 0 ? position.charOffset / chapterData.totalChars : 0.0).toStringAsFixed(4)} '
      'visualBlock=${position.blockIndex} '
      'visualRatio=${position.blockRatio.toStringAsFixed(3)} '
      'visualCursor=${position.chapterVisualCursor.toStringAsFixed(1)} '
      'displayedProgress=${bookProgressNotifier.value.toStringAsFixed(4)} '
      'contentY=${position.contentY.toStringAsFixed(1)} '
      'geometryRevision=${position.layoutRevision.geometryRevision} '
      'txGeometryRevision=${runtime.transactions.current?.layout.geometry.revision} '
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
    // 扩窗意图经 WindowManager 记录（方案 §41/§42：请求与提交分离）。
    runtime.window.requestForward();
    _emitRuntimeEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.windowRequested,
        at: runtime.clock.now,
        blockIndex: 1,
      ),
    );
    onContinuousWindowExpand(forward: true);
    _expandForwardDebounce = Timer(const Duration(milliseconds: 600), () {
      _expandForwardInFlight = false;
    });
  }

  void _throttledExpandBackward() {
    if (_expandBackwardDebounce?.isActive ?? false) {
      return;
    }
    runtime.window.requestBackward();
    _emitRuntimeEvent(
      ReaderRuntimeEvent(
        type: ReaderRuntimeEventType.windowRequested,
        at: runtime.clock.now,
        blockIndex: 0,
      ),
    );
    onContinuousWindowExpand(forward: false);
    _expandBackwardDebounce = Timer(const Duration(milliseconds: 600), () {});
  }

  /// 释放滚动节流 Timer（由 State.dispose 调用）。
  void disposeScrollThrottles() {
    _preloadDebounce?.cancel();
    _expandForwardDebounce?.cancel();
    _expandBackwardDebounce?.cancel();
    runtime.dispose();
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
  void cancelOngoingRestoreForUserScroll() {
    if (runtime.restore.current != null) {
      _emitRuntimeEvent(
        ReaderRuntimeEvent(
          type: ReaderRuntimeEventType.restoreInvalidated,
          at: runtime.clock.now,
          charOffset: runtime.restore.generation,
        ),
      );
    }
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
    cancelOngoingRestoreForUserScroll();
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
    if (!runtime.isInActiveGesture) {
      cancelOngoingRestoreForUserScroll();
      _beginScrollTransaction(kind);
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
    if (!runtime.isInActiveGesture) {
      cancelOngoingRestoreForUserScroll();
      _beginScrollTransaction(kind);
    }
    scrollController.jumpTo(target);
    final tx = runtime.transactions.current;
    final snapshot = runtime.position.resolve(
      scrollOffset: scrollController.offset,
      layout: tx?.layout ?? currentLiveLayout(),
      transactionId: tx?.id ?? 0,
    );
    if (snapshot != null) {
      handleResolvedPosition(snapshot);
    }
    if (!runtime.isInActiveGesture) {
      _commitScrollTransaction();
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
    if (!runtime.isInActiveGesture) {
      cancelOngoingRestoreForUserScroll();
      _beginScrollTransaction(kind);
    }
    await scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !scrollController.hasClients) return true;
    // 键盘/侧点滚动不产生指针事件：主动按窗口控制器解析结果汇报位置，
    // 绕过"距上次指针事件 >2s"守卫的停更。
    final tx = runtime.transactions.current;
    final snapshot = runtime.position.resolve(
      scrollOffset: scrollController.offset,
      layout: tx?.layout ?? currentLiveLayout(),
      transactionId: tx?.id ?? 0,
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
        // 章节身份变更统一经收养提交入口（方案 §62/§63）。
        adoptContinuousAnchorChapter(resolved.chapterId);
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
