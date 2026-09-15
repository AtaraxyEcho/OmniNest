import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_consume_delegate.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_mode_switch.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scrolling_input.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_delegate.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_position_resolver.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读页面的滚动交互、设置应用与重新分页逻辑。
///
/// 消费管线行为已内化 Runtime（B3 §6.2/§6.3）：本 mixin 只做薄转发守卫
/// 并实现 [ReaderConsumeDelegate] 供给页面侧数据与动作。
mixin ReaderViewPageInteractionMixin
    on ConsumerState<ReaderViewPage>, ReaderViewPageMixin
    implements ReaderConsumeDelegate, ReaderRestoreDelegate {
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

    if (runtime.isRestoreBusy || isSwitchingChapter) {
      return;
    }

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
    // 优先取 GeometryStore 的 Live 快照（方案 §13）；Live 只能由
    // WindowBuilder 构建时装入（B4 只读化），此处不再补写 Store。
    final storeLive = runtime.geometryLive;
    final geometry =
        storeLive != null && storeLive.revision == geometryRevision
            ? storeLive
            : continuousScrollController.buildGeometrySnapshot();
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
  /// 页面只保留 Widget 生命周期与恢复期守卫，解析与消费全部内化 Runtime
  /// （B3 §6.2 onPhysicalOffsetChanged；B6 恢复期守卫统一为 isBusy 投影）。
  void onActualScrollOffsetChanged(double offset) {
    if (!mounted || isPageMode) return;
    if (runtime.isRestoreBusy || isSwitchingChapter) {
      return;
    }
    final now = runtime.clock.now;
    lastScrollActivityAt = now;
    dismissReturnSnackBar();
    runtime.onPhysicalOffsetChanged(offset);
  }

  // ── ReaderConsumeDelegate（B3 §6.3）：消费管线的页面供给，全部 1-3 行 ──

  @override
  int totalCharsOf(String chapterId) =>
      contentLoader?.getByChapterId(chapterId)?.totalChars ?? 0;

  @override
  bool isChapterHeightConverging(String chapterId) =>
      !(contentLoader?.getByChapterId(chapterId)?.hasPreciseHeights ?? true);

  @override
  void dismissReturnControl() => dismissReturnSnackBar();

  @override
  void preloadAdjacentAtTail() {
    if (!scrollController.hasClients) return;
    final max = scrollController.position.maxScrollExtent;
    if (max - scrollController.offset < max * 0.5) {
      preloadAdjacent();
    }
  }

  @override
  void preloadAdjacentThrottled() {
    if (!scrollController.hasClients) return;
    final max = scrollController.position.maxScrollExtent;
    if (max > 0 && max - scrollController.offset < max * 0.5) {
      _throttledPreloadAdjacent();
    }
  }

  @override
  void adoptChapter(String chapterId) =>
      adoptContinuousAnchorChapter(chapterId);

  @override
  void expandWindow({required bool forward}) {
    if (forward) {
      _throttledExpandForward();
    } else {
      _throttledExpandBackward();
    }
  }

  @override
  void confirmAppliedPosition({
    required ReaderPositionSnapshot snapshot,
    required int totalChars,
  }) {
    // 封面/空章不记账（原 updateFromScroll 的 totalChars 守卫语义）。
    if (totalChars > 0) {
      // 图片块无字符：锚点滑过图片时解析出的 charOffset 是块前缀
      // （章首图片恒 0），记账回退到 0 会污染最近文本位置（后续快照
      // 兜底与同章回灌判定都依赖它），跳过本次、保留上次文本位置。
      final blocks = contentLoader?.getByChapterId(snapshot.chapterId)?.blocks;
      final isImageBlock =
          blocks != null &&
          snapshot.blockIndex >= 0 &&
          snapshot.blockIndex < blocks.length &&
          blocks[snapshot.blockIndex] is ImageBlock;
      final tracked = runtime.logicalPosition;
      final zeroRegress =
          snapshot.charOffset <= 0 &&
          tracked.chapterId == snapshot.chapterId &&
          tracked.charOffset > 0;
      if (!isImageBlock || !zeroRegress) {
        runtime.acceptLogicalPosition(
          chapterId: snapshot.chapterId,
          charOffset: snapshot.charOffset,
        );
      }
    }
    _debugContinuousPosition(
      snapshot,
      contentLoader?.getByChapterId(snapshot.chapterId),
      event: 'positionApplied',
      detail:
          'chapterProgress=${totalChars > 0 ? snapshot.charOffset / totalChars : 0.0}',
    );
  }

  @override
  void persistProgress({
    required String chapterId,
    required int charOffset,
    required double chapterProgress,
  }) {
    // 热路径：只更新通知器；写盘经 coordinator 合并（阈值判定在 Runtime）。
    scrollProgress = chapterProgress;
    scheduleLocalProgressSave(
      chapterProgress: chapterProgress,
      mode: 'scroll',
      charOffset: charOffset,
    );
  }

  @override
  double visualProgressFallback(String chapterId, double chapterVisualCursor) =>
      bookVisualProgressFor(chapterId, chapterVisualCursor);

  @override
  void ensureVisualExtentTable() => _ensureBookVisualExtentTable();

  @override
  double get currentChapterProgress => scrollProgress;

  Timer? _preloadDebounce;
  Timer? _expandForwardDebounce;
  Timer? _expandBackwardDebounce;
  bool _expandForwardInFlight = false;

  // ── 模式切换事务（方案 §17-29）──

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

  /// Runtime Restore 编排的页面供给（B6 §7.2）：目标换算、用户滚动探针
  /// 与稳定回写在页面实现，Runtime 经 [ReaderRestoreDelegate] 调用。

  /// 恢复目标 → 窗口滚动 offset：charOffset>0 走 TextPainter 精度路径
  /// （§144），charOffset=0 语义为章首（章头贴视口顶）。布局或章节数据
  /// 未就绪返回 null，由引擎多帧重试。
  @override
  double? resolveRestoreOffset(ReaderPositionTarget target) {
    if (!scrollController.hasClients) {
      return null;
    }
    final max = scrollController.position.maxScrollExtent;
    if (max <= 0) {
      return null;
    }
    // 目标章未入窗（切章后窗口重锚定经 100ms 合并延迟，startRestore 可能
    // 先于重锚定启动）：等待窗口含目标章后再换算，前缀缺失静默落到 0
    // 会把恢复落点锚到错误章节顶部（错章根因之一）。
    if (continuousScrollController.entryFor(target.chapterId) == null) {
      return null;
    }
    if (target.charOffset <= 0) {
      // 章首落点只依赖目标章之前的窗口章高度（前缀），目标章之后的章
      // 不参与换算，不等待其精测，缩短 applying 期。
      final entries = continuousScrollController.entries;
      // 窗口内已有估算高度但未精测的章：逐个触发精测（幂等，内部
      // 批处理去重）；无高度数据的章（空块）不阻塞，避免死等。
      final pendingPrecise = <String>[];
      var reachedTarget = false;
      for (final e in entries) {
        if (reachedTarget) {
          break;
        }
        if (e.chapterId == target.chapterId) {
          reachedTarget = true;
        }
        final data = contentLoader?.getByChapterId(e.chapterId);
        if (data != null &&
            data.cumulativeHeights.isNotEmpty &&
            !data.hasPreciseHeights) {
          pendingPrecise.add(e.chapterId);
          contentLoader?.ensurePreciseHeights(
            e.chapterId,
            pageWidth: computePageWidth(),
            settings: settings,
            textScale: MediaQuery.textScalerOf(context).scale(1.0),
          );
        }
      }
      if (pendingPrecise.isNotEmpty) {
        if (kDebugMode) {
          readerDebugLog(
            'ReaderRestore: waiting precise heights '
            '(${pendingPrecise.join(',')})',
          );
        }
        return null;
      }
      return chapterStartScrollOffset(target.chapterId);
    }
    final data = contentLoader?.getByChapterId(target.chapterId);
    if (data == null || data.totalChars <= 0) {
      return null;
    }
    final intraY = contentLoader?.charOffsetToPixelOffset(
      target.chapterId,
      target.charOffset,
      pageWidth: computePageWidth(),
      settings: settings,
      textScale: MediaQuery.textScalerOf(context).scale(1.0),
    );
    // 章体在窗口中的起点 = 前缀 + 章头 chrome；charOffset 原点是章体顶。
    final windowY =
        continuousScrollController.prefixHeightOf(target.chapterId) +
        ReaderContinuousScrollController.chapterHeaderExtent +
        (intraY ?? 0.0);
    return windowY;
  }

  @override
  bool isUserScrollingSince(DateTime since) => isUserScrollActive(since: since);

  /// 稳定回写：tracker 记账并立即落库一次（视觉 seek 的即时持久化语义
  /// 统一到全部恢复站点；零进度由 scheduleLocalProgressSave 拦截）。
  @override
  void onRestoreSettled(ReaderPositionTarget target) {
    runtime.acceptLogicalPosition(
      chapterId: target.chapterId,
      charOffset: target.charOffset,
    );
    refreshBookProgressNow();
    final totalChars =
        contentLoader?.getByChapterId(target.chapterId)?.totalChars ?? 0;
    if (totalChars > 0) {
      scheduleLocalProgressSave(
        chapterProgress: (target.charOffset / totalChars).clamp(0.0, 1.0),
        charOffset: target.charOffset,
        mode: 'scroll',
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 生命周期事件发射统一走 Runtime Facade（B3 §6.3：页面不再自持发射器）。

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

  // ── 全书视觉进度表（D4：VisualProgress 与 LogicalProgress 语义独立） ──

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
      'txGeometryRevision=${runtime.currentTransaction?.layout.geometry.revision} '
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
    // 扩窗意图记录与事件发射在 Runtime（B3 §6.2），页面只执行节流扩挂。
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
      runtime.requestWindowCommit(force: true);
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
      runtime.requestWindowCommit(force: true);
      if (mounted) {
        setState(() {});
      }
    }());
  }

  /// 用户主动滚动前终止进行中的进度恢复。
  ///
  /// 恢复引擎在恢复期与监控期都会 jumpTo 锚点，会与本次滚动对抗，
  /// 导致滚动位移归零被误判为章末并触发跳章（方案 §59）。页面态清理
  /// 已随四态退役消失；_beginTransaction 内已调 manager.cancel。
  void cancelOngoingRestoreForUserScroll() {
    // 失效事件由 cancelRestorePhase 内化发射（§103）。
    if (runtime.restorePhaseTarget == null) {
      return;
    }
    runtime.cancelRestorePhase();
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
    final didScroll = await runtime.scrollBy(viewportDelta);
    if (didScroll) {
      unawaited(syncProgressAsync());
    }
    if (!mounted) return;
    if (!didScroll) {
      // 连续滚动窗口：先扩挂邻章再尝试；大章测高需更长等待。
      onContinuousWindowExpand(forward: forward);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      final again = await runtime.scrollBy(viewportDelta);
      if (again) {
        unawaited(syncProgressAsync());
      }
      if (!again && mounted) {
        onContinuousWindowExpand(forward: forward);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        final retry = await runtime.scrollBy(viewportDelta);
        if (retry) {
          unawaited(syncProgressAsync());
        }
        if (!retry && mounted) {
          tryNavigateChapter(forward ? 1 : -1);
        }
      }
    }
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
          savedCharOffset = runtime.logicalPosition.charOffset;
        }
      } else {
        savedCharOffset = runtime.logicalPosition.charOffset;
      }
    }
    // 模式切换事务开始（B7 请求化）：锚点一次冻结进请求，新切换使旧
    // 切换的在途定位回调整体失效。
    if (modeChanged) {
      runtime.changeMode(
        ReaderModeSwitchRequest(
          fromMode: settings.readingMode,
          toMode: newSettings.readingMode,
          chapterId: currentChapterId,
          anchorCharOffset: savedCharOffset,
        ),
      );
      if (kDebugMode) {
        readerDebugLog(
          'ReaderModeTxn: start ${settings.readingMode}→${newSettings.readingMode} '
          'anchor=$savedCharOffset',
        );
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
      if (kDebugMode) {
        readerDebugLog(
          'ApplySettings: modeChanged=$modeChanged, fontChanged=$fontChanged, '
          'immersiveChanged=$immersiveChanged, '
          'savedCharOffset=$savedCharOffset, isPageMode=$isPageMode',
        );
      }

      if (isPageMode) {
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
        runtime.requestWindowCommit();
        if (runtimeAnchor != null) {
          restoreRuntimeAnchor(runtimeAnchor);
        } else {
          restoreScrollPositionFromOffset(savedCharOffset);
        }
        // 滚动模式恢复期由 runtime.isRestoreBusy 守卫，切换请求即此终结。
        runtime.completeModeSwitch();
      }
    }

    if (mounted) {
      setState(() {});
    }
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
        charOffset: runtime.logicalPosition.charOffset,
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
      runtime.jumpToOffset(target, kind: ReaderTransactionKind.modeSwitch);
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
      // 页模式重排定位：相位接管即登记（B7 改造），旧滚动恢复一并取消。
      runtime.cancelRestorePhase();
      runtime.beginRestorePhase(
        ReaderPositionTarget(
          chapterId: currentChapterId,
          charOffset: restoreCharOffset,
        ),
      );
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
    restoreScrollPositionFromOffset(runtime.logicalPosition.charOffset);
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
        final trackedAnchor =
            runtime.modeSwitchAnchor ?? runtime.logicalPosition.charOffset;
        final anchor =
            trackedAnchor > 0
                ? trackedAnchor
                : computePageCharOffset(pageModePage);
        repaginateCurrentChapter(restoreCharOffset: anchor);
        return;
      }
      if (!widthChanged) {
        // 高度变化不改变换行；仅刷新窗口启发与布局。
        runtime.requestWindowCommit();
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
    var anchorCharOffset = runtime.logicalPosition.charOffset;
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
    runtime.acceptLogicalPosition(
      chapterId: currentChapterId,
      charOffset: anchorCharOffset,
    );
    runtime.requestWindowCommit();
    restoreScrollPositionFromOffset(anchorCharOffset);
    if (mounted) {
      setState(() {});
    }
  }

  /// 用指定 charOffset 恢复滚动位置（模式切换/重测高后）。
  ///
  /// 布局重算当帧窗口未收敛：恢复引擎逐帧重算目标，多帧重试自收敛。
  void restoreScrollPositionFromOffset(int charOffset) {
    if (charOffset <= 0) return;
    runtime.startRestore(
      ReaderPositionTarget(chapterId: currentChapterId, charOffset: charOffset),
    );
  }

  /// 重新分页所有章节。
  void repaginateAll() {
    contentLoader?.invalidateAll();
    repaginateCurrentChapter(
      restoreCharOffset: runtime.logicalPosition.charOffset,
    );
  }
}
