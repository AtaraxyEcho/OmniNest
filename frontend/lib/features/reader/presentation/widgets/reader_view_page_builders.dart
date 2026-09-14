import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_invalidation.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_session.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_navigation_token.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_flow.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_return_to_progress_control.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';

/// reader_view_page.dart 的构建方法 mixin。
///
/// 通过 getter/setter 访问 State 字段，避免私有成员访问限制。
mixin ReaderViewPageBuilders on ConsumerState<ReaderViewPage> {
  bool _readerRebuildScheduled = false;
  bool _viewportUpdateScheduled = false;
  Size? _pendingViewportSize;
  bool _pageNavigatorWarmupScheduled = false;
  bool _scrollRestoreScheduled = false;
  bool _pageRestoreScheduled = false;
  ReaderProgressSnapshot? _pendingProgressSnapshot;
  bool _progressSnapshotApplyScheduled = false;

  /// 连续滚动窗口 fingerprint；未变化时跳过 rebuild，避免滚动热路径重建。
  int? _lastWindowFingerprint;
  bool _continuousWindowRebuilding = false;

  /// 窗口首尾章节及高度，用于滑窗时换算滚动偏移。
  String? _windowFirstChapterId;
  String? _windowLastChapterId;
  double _windowFirstChapterHeight = 0;

  /// 翻页跨章页流（当前章 ±2）。pageModePage 表示流内全局页索引。
  ReaderPageFlow? _pageFlow;

  /// 页流复用签名（方案 §47-48）：扩窗/排版变化才失效重建。
  bool _pageFlowInvalidated = true;
  String? _pageFlowSignatureAnchor;
  double? _pageFlowSignatureWidth;
  double? _pageFlowSignatureHeight;
  double? _pageFlowSignatureTextScale;
  ReaderViewSettings? _pageFlowSignatureSettings;

  /// 跨章收养后待映射的章内页；下一帧流重建时换算为全局索引。
  int? _pendingPageLocalIndex;
  double _windowLastChapterHeight = 0;

  void invalidateContinuousWindowFingerprint() {
    _lastWindowFingerprint = null;
  }

  // ── State 字段访问器（由 State 实现） ──
  ReaderContentLoader? get contentLoader;
  ReaderContinuousScrollController get continuousScrollController;
  ReaderPositionTracker get positionTracker;
  ScrollController get scrollController;
  ScrollRestore get restore;
  ReaderViewSettings get settings;
  String get currentChapterId;
  bool get isPageMode;
  int get pageModePage;
  set pageModePage(int value);
  bool get isRestoringProgress;
  set isRestoringProgress(bool value);
  DateTime get restoreSilenceUntil;
  set restoreSilenceUntil(DateTime value);
  double get scrollProgress;
  set scrollProgress(double value);
  double? get pendingChapterProgress;
  set pendingChapterProgress(double? value);
  int? get pendingRestoreCharOffset;
  set pendingRestoreCharOffset(int? value);
  DateTime get lastPointerDownTime;
  DateTime? get lastScrollActivityAt;
  set lastPointerDownTime(DateTime value);
  Size? get pageViewportSize;
  set pageViewportSize(Size? value);
  bool get showReturnControl;
  bool get showControls;

  /// 当前"返回原进度"浮层是否为远端进度同步入口（决定文案）。
  bool get returnControlIsRemoteOffer;
  bool get modeSwitchInProgress;
  set modeSwitchInProgress(bool value);
  int? get modeSwitchAnchor;
  set modeSwitchAnchor(int? value);
  int get restoreTargetCharOffset;
  set restoreTargetCharOffset(int value);
  bool get isSwitchingChapter;
  bool get isLoadingChapter;
  bool get selectionActive;
  ReaderChapterLoadCoordinator get chapterLoadCoordinator;
  ReaderPageLocator get pageLocator;
  dynamic get annotationHandler;
  String get itemId;
  ReaderPageTurnController get pageTurnController;
  ReaderNavigationTokenHolder get navigationTokens;

  // ── 跨 mixin 方法（由 State 实现） ──
  void dismissReturnSnackBar();
  void updateProgressFromPage();
  void onAnimationComplete();
  void tryNavigateChapter(int offset);
  void toggleControls();
  void returnToOriginalProgress();
  void onViewportChanged(Size newSize);
  Future<int?> findPageByCharOffset(ChapterData chapterData, int charOffset);
  Future<void> switchToChapter(
    String chapterId, {
    required ReaderChapterNavigationIntent intent,
  });
  void scheduleLocalProgressSave({
    required double chapterProgress,
    required int charOffset,
    required String mode,
  });
  void onReaderSelectionActive(bool active);
  DateTime? get lastAppliedProgressAt;
  void applyProgressSnapshot(ReaderProgressSnapshot snapshot);
  void onContinuousScrollPosition(ContinuousScrollPosition position);
  void onContinuousWindowExpand({required bool forward});
  void prefetchNextChapterAtBoundary(int pageIndex);
  void adoptPageModeChapter(String chapterId, {int localPageIndex = 0});
  Future<void> warmChapterPages(String chapterId, {int pageCount = 5});
  int windowContentYToCharOffset(String chapterId, double windowContentY);
  double chapterStartScrollOffset(String chapterId);
  void restoreToChapterStart(String chapterId);
  bool get pointerDownActive;
  set pointerDownActive(bool value);
  bool isUserScrollActive({required DateTime since});
  void onScrollPhaseChanged(ReaderScrollPhase phase);
  bool get isScrollPhaseActive;
  ReaderScrollSession? get scrollSession;
  int get modeSwitchGeneration;
  void completeModeSwitchGeneration(int generation);
  void abortModeSwitchGeneration(int generation);

  /// 当前冻结视口快照（由 interaction mixin 经 State 组合提供）。
  ReaderViewportSnapshot currentRuntimeViewport();

  /// Reading Runtime Facade（由 State 实现，方案 §83）。
  ReaderReadingRuntime get runtime;

  /// 滚轮/触控板输入入口（由 interaction mixin 经 State 组合提供）。
  void onPointerScrollInput();

  /// Runtime Restore 事务创建（方案 §55/§96，由 interaction mixin 实现）。
  ReaderRestoreTransaction beginRuntimeRestore(ReaderPositionTarget target);

  /// 程序化 jumpTo（方案 §33，由 interaction mixin 经 State 组合提供）。
  void jumpToOffsetProgrammatic(
    double targetOffset, {
    required ReaderTransactionKind kind,
  });

  // ── 页面尺寸 ──

  double computePageWidth() {
    final viewport = pageViewportSize;
    final size =
        viewport != null && viewport.width.isFinite
            ? viewport
            : MediaQuery.sizeOf(context);
    return ReaderControlLayout.resolve(
      viewport: size,
      fontSize: settings.fontSize,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    ).textColumnWidth;
  }

  double computePageHeight() {
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: settings.immersiveMode,
      isPageMode: isPageMode,
    );
    final viewport = pageViewportSize;
    if (viewport != null && viewport.height.isFinite) {
      final available = viewport.height - chromeLayout.chapterHeaderReserve - 1;
      return available > 1 ? available : 1;
    }
    final size = MediaQuery.sizeOf(context);
    final topInset =
        settings.immersiveMode ? 0.0 : MediaQuery.viewPaddingOf(context).top;
    final available =
        size.height - topInset - chromeLayout.viewportVerticalReserve;
    final contentHeight = available - chromeLayout.chapterHeaderReserve - 1;
    return contentHeight > 1 ? contentHeight : 1;
  }

  double get viewportAnchorY {
    final size = MediaQuery.sizeOf(context);
    final topInset =
        settings.immersiveMode ? 0.0 : MediaQuery.viewPaddingOf(context).top;
    return ReaderChromeLayout.anchorViewportY(
      viewportSize: size,
      immersiveMode: settings.immersiveMode,
      topInset: topInset,
    );
  }

  int computePageCharOffset(int pageIndex) {
    final flow = _pageFlow;
    final ref = flow?.keyAt(pageIndex);
    final chapterId = ref?.chapterId ?? currentChapterId;
    final localIndex = ref?.localPageIndex ?? pageIndex;
    final slice = contentLoader?.computePage(
      chapterId: chapterId,
      settings: settings,
      pageWidth: computePageWidth(),
      pageHeight: computePageHeight(),
      pageIndex: localIndex,
      textScale: MediaQuery.textScalerOf(context).scale(1.0),
    );
    return slice?.startCharOffset ?? 0;
  }

  /// 构建/刷新翻页跨章页流。返回流内锚点章起始全局索引。
  int _ensurePageFlow({
    required double pageWidth,
    required double pageHeight,
    required double textScale,
  }) {
    final loader = contentLoader;
    if (loader == null) {
      return 0;
    }
    // 锚点/排版/尺寸均未变化时复用现有页流（方案 §47-48）：
    // 普通同章翻页不再每次 build 重建页流与触发邻章分页。
    if (!_pageFlowInvalidated &&
        _pageFlow != null &&
        _pageFlowSignatureAnchor == currentChapterId &&
        _pageFlowSignatureWidth == pageWidth &&
        _pageFlowSignatureHeight == pageHeight &&
        _pageFlowSignatureTextScale == textScale &&
        _pageFlowSignatureSettings == settings) {
      return _pageFlow!.startIndexOf(currentChapterId) ?? 0;
    }
    final pendingLocal = _pendingPageLocalIndex;
    // 显式导航帧（切章锁定中）禁止旧页身份参与重映射：旧流 keyAt 可能
    // 解析出前缀章页面，把显式跳章拉回旧章（章节跳转错位的根因入口）。
    final explicitNavigation = isSwitchingChapter;
    final previousRef =
        pendingLocal == null && !explicitNavigation
            ? _pageFlow?.keyAt(pageModePage)
            : null;
    _pageFlow = ReaderPageFlow.fromLoader(
      loader: loader,
      anchorChapterId: currentChapterId,
      settings: settings,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      textScale: textScale,
      windowSide: 2,
    );
    pageModePage = _pageFlow!.resolveRebuiltPageIndex(
      anchorChapterId: currentChapterId,
      currentPage: pageModePage,
      previousRef: previousRef,
      pendingLocalIndex: pendingLocal,
      explicitNavigation: explicitNavigation,
    );
    _pageFlowInvalidated = false;
    _pageFlowSignatureAnchor = currentChapterId;
    _pageFlowSignatureWidth = pageWidth;
    _pageFlowSignatureHeight = pageHeight;
    _pageFlowSignatureTextScale = textScale;
    _pageFlowSignatureSettings = settings;
    // 目标章尚无页（数据未就绪）时保留待映射索引，待下帧重试锚定。
    if (pendingLocal != null &&
        _pageFlow!.startIndexOf(currentChapterId) != null) {
      _pendingPageLocalIndex = null;
    }
    return _pageFlow!.startIndexOf(currentChapterId) ?? 0;
  }

  /// 将翻页流锚定到目标章起始：写入待映射章内页 0，流已就绪时直接换算
  /// 全局索引。显式跳章禁止用 pageModePage=0 表达章首（跨章流中 0 可能
  /// 是窗口前缀章的页面）。
  void anchorPageModeToChapterStart(String chapterId) {
    _pendingPageLocalIndex = 0;
    final start = _pageFlow?.startIndexOf(chapterId);
    if (start != null) {
      pageModePage = start;
    }
  }

  /// 将流内全局页索引解析为章 + 章内页，并在跨章时软收养。
  void _handlePageFlowIndexChanged(int globalIndex) {
    final flow = _pageFlow;
    if (flow == null) {
      return;
    }
    final ref = flow.keyAt(globalIndex);
    if (ref == null) {
      return;
    }
    if (ref.chapterId != currentChapterId) {
      final before = currentChapterId;
      _pendingPageLocalIndex = ref.localPageIndex;
      adoptPageModeChapter(ref.chapterId);
      if (currentChapterId == before) {
        // 收养被拒绝（加载中且正文未就绪）：清空 pending，避免按旧章错映射。
        _pendingPageLocalIndex = null;
      }
    }
    pageModePage = globalIndex;
  }

  /// 翻页页索引唯一提交入口：页索引写入、跨章收养、进度更新、持久化
  /// 调度与边界预取在此一次完成，禁止多处重复修改状态。
  void _commitPageIndex(int index) {
    dismissReturnSnackBar();
    if (pageModePage != index) {
      final flowNow = _pageFlow;
      final chapterChanged =
          flowNow?.keyAt(index)?.chapterId !=
          flowNow?.keyAt(pageModePage)?.chapterId;
      pageModePage = index;
      _handlePageFlowIndexChanged(index);
      // 同章翻页不触发整体 rebuild（方案 §30-32）：页面内容已由
      // PageView 呈现，进度/持久化已就地完成；跨章收养由 adopt 调度。
      if (chapterChanged) {
        _requestReaderRebuild();
      }
    }
    if (modeSwitchInProgress) {
      modeSwitchInProgress = false;
      return;
    }
    // 加载/恢复/切章期间：页索引已提交（上方），进度写入推迟，
    // 避免加载窗口内 jumpToPage 触发的提交写脏进度。
    if (isRestoringProgress ||
        isSwitchingChapter ||
        isLoadingChapter ||
        chapterLoadCoordinator.isLoading) {
      return;
    }
    if (DateTime.now().isBefore(restoreSilenceUntil)) return;
    final flow = _pageFlow;
    // 模式切换期间（modeSwitchAnchor 未被用户交互消耗）：
    // 只更新展示进度，不写 tracker 和 SQLite。
    if (modeSwitchAnchor != null) {
      final chapterId = flow?.chapterIdAt(index) ?? currentChapterId;
      final chapterData = contentLoader?.get(chapterId, settings);
      if (chapterData != null && chapterData.totalChars > 0) {
        final charOffset = computePageCharOffset(index);
        scrollProgress = (charOffset / chapterData.totalChars).clamp(0.0, 1.0);
      }
      return;
    }
    updateProgressFromPage();
    final charOffset = computePageCharOffset(index);
    scheduleLocalProgressSave(
      chapterProgress: scrollProgress,
      mode: 'page',
      charOffset: charOffset,
    );
    onAnimationComplete();
    final localIndex = flow?.keyAt(index)?.localPageIndex ?? index;
    prefetchNextChapterAtBoundary(localIndex);
  }

  PageTurnMode parsePageTurnMode(String mode) {
    return switch (mode) {
      'cover' => PageTurnMode.cover,
      'fade' => PageTurnMode.fade,
      _ => PageTurnMode.slide,
    };
  }

  void _requestReaderRebuild() {
    if (!mounted) {
      return;
    }
    if (_readerRebuildScheduled) {
      return;
    }
    _readerRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readerRebuildScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void requestReaderRebuild() => _requestReaderRebuild();

  void clearPendingPageLocalIndex() => _pendingPageLocalIndex = null;

  void scheduleProgressSnapshotApply(ReaderProgressSnapshot snapshot) {
    final updatedAt = snapshot.updatedAt;
    if (updatedAt == null) {
      return;
    }
    final appliedAt = lastAppliedProgressAt;
    if (appliedAt != null && !updatedAt.isAfter(appliedAt)) {
      return;
    }
    final pendingAt = _pendingProgressSnapshot?.updatedAt;
    if (pendingAt != null && !updatedAt.isAfter(pendingAt)) {
      return;
    }
    _pendingProgressSnapshot = snapshot;
    if (_progressSnapshotApplyScheduled) {
      return;
    }
    _progressSnapshotApplyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _progressSnapshotApplyScheduled = false;
      final nextSnapshot = _pendingProgressSnapshot;
      _pendingProgressSnapshot = null;
      if (!mounted || nextSnapshot == null) {
        return;
      }
      final nextUpdatedAt = nextSnapshot.updatedAt;
      final currentAppliedAt = lastAppliedProgressAt;
      if (nextUpdatedAt == null ||
          (currentAppliedAt != null &&
              !nextUpdatedAt.isAfter(currentAppliedAt))) {
        return;
      }
      applyProgressSnapshot(nextSnapshot);
    });
  }

  void _scheduleViewportUpdate(Size viewportSize) {
    _pendingViewportSize = viewportSize;
    if (_viewportUpdateScheduled) {
      return;
    }
    _viewportUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportUpdateScheduled = false;
      final nextSize = _pendingViewportSize;
      _pendingViewportSize = null;
      if (!mounted || nextSize == null || pageViewportSize == nextSize) {
        return;
      }
      pageViewportSize = nextSize;
      onViewportChanged(nextSize);
    });
  }

  void _schedulePageNavigatorWarmup(
    PageNavigator navigator,
    int pageIndex,
    String chapterId,
  ) {
    if (_pageNavigatorWarmupScheduled) {
      return;
    }
    _pageNavigatorWarmupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageNavigatorWarmupScheduled = false;
      if (!mounted || currentChapterId != chapterId) {
        return;
      }
      navigator.ensurePage(0);
      navigator.schedulePrefetch(pageIndex, onPageReady: _requestReaderRebuild);
    });
  }

  // ── 翻页模式 ──

  Widget buildPageModeContent(ReaderChapterContent content) {
    final chapters = contentLoader?.allChapters ?? [];
    final chapterIdx = chapters.indexWhere((c) => c.id == currentChapterId);
    final currentChapter = chapterIdx >= 0 ? chapters[chapterIdx] : null;
    // 以 currentChapterId 解析标题，避免切章后仍用上一章 content.title。
    final chapterTitle =
        (currentChapter?.title.isNotEmpty == true)
            ? currentChapter!.title
            : (content.title.isNotEmpty ? content.title : '');

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final viewportSize = Size(
          constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : fallbackSize.width,
          constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : fallbackSize.height,
        );
        final viewportChanged = pageViewportSize != viewportSize;
        if (viewportSize.width.isFinite &&
            viewportSize.height.isFinite &&
            viewportChanged) {
          _scheduleViewportUpdate(viewportSize);
        }
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final pageLayout = ReaderControlLayout.resolve(
          viewport: viewportSize,
          fontSize: settings.fontSize,
          textScale: textScale,
        );
        final chromeLayout = ReaderChromeLayout.resolve(
          immersiveMode: settings.immersiveMode,
          isPageMode: true,
        );
        final pageWidth = pageLayout.textColumnWidth;
        final availablePageHeight =
            viewportSize.height - chromeLayout.chapterHeaderReserve - 1;
        final pageHeight = availablePageHeight > 1 ? availablePageHeight : 1.0;

        _ensurePageFlow(
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          textScale: textScale,
        );
        final flow = _pageFlow;
        // 空流兜底。
        if (flow != null && flow.readablePageCount == 0 && pageModePage != 0) {
          pageModePage = 0;
        }

        final data = contentLoader?.get(currentChapterId, settings);
        final navigator = data?.getOrCreatePageNavigator(
          pageWidth,
          pageHeight,
          settings,
          textScale: textScale,
        );
        if (navigator != null && data != null) {
          final localPage =
              flow?.keyAt(pageModePage)?.localPageIndex ?? pageModePage;
          _schedulePageNavigatorWarmup(navigator, localPage, data.chapterId);
        }

        if (pendingRestoreCharOffset != null && data != null) {
          _schedulePendingPageCharOffsetRestore(data);
        }

        final pageCount = flow?.readablePageCount ?? 0;
        final hasMore = flow?.needsProbe ?? true;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            lastPointerDownTime = DateTime.now();
            pointerDownActive = true;
            // 用户真实触摸：消耗模式切换冻结锚点
            if (modeSwitchAnchor != null) modeSwitchAnchor = null;
          },
          onPointerUp: (_) {
            pointerDownActive = false;
          },
          onPointerCancel: (_) {
            pointerDownActive = false;
          },
          child: ReaderPageView(
            // 固定 key：跨章软切换时不重挂载 PageView，翻页动画与手势连续。
            key: ValueKey('reader-page-flow-${settings.pageTurnMode}'),
            controller: pageTurnController,
            state: PagedState(
              chapterId: currentChapterId,
              pageIndex: pageModePage,
              pageCount: pageCount,
              hasMore: hasMore,
              hasPreviousChapter: chapterIdx > 0,
              hasNextChapter: chapterIdx < chapters.length - 1,
              // PageLocator.isLocating 不在此列（方案 §4）：后台定位恢复页
              // 属于 Restore/Seek 事务，不得剥夺普通翻页的执行资格；
              // 恢复期的进度写入由 isRestoringProgress 守卫。
              isPaginating:
                  isSwitchingChapter ||
                  isLoadingChapter ||
                  chapterLoadCoordinator.isLoading,
            ),
            selectionActive: selectionActive,
            pageBuilder: (index) {
              final pageRef = flow?.keyAt(index);
              if (pageRef != null) {
                final chapterId = pageRef.chapterId;
                final localIndex = pageRef.localPageIndex;
                final pageData = contentLoader?.get(chapterId, settings);
                if (pageData == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                // pageBuilder 只查缓存不触发分页（方案 §33/§36）：
                // 未预热页渲染占位，由 schedulePrefetch 异步补算后重建。
                final slice = contentLoader?.peekPage(
                  chapterId,
                  settings,
                  pageWidth: pageWidth,
                  pageHeight: pageHeight,
                  pageIndex: localIndex,
                  textScale: textScale,
                );
                if (slice == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (localIndex == 0 &&
                    isDedicatedCoverPage(blocks: pageData.blocks)) {
                  return ReaderCoverPage(
                    title:
                        pageData.content.title.isNotEmpty
                            ? pageData.content.title
                            : chapterTitle,
                    settings: settings,
                    visibleBlocks: _sliceVisibleBlocks(pageData, slice),
                    itemId: itemId,
                  );
                }
                final pageChapter =
                    contentLoader?.allChapters
                        .where((c) => c.id == chapterId)
                        .firstOrNull;
                final pageChapterTitle =
                    pageChapter?.title.isNotEmpty == true
                        ? pageChapter!.title
                        : chapterTitle;
                final showHeader = localIndex == 0;
                return buildPageContent(
                  pageData,
                  slice,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  chapterTitle: showHeader ? pageChapterTitle : null,
                );
              }

              // 探测页：优先续排本章下一页；否则尝试下一章首页。
              final probe = _buildProbePage(
                flow: flow,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                textScale: textScale,
                fallbackTitle: chapterTitle,
              );
              return probe;
            },
            callbacks: PageTurnCallbacksImpl(
              // 唯一页索引提交入口（方案 §9）：页索引、流归属、进度、
              // 持久化与预取全部经 _commitPageIndex 一次收口。
              onPageChangedFn: _commitPageIndex,
              onPreviousChapterFn: () {
                // 流内还有前页时优先在流内后退；确在流首再硬切上一章。
                if (pageModePage > 0) {
                  pageTurnController.previous();
                  return;
                }
                tryNavigateChapter(-1);
              },
              onNextChapterFn: () {
                final flowNow = _pageFlow;
                final readable = flowNow?.readablePageCount ?? 0;
                // 仅在已确认页内前进；到达末页后走扩窗，避免探测死循环。
                if (readable > 0 && pageModePage < readable - 1) {
                  pageTurnController.next();
                  return;
                }
                final chapters = contentLoader?.allChapters ?? const [];
                final lastId =
                    flowNow != null && flowNow.chapterIds.isNotEmpty
                        ? flowNow.chapterIds.last
                        : currentChapterId;
                final idx = chapters.indexWhere((c) => c.id == lastId);
                if (idx >= 0 && idx + 1 < chapters.length) {
                  unawaited(_expandPageFlowForward(chapters[idx + 1].id));
                  return;
                }
                tryNavigateChapter(1);
              },
              onToggleControlsFn: toggleControls,
            ),
            surfaceColor: settings.surfaceColor,
            turnMode: parsePageTurnMode(settings.pageTurnMode),
          ),
        );
      },
    );
  }

  /// 探测页内容：本章未分页完时续排下一页，否则尝试下一章首页。
  Widget? _buildProbePage({
    required ReaderPageFlow? flow,
    required double pageWidth,
    required double pageHeight,
    required double textScale,
    required String fallbackTitle,
  }) {
    final loader = contentLoader;
    if (loader == null) {
      return null;
    }
    Widget? renderChapterPage(
      String chapterId,
      int localIndex, {
      required String title,
    }) {
      final pageData = loader.get(chapterId, settings);
      if (pageData == null) {
        return null;
      }
      // Probe 只读缓存（方案 §37/§38）：未预热页不在此同步分页。
      final slice = loader.peekPage(
        chapterId,
        settings,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        pageIndex: localIndex,
        textScale: textScale,
      );
      if (slice == null) {
        unawaited(warmChapterPages(chapterId, pageCount: localIndex + 2));
        return null;
      }
      if (localIndex == 0 && isDedicatedCoverPage(blocks: pageData.blocks)) {
        return ReaderCoverPage(
          title:
              pageData.content.title.isNotEmpty
                  ? pageData.content.title
                  : title,
          settings: settings,
          visibleBlocks: _sliceVisibleBlocks(pageData, slice),
          itemId: itemId,
        );
      }
      return buildPageContent(
        pageData,
        slice,
        scrollPhysics: const NeverScrollableScrollPhysics(),
        chapterTitle: localIndex == 0 ? title : null,
      );
    }

    final windowLast =
        flow?.chapterIds.isNotEmpty == true ? flow!.chapterIds.last : null;
    if (windowLast != null && !(flow?.fullyPaginated[windowLast] ?? true)) {
      final nextLocal = flow?.readableCounts[windowLast] ?? 0;
      final rendered = renderChapterPage(
        windowLast,
        nextLocal,
        title: fallbackTitle,
      );
      if (rendered != null) {
        return rendered;
      }
    }

    final chapters = loader.chapterIds;
    final edge = windowLast ?? currentChapterId;
    final edgeIdx = chapters.indexOf(edge);
    if (edgeIdx >= 0 && edgeIdx + 1 < chapters.length) {
      final nextId = chapters[edgeIdx + 1];
      final rendered = renderChapterPage(nextId, 0, title: fallbackTitle);
      if (rendered != null) {
        // 探测成功：预热并准备下一帧把该章并入页流。
        unawaited(_expandPageFlowForward(nextId));
        return rendered;
      }
      // 未预热：异步预热完成后扩窗，点击链路不做同步分页（方案 §46）。
      unawaited(
        warmChapterPages(nextId, pageCount: 3).then((_) {
          if (mounted) {
            unawaited(_expandPageFlowForward(nextId));
          }
        }),
      );
    }
    return null;
  }

  /// 跨章页流前向扩窗：预热下一章正文与首页，重建后可直接续读。
  Future<void> _expandPageFlowForward(String chapterId) async {
    await warmChapterPages(chapterId, pageCount: 5);
    if (!mounted) {
      return;
    }
    _pageFlowInvalidated = true;
    _requestReaderRebuild();
    // 探测页翻转发生时页流尚未扩窗，keyAt 返回 null 会跳过跨章收养，
    // 目录高亮/进度章节滞后一页；扩窗完成后对当前页补一次归属解析。
    _handlePageFlowIndexChanged(pageModePage);
  }

  // ── 单页内容 ──

  /// PageSlice 的可见块：图片独占页的真实字符区间为零宽，只能按块
  /// 区间取内容。封面页与普通页共用，保证一页只有一个内容来源。
  List<ContentBlock> _sliceVisibleBlocks(ChapterData data, PageSlice slice) {
    if (slice.endCharOffset > slice.startCharOffset) {
      return BlockClipper.clipBlocksByCharRange(
        data.blocks,
        slice.startCharOffset,
        slice.endCharOffset,
      );
    }
    return BlockClipper.clipBlocksByIndexRange(
      data.blocks,
      slice.startIndex,
      slice.endIndex,
    );
  }

  Widget buildPageContent(
    ChapterData data,
    PageSlice slice, {
    ScrollPhysics? scrollPhysics,
    String? chapterTitle,
  }) {
    final blocks = _sliceVisibleBlocks(data, slice);

    bool isFirstBlockContinuation = false;
    if (blocks.isNotEmpty && slice.startCharOffset > 0) {
      var blockStart = 0;
      for (final block in data.blocks) {
        final blockEnd = blockStart + BlockClipper.blockCharCount(block);
        if (blockEnd > slice.startCharOffset) {
          if (blockStart < slice.startCharOffset &&
              (block is ParagraphBlock || block is BlockquoteBlock)) {
            isFirstBlockContinuation = true;
          }
          break;
        }
        blockStart = blockEnd;
      }
    }

    final content = ReaderViewContent(
      htmlContent: data.content.content,
      settings: settings,
      itemId: itemId,
      annotations: annotationHandler?.chapterAnnotations ?? [],
      visibleBlocks: blocks,
      rawBlocks: data.blocks,
      scrollPhysics: scrollPhysics,
      isFirstBlockContinuation: isFirstBlockContinuation,
      onHighlight: (text, start, end) {
        if (!mounted) return;
        annotationHandler?.highlight(text, start, end, context);
      },
      onAnnotate: (text, start, end) {
        if (!mounted) return;
        annotationHandler?.annotate(text, start, end, context);
      },
      onRemoveHighlight: (a) {
        if (!mounted) return;
        annotationHandler?.delete(a);
      },
      onRemoveAnnotation: (a) {
        if (!mounted) return;
        annotationHandler?.delete(a);
      },
      onLinkTap: handleReaderLinkTap,
      onSelectionActive: onReaderSelectionActive,
      // 翻页模式的点击热区由 ReaderPageView 顶层交互层统一分发，
      // 内容层再响应会与顶层各触发一次 toggleControls，两次取反导致
      // 点击中间无法弹出控制栏。
      onTap: null,
    );

    if (settings.immersiveMode ||
        chapterTitle == null ||
        chapterTitle.isEmpty) {
      return content;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
          child: buildChapterHeader(chapterTitle),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget buildChapterHeader(String chapterTitle) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final headerFontSize = (screenWidth * 0.02).clamp(13.0, 15.0);
    final labelColor = settings.onSurfaceColor.withValues(alpha: 0.35);
    return Text(
      chapterTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: headerFontSize,
        color: labelColor,
        height: 1.4,
        letterSpacing: 0.3,
      ),
    );
  }

  // ── 滚动模式 ──

  /// Build 期几何更新收敛调度（方案 §72）：同一帧多次请求合并为一次，
  /// 帧末在 build 之外执行重建；窗口实际变化时补一次页面重建同步
  /// 批注映射，无变化则静默终止，避免空转循环。
  bool _geometryRebuildRequested = false;

  void requestContinuousWindowRebuild() {
    if (_geometryRebuildRequested) {
      return;
    }
    _geometryRebuildRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryRebuildRequested = false;
      if (!mounted || isPageMode) {
        return;
      }
      if (isScrollPhaseActive) {
        // ACTIVE_SCROLL：窗口重建推迟到 ScrollEnd 一次提交（方案 §12）。
        runtime.window.pendingMetricUpdate = true;
        return;
      }
      final geometryBefore = continuousScrollController.geometryRevision;
      final windowBefore = continuousScrollController.windowRevision;
      rebuildContinuousWindow();
      final changed =
          continuousScrollController.geometryRevision != geometryBefore ||
          continuousScrollController.windowRevision != windowBefore;
      if (changed && mounted) {
        setState(() {});
      }
    });
  }

  /// 用 contentLoader 数据重建连续滚动窗口。
  ///
  /// build 热路径调用：fingerprint 未变化时整段跳过（含测高启动与 notify）。
  /// dropHtmlForNeighbors 由 setActive/loadChapter 负责，不在此处理。
  void rebuildContinuousWindow() {
    if (_continuousWindowRebuilding) {
      return;
    }
    if (isScrollPhaseActive) {
      // ACTIVE_SCROLL：窗口重建推迟到 ScrollEnd 一次提交（方案 §12），
      // 坐标系变化不得发生在用户滚动手势期间。
      runtime.window.pendingMetricUpdate = true;
      return;
    }
    final loader = contentLoader;
    if (loader == null) {
      return;
    }
    _continuousWindowRebuilding = true;
    try {
      final pageWidth = computePageWidth();
      final textScale = MediaQuery.textScalerOf(context).scale(1.0);
      final fingerprint = _computeWindowFingerprint(
        loader,
        pageWidth: pageWidth,
        textScale: textScale,
      );
      if (_lastWindowFingerprint == fingerprint &&
          !continuousScrollController.isEmpty) {
        return;
      }
      _lastWindowFingerprint = fingerprint;

      // 记录滑窗前首尾章，rebuild 后用高度差保持视口稳定。
      final prevFirstId = _windowFirstChapterId;
      final prevLastId = _windowLastChapterId;
      final prevFirstHeight = _windowFirstChapterHeight;
      final prevLastHeight = _windowLastChapterHeight;
      final prevEntries = continuousScrollController.entries;
      // 布局变化前捕获视觉锚点：变化后按同一锚点保持视口（P0-17），
      // 而非机械保持 offset 数值。
      final anchorBefore =
          scrollController.hasClients
              ? continuousScrollController.visualAnchorAt(
                scrollController.offset + viewportAnchorY,
              )
              : null;
      final oldAnchorEntry =
          anchorBefore == null
              ? null
              : continuousScrollController.entryFor(anchorBefore.chapterId);
      // 锚点在旧布局中的窗口内容坐标：应用期按"新布局位置 - 旧布局
      // 位置"的位移修正当前 offset，与用户滚动自然叠加，不再回拉。
      final anchorContentY =
          anchorBefore == null
              ? 0.0
              : scrollController.offset + viewportAnchorY;

      loader.ensureScrollLayoutForNeighbors(
        currentChapterId,
        pageWidth: pageWidth,
        settings: settings,
        textScale: textScale,
      );
      final fontSize = settings.fontSize;
      final lineHeight = settings.lineHeight;
      final previousPrefix =
          continuousScrollController.isEmpty
              ? null
              : continuousScrollController.prefixHeightOf(currentChapterId);
      continuousScrollController.rebuild(
        anchorChapterId: currentChapterId,
        allChapterIds: loader.chapterIds,
        estimateHeight: (chapterId) {
          // 优先用解析期 charCount 折算行数；无元数据时退回固定行数占位。
          final lineHeightPx = fontSize * lineHeight;
          final chars = _charCountForChapter(loader, chapterId);
          if (chars == null || chars <= 0) {
            return lineHeightPx * 20;
          }
          final fontSizeEff = math.max(12.0, fontSize);
          final charsPerLine = math.max(
            16,
            (pageWidth / (fontSizeEff * 0.95)).floor(),
          );
          final lines = (chars / charsPerLine).ceil();
          return lineHeightPx * math.max(8, lines) + 36;
        },
        resolve: (chapterId) {
          final data = loader.get(chapterId, settings);
          if (data == null) {
            return null;
          }
          final heights = data.cumulativeHeights;
          final isReady =
              heights.isNotEmpty && heights.length == data.blocks.length;
          var title = data.content.title;
          if (title.isEmpty) {
            for (final chapter in loader.allChapters) {
              if (chapter.id == chapterId) {
                title = chapter.title;
                break;
              }
            }
          }
          return ContinuousChapterEntry(
            chapterId: chapterId,
            title: title,
            blockCount: data.blocks.length,
            cumulativeHeights: heights,
            totalHeight:
                isReady
                    ? heights.last
                    : (data.blocks.isEmpty
                        ? ReaderContinuousScrollController
                            .fallbackPlaceholderHeight
                        : data.blocks.length * fontSize * lineHeight),
            totalChars: data.totalChars,
            isReady: isReady,
            blocks: data.blocks,
            blockCharPrefixes: data.blockCharPrefixes,
          );
        },
      );

      final nextEntries = continuousScrollController.entries;
      if (nextEntries.isNotEmpty) {
        _windowFirstChapterId = nextEntries.first.chapterId;
        _windowLastChapterId = nextEntries.last.chapterId;
        _windowFirstChapterHeight = nextEntries.first.totalHeight;
        _windowLastChapterHeight = nextEntries.last.totalHeight;
      }

      final windowSlid =
          prevFirstId != null &&
          (nextEntries.isEmpty ||
              nextEntries.first.chapterId != prevFirstId ||
              (prevLastId != null && nextEntries.last.chapterId != prevLastId));
      _compensateScrollForWindowSlide(
        prevEntries: prevEntries,
        prevFirstId: prevFirstId,
        prevLastId: prevLastId,
        prevFirstHeight: prevFirstHeight,
        prevLastHeight: prevLastHeight,
        anchorBefore: anchorBefore,
        oldAnchorEntry: oldAnchorEntry,
        anchorContentY: anchorContentY,
      );
      // 滑窗已按首尾高度补偿，勿再按锚点 prefix 二次修正。
      if (!windowSlid) {
        _compensateScrollForPrefixDelta(
          previousPrefix,
          anchorBefore: anchorBefore,
          oldAnchorEntry: oldAnchorEntry,
          anchorContentY: anchorContentY,
        );
      }
    } finally {
      _continuousWindowRebuilding = false;
    }
  }

  /// 窗口状态指纹：锚点 + 排版 + 视口宽度 + 窗口章 layoutVersion/高度末值。
  int _computeWindowFingerprint(
    ReaderContentLoader loader, {
    required double pageWidth,
    required double textScale,
  }) {
    var hash = Object.hash(
      currentChapterId,
      settings.fontSize,
      settings.lineHeight,
      settings.fontFamily,
      settings.immersiveMode,
      pageWidth,
      textScale,
    );
    final ids = [
      currentChapterId,
      ...loader.neighborChapterIds(
        currentChapterId,
        radius: kContinuousCacheRadius,
      ),
    ];
    for (final id in ids) {
      final data = loader.getByChapterId(id);
      final heights = data?.cumulativeHeights;
      // 不用 layoutVersion：精测分批会频繁 bump，导致每批整页 rebuild。
      final heightBucket =
          heights == null || heights.isEmpty
              ? -1.0
              : (heights.last / 64).roundToDouble() * 64;
      hash = Object.hash(
        hash,
        id,
        data?.blocks.length ?? 0,
        data?.totalChars ?? 0,
        data?.hasPreciseHeights ?? false,
        heightBucket,
      );
    }
    return hash;
  }

  /// 从解析元数据取章节字数；chapterIds 与 parsed.chapters 按序对齐。
  int? _charCountForChapter(ReaderContentLoader loader, String chapterId) {
    final parsed = ref.read(parsedBookProvider(itemId)).value;
    if (parsed == null || parsed.chapters.isEmpty) {
      return null;
    }
    final index = loader.chapterIds.indexOf(chapterId);
    if (index < 0 || index >= parsed.chapters.length) {
      // 兼容 chapter_N 形式 id。
      final match = RegExp(r'^chapter_(\d+)$').firstMatch(chapterId);
      if (match == null) {
        return null;
      }
      final n = int.tryParse(match.group(1)!);
      if (n == null || n < 0 || n >= parsed.chapters.length) {
        return null;
      }
      return parsed.chapters[n].charCount;
    }
    return parsed.chapters[index].charCount;
  }

  int? charCountForChapter(String chapterId) {
    final loader = contentLoader;
    if (loader == null) {
      return null;
    }
    return _charCountForChapter(loader, chapterId);
  }

  // ── 布局变化的视口保持统一入口（方案 §21/§22/§26/§31）──
  // ACTIVE_SCROLL：指针按住或 400ms 内有滚动活动。期间高度收敛类校正
  // 不抢视口，挂起为 pendingMetrics；SETTLING（滚动结束）后应用一次；
  // 坐标原点平移类（滑窗）不排队——拖动进新章时必须即时补偿，否则
  // 内容会在指下大幅位移。

  /// 布局变化后的视口保持：锚点保持优先，锚点不可解析时回退高度差。
  ///
  /// ACTIVE_SCROLL 期间一律不改视口（方案 §8-10，含滑窗）：布局变化
  /// 标记 dirty，ScrollEnd 后由 commitPendingContinuousMetrics 一次收敛。
  void _preserveVisualAnchorAfterLayoutChange({
    required VisualAnchor? anchorBefore,
    required ContinuousChapterEntry? oldAnchorEntry,
    required double fallbackDelta,
    required double anchorContentY,
  }) {
    if (!scrollController.hasClients) {
      return;
    }
    if (isScrollPhaseActive) {
      runtime.window.pendingMetricUpdate = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      if (isScrollPhaseActive) {
        runtime.window.pendingMetricUpdate = true;
        return;
      }
      _applyVisualCorrectionNow(
        anchorBefore: anchorBefore,
        oldAnchorEntry: oldAnchorEntry,
        fallbackDelta: fallbackDelta,
        anchorContentY: anchorContentY,
      );
    });
  }

  void commitPendingContinuousMetrics() {
    // ScrollEnd 一次收敛：清除挂起标记并重建窗口；窗口内部的锚点
    // 补偿（settling 相位允许）负责唯一一次视口修正。
    runtime.window.pendingMetricUpdate = false;
    rebuildContinuousWindow();
  }

  void _applyVisualCorrectionNow({
    required VisualAnchor? anchorBefore,
    required ContinuousChapterEntry? oldAnchorEntry,
    required double fallbackDelta,
    required double anchorContentY,
  }) {
    if (!scrollController.hasClients) {
      return;
    }
    final max = scrollController.position.maxScrollExtent;
    final remapped =
        anchorBefore == null
            ? null
            : continuousScrollController.remapVisualAnchor(
              anchorBefore,
              oldEntry: oldAnchorEntry,
            );
    final anchorY =
        remapped == null
            ? null
            : continuousScrollController.contentYForVisualAnchor(remapped);
    final double target;
    if (anchorY != null) {
      // 位移合成：锚点内容坐标在新旧布局间的位移量叠加到当前 offset。
      // 用户在捕获与应用之间的滚动已在当前 offset 中，若按绝对目标跳转
      // 会撤销用户滚动（慢滚回拉根因）；位移合成则两者自然叠加。
      final shift = anchorY - anchorContentY;
      target = (scrollController.offset + shift).clamp(0.0, max);
    } else {
      target = (scrollController.offset + fallbackDelta).clamp(0.0, max);
    }
    if ((target - scrollController.offset).abs() < 0.5) {
      return;
    }
    // 布局修正进入 LayoutCorrection 事务（方案 §21/§33）：修正性跳转
    // 不伪装成用户滚动。
    jumpToOffsetProgrammatic(
      target,
      kind: ReaderTransactionKind.layoutCorrection,
    );
  }

  /// 滑窗时保持视口：坐标原点平移类补偿，经统一入口即时执行；
  /// 锚点不可解析时回退首尾高度差补偿。
  void _compensateScrollForWindowSlide({
    required List<ContinuousChapterEntry> prevEntries,
    required String? prevFirstId,
    required String? prevLastId,
    required double prevFirstHeight,
    required double prevLastHeight,
    VisualAnchor? anchorBefore,
    ContinuousChapterEntry? oldAnchorEntry,
    required double anchorContentY,
  }) {
    if (prevEntries.isEmpty || !scrollController.hasClients) {
      return;
    }
    if (isRestoringProgress ||
        restore.shouldSuppressWrites ||
        isLoadingChapter ||
        isSwitchingChapter) {
      return;
    }
    final nextEntries = continuousScrollController.entries;
    if (nextEntries.isEmpty) {
      return;
    }
    final nextFirstId = nextEntries.first.chapterId;
    final nextLastId = nextEntries.last.chapterId;
    if (nextFirstId == prevFirstId && nextLastId == prevLastId) {
      return;
    }
    var delta = 0.0;
    // 卸载前缀章：滚动坐标原点后移，offset 需减小。
    if (prevFirstId != null && nextFirstId != prevFirstId) {
      delta -= prevFirstHeight;
    }
    // 在前部新增章：原点前移，offset 需增大。
    if (nextFirstId != prevFirstId) {
      for (final entry in nextEntries) {
        if (entry.chapterId == prevFirstId) {
          break;
        }
        if (prevEntries.every((e) => e.chapterId != entry.chapterId)) {
          delta += entry.totalHeight;
        }
      }
    }
    if (delta.abs() < 0.5 && anchorBefore == null) {
      return;
    }
    _preserveVisualAnchorAfterLayoutChange(
      anchorBefore: anchorBefore,
      oldAnchorEntry: oldAnchorEntry,
      fallbackDelta: delta,
      anchorContentY: anchorContentY,
    );
  }

  /// 前缀章高度变化或章内块重测高时补偿滚动偏移（高度收敛类）。
  ///
  /// 以布局变化前捕获的视觉锚点为中心：变化后重解析同一锚点的窗口
  /// 坐标（块内按比例保持），保持"用户看到的内容"不变。用户滚动期间
  /// （ACTIVE_SCROLL）校正挂起为 pendingMetrics，滚动结束（SETTLING）
  /// 后应用一次；锚点不可解析时回退前缀高度差补偿。
  void _compensateScrollForPrefixDelta(
    double? previousPrefix, {
    VisualAnchor? anchorBefore,
    ContinuousChapterEntry? oldAnchorEntry,
    required double anchorContentY,
  }) {
    if (previousPrefix == null ||
        isRestoringProgress ||
        restore.shouldSuppressWrites ||
        isLoadingChapter ||
        isSwitchingChapter) {
      return;
    }
    final nextPrefix = continuousScrollController.prefixHeightOf(
      currentChapterId,
    );
    final delta = nextPrefix - previousPrefix;
    if (delta.abs() < 0.5 && anchorBefore == null) {
      return;
    }
    if (!scrollController.hasClients) {
      return;
    }
    _preserveVisualAnchorAfterLayoutChange(
      anchorBefore: anchorBefore,
      oldAnchorEntry: oldAnchorEntry,
      fallbackDelta: delta,
      anchorContentY: anchorContentY,
    );
  }

  Map<String, List<ReaderAnnotation>> _continuousAnnotationsByChapter() {
    final loader = contentLoader;
    final handler = annotationHandler;
    if (loader == null || handler == null) {
      return const {};
    }
    final map = <String, List<ReaderAnnotation>>{};
    for (final entry in continuousScrollController.entries) {
      map[entry.chapterId] = handler.annotationsForChapter(entry.chapterId);
    }
    return map;
  }

  Widget buildScrollModeContent(
    ReaderChapterContent content,
    ReaderItemDetail detail,
  ) {
    // Build Purity（方案 §71/§72）：build 只请求几何更新，实际重建在
    // 帧末收敛；先注册重建请求，使同帧后续 restore 读取新窗口。
    runtime.requestGeometryUpdate(
      reason: ReaderGeometryInvalidation.contentLoaded,
    );
    _schedulePendingScrollRestore();

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final viewportSize = Size(
          constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : fallbackSize.width,
          constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : fallbackSize.height,
        );
        if (viewportSize.width.isFinite &&
            viewportSize.height.isFinite &&
            pageViewportSize != viewportSize) {
          _scheduleViewportUpdate(viewportSize);
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            lastPointerDownTime = DateTime.now();
            pointerDownActive = true;
            // 用户真实触摸：消耗模式切换冻结锚点
            if (modeSwitchAnchor != null) modeSwitchAnchor = null;
          },
          onPointerUp: (_) {
            pointerDownActive = false;
          },
          onPointerCancel: (_) {
            pointerDownActive = false;
          },
          onPointerMove: (event) {
            // 按住拖动阅读时持续刷新进度窗口起点；buttons==0 的悬停移动
            // 不刷新，保留"非指针驱动滚动不写进度"的守卫语义
            if (event.buttons != 0) {
              lastPointerDownTime = DateTime.now();
            }
          },
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              lastPointerDownTime = DateTime.now();
              // 滚轮/触控板输入进入事务层（方案 §29-§31）：burst 复用
              // 同一事务，200ms 空闲后一次提交。
              onPointerScrollInput();
            }
          },
          child: ReaderContinuousScrollView(
            key: const Key('reader-continuous-scroll'),
            controller: continuousScrollController,
            settings: settings,
            scrollController: scrollController,
            itemId: itemId,
            annotationsByChapter: _continuousAnnotationsByChapter(),
            onLinkTap: handleReaderLinkTap,
            onSelectionActive: onReaderSelectionActive,
            onTap: toggleControls,
            onScrollPosition: onContinuousScrollPosition,
            onScrollPhaseChanged: onScrollPhaseChanged,
            scrollSessionProvider: () => scrollSession,
            onHighlight: (text, start, end, chapterId) {
              if (!mounted) return;
              annotationHandler?.updateChapter(chapterId);
              annotationHandler?.highlight(text, start, end, context);
            },
            onAnnotate: (text, start, end, chapterId) {
              if (!mounted) return;
              annotationHandler?.updateChapter(chapterId);
              annotationHandler?.annotate(text, start, end, context);
            },
            onExpandWindow: onContinuousWindowExpand,
          ),
        );
      },
    );
  }

  void handleReaderLinkTap(String href) {
    final link = href.trim();
    if (link.isEmpty) {
      return;
    }
    if (_isExternalReaderHref(link)) {
      _showUnsupportedLinkSnackBar();
      return;
    }
    final target = _findLinkedTarget(link);
    if (target != null) {
      if (target.chapterId == currentChapterId) {
        _restoreAnchorInCurrentChapter(target.anchor);
      } else {
        unawaited(
          switchToChapter(
            target.chapterId,
            intent: ReaderChapterNavigationIntent.anchor(
              target.anchor,
              offerReturn: true,
            ),
          ),
        );
      }
      return;
    }
    _showUnsupportedLinkSnackBar();
  }

  void _showUnsupportedLinkSnackBar() {
    final message = AppLocalizations.of(context).readerUnsupportedLink;
    showReaderSnackBar(context, message);
  }

  _ReaderLinkTarget? _findLinkedTarget(String href) {
    final chapters = contentLoader?.allChapters ?? [];
    if (chapters.isEmpty) {
      return null;
    }
    final anchor = _extractReaderAnchor(href);
    final normalizedHref = _normalizeReaderHref(href);
    if (normalizedHref.isEmpty) {
      return _ReaderLinkTarget(currentChapterId, anchor);
    }
    for (final chapter in chapters) {
      final contentPath = chapter.contentPath;
      if (contentPath == null || contentPath.isEmpty) {
        continue;
      }
      final normalizedPath = _normalizeReaderHref(contentPath);
      if (normalizedPath == normalizedHref ||
          normalizedPath.endsWith('/$normalizedHref') ||
          normalizedHref.endsWith('/$normalizedPath')) {
        return _ReaderLinkTarget(chapter.id, anchor);
      }
    }
    return null;
  }

  String _normalizeReaderHref(String href) {
    var value = Uri.decodeComponent(href.trim());
    final hashIndex = value.indexOf('#');
    if (hashIndex >= 0) {
      value = value.substring(0, hashIndex);
    }
    final queryIndex = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }
    value = value.replaceAll('\\', '/');
    while (value.startsWith('./')) {
      value = value.substring(2);
    }
    return value;
  }

  bool _isExternalReaderHref(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) {
      return false;
    }
    return uri.hasScheme && uri.scheme.toLowerCase() != 'file';
  }

  String? _extractReaderAnchor(String href) {
    final hashIndex = href.indexOf('#');
    if (hashIndex < 0 || hashIndex == href.length - 1) {
      return null;
    }
    return Uri.decodeComponent(href.substring(hashIndex + 1));
  }

  void _restoreAnchorInCurrentChapter(String? anchor) {
    final charOffset = resolveAnchorCharOffset(currentChapterId, anchor);
    if (charOffset == null) {
      return;
    }
    isRestoringProgress = true;
    pendingRestoreCharOffset = charOffset;
    if (mounted) {
      setState(() {});
    }
  }

  int? resolveAnchorCharOffset(String chapterId, String? anchor) {
    if (anchor == null || anchor.isEmpty) {
      return 0;
    }
    final data = contentLoader?.getByChapterId(chapterId);
    final htmlContent = data?.content.content;
    if (htmlContent == null || htmlContent.isEmpty) {
      return null;
    }
    final anchorOffset = _findAnchorHtmlOffset(htmlContent, anchor);
    if (anchorOffset == null) {
      return null;
    }
    final prefix = htmlContent.substring(0, anchorOffset);
    final plainPrefix = stripHtml(prefix);
    return plainPrefix.length.clamp(0, data!.totalChars).toInt();
  }

  int? _findAnchorHtmlOffset(String html, String anchor) {
    final escaped = RegExp.escape(anchor);
    final pattern = RegExp(
      '\\s(?:id|name)\\s*=\\s*["\\\']$escaped["\\\']',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(html);
    return match?.start;
  }

  void _handlePendingCharOffsetRestore() {
    final restoreCharOffset = pendingRestoreCharOffset;
    pendingRestoreCharOffset = null;
    if (restoreCharOffset == null) {
      isRestoringProgress = false;
      modeSwitchInProgress = false;
      return;
    }
    final chapterData = contentLoader?.get(currentChapterId, settings);
    if (chapterData == null || chapterData.totalChars <= 0) {
      // 数据未就绪，重新排队等待下次 build 重试
      pendingRestoreCharOffset = restoreCharOffset;
      return;
    }

    if (restoreCharOffset <= 0) {
      modeSwitchInProgress = false;
      if (isPageMode) {
        scrollProgress = 0;
        positionTracker.setCharOffset(0, currentChapterId);
        isRestoringProgress = false;
      } else {
        restoreToChapterStart(currentChapterId);
      }
      return;
    }

    final progress = (restoreCharOffset / chapterData.totalChars).clamp(
      0.0,
      1.0,
    );
    scrollProgress = progress;
    final capturedCharOffset = restoreCharOffset;
    final capturedPageWidth = computePageWidth();
    final capturedSettings = settings;
    final capturedTextScale = MediaQuery.textScalerOf(context).scale(1.0);
    final capturedAnchorY = viewportAnchorY;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final restoreScheduledAt = DateTime.now();
      final restoreTx = beginRuntimeRestore(
        ReaderPositionTarget(
          chapterId: currentChapterId,
          charOffset: capturedCharOffset,
        ),
      );
      restore.start(
        scrollController: scrollController,
        targetOffsetBuilder: () {
          if (!scrollController.hasClients) return 0;
          final max = scrollController.position.maxScrollExtent;
          if (max <= 0) return 0;
          final intraY = contentLoader?.charOffsetToPixelOffset(
            currentChapterId,
            capturedCharOffset,
            pageWidth: capturedPageWidth,
            settings: capturedSettings,
            textScale: capturedTextScale,
          );
          final prefix = continuousScrollController.prefixHeightOf(
            currentChapterId,
          );
          // 章体在窗口中的起点 = 前缀 + 章头 chrome；charOffset 原点是章体顶。
          final windowY =
              prefix +
              ReaderContinuousScrollController.chapterHeaderExtent +
              (intraY ?? 0.0);
          return (windowY - capturedAnchorY).clamp(0.0, max);
        },
        isUserScrolling: () => isUserScrollActive(since: restoreScheduledAt),
        onSettled: (completed) {
          if (completed) {
            // 三层身份校验（方案 §57）：item/mode 已变的恢复不得回写 tracker。
            if (runtime.restore.isCallbackValid(
              restoreTx,
              itemId: itemId,
              readingMode: settings.readingMode,
            )) {
              positionTracker.setCharOffset(
                capturedCharOffset,
                currentChapterId,
              );
            } else {
              runtime.diagnostics.restoreCallbackDropCount++;
            }
          } else {
            // 被用户滚动中断或超时：当前真实位置即事实，恢复静默窗口
            // 让进度写入立即恢复，追踪由下一次滚动回调修正
            restoreSilenceUntil = DateTime.fromMillisecondsSinceEpoch(0);
          }
          isRestoringProgress = false;
          if (mounted) setState(() {});
        },
      );
    });
  }

  void _schedulePendingScrollRestore() {
    if (pendingRestoreCharOffset == null && pendingChapterProgress == null) {
      return;
    }
    if (_scrollRestoreScheduled) {
      return;
    }
    _scrollRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollRestoreScheduled = false;
      if (!mounted) {
        return;
      }
      if (pendingRestoreCharOffset != null) {
        _handlePendingCharOffsetRestore();
      } else if (pendingChapterProgress != null) {
        _handlePendingProgressRestore();
      }
    });
  }

  void _schedulePendingPageCharOffsetRestore(ChapterData chapterData) {
    if (_pageRestoreScheduled) {
      return;
    }
    _pageRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageRestoreScheduled = false;
      if (!mounted) {
        return;
      }
      final restoreCharOffset = pendingRestoreCharOffset;
      pendingRestoreCharOffset = null;
      if (restoreCharOffset == null) {
        isRestoringProgress = false;
        modeSwitchInProgress = false;
        return;
      }
      unawaited(_restorePageCharOffset(chapterData, restoreCharOffset));
    });
  }

  Future<void> _restorePageCharOffset(
    ChapterData chapterData,
    int restoreCharOffset,
  ) async {
    final requestedChapterId = currentChapterId;
    // 模式切换/恢复事务代次：完成或失败都必须统一退出（方案 §27-28）。
    final txnGeneration = modeSwitchGeneration;
    // 捕获当前导航令牌：await 定位期间若发生新的显式导航（含同章重复
    // 跳转），本次恢复结果已过时，必须整体丢弃（旧任务 ≠ 当前任务）。
    final navigationTokenAtStart = navigationTokens.current;
    try {
      final targetPage = await findPageByCharOffset(
        chapterData,
        restoreCharOffset,
      );
      if (!mounted) {
        return;
      }
      if (targetPage == null ||
          requestedChapterId != currentChapterId ||
          !navigationTokens.isUnchangedSince(navigationTokenAtStart)) {
        // 定位被取消或章节已切换：当前章节请求结束时必须退出恢复态，避免遮罩滞留
        if (requestedChapterId == currentChapterId) {
          setState(() {
            isRestoringProgress = false;
            modeSwitchInProgress = false;
          });
          completeModeSwitchGeneration(txnGeneration);
        }
        return;
      }
      final totalChars = chapterData.totalChars;
      final capturedProgress =
          totalChars <= 0
              ? 0.0
              : (restoreCharOffset / totalChars).clamp(0.0, 1.0).toDouble();
      scrollProgress = capturedProgress;
      positionTracker.setCharOffset(restoreCharOffset, currentChapterId);
      // targetPage 为章内页；换算到跨章流全局索引。
      final anchorStart = _pageFlow?.startIndexOf(currentChapterId) ?? 0;
      setState(() {
        pageModePage = anchorStart + targetPage;
        modeSwitchInProgress = false;
        isRestoringProgress = false;
      });
      completeModeSwitchGeneration(txnGeneration);
    } catch (e) {
      if (mounted && requestedChapterId == currentChapterId) {
        setState(() {
          isRestoringProgress = false;
          modeSwitchInProgress = false;
        });
        // 定位异常同样是统一失败退出（方案 §28）。
        abortModeSwitchGeneration(txnGeneration);
      }
    }
  }

  void _handlePendingProgressRestore() {
    final progressRatio = pendingChapterProgress!.clamp(0.0, 1.0);
    pendingChapterProgress = null;
    scrollProgress = progressRatio;
    final capturedRatio = progressRatio;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final restoreScheduledAt = DateTime.now();
      final restoreTx = beginRuntimeRestore(
        ReaderPositionTarget(
          chapterId: currentChapterId,
          charOffset:
              (capturedRatio *
                      (contentLoader
                              ?.getByChapterId(currentChapterId)
                              ?.totalChars ??
                          0))
                  .round(),
        ),
      );
      restore.start(
        scrollController: scrollController,
        targetOffsetBuilder: () {
          if (!scrollController.hasClients) return 0;
          final max = scrollController.position.maxScrollExtent;
          final data = contentLoader?.get(currentChapterId, settings);
          final chapterHeight =
              (data != null && data.cumulativeHeights.isNotEmpty)
                  ? data.cumulativeHeights.last
                  : 0.0;
          if (chapterHeight <= 0) {
            return capturedRatio * max;
          }
          // 章内比例映射到窗口坐标：前缀 + 章头 + ratio×章体高 − 视口锚点。
          final target =
              continuousScrollController.prefixHeightOf(currentChapterId) +
              ReaderContinuousScrollController.chapterHeaderExtent +
              capturedRatio * chapterHeight -
              viewportAnchorY;
          return target.clamp(0.0, max);
        },
        isUserScrolling: () => isUserScrollActive(since: restoreScheduledAt),
        onSettled: (completed) {
          if (completed && scrollController.hasClients) {
            final max = scrollController.position.maxScrollExtent;
            final data = contentLoader?.get(currentChapterId, settings);
            if (data != null &&
                max > 0 &&
                runtime.restore.isCallbackValid(
                  restoreTx,
                  itemId: itemId,
                  readingMode: settings.readingMode,
                )) {
              final settledCharOffset = windowContentYToCharOffset(
                currentChapterId,
                scrollController.offset + viewportAnchorY,
              );
              positionTracker.updateFromScroll(
                offset: scrollController.offset,
                maxExtent: max,
                totalChars: data.totalChars,
                chapterId: currentChapterId,
                charOffset: settledCharOffset,
              );
            } else if (max <= 0 || data == null) {
              runtime.diagnostics.restoreCallbackDropCount++;
            }
          } else if (!completed) {
            restoreSilenceUntil = DateTime.fromMillisecondsSinceEpoch(0);
          }
          isRestoringProgress = false;
          if (mounted) setState(() {});
        },
      );
    });
  }

  // ── 返回原进度浮层 ──

  Widget buildReturnToProgressControl() {
    final l10n = AppLocalizations.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomOffset =
        showControls ? 216.0 + bottomPadding : 16.0 + bottomPadding;
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: showReturnControl ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: ReaderReturnToProgressControl(
          settings: settings,
          label:
              returnControlIsRemoteOffer
                  ? l10n.readerSyncRemoteProgress
                  : l10n.readerReturnToProgress,
          onPressed: returnToOriginalProgress,
        ),
      ),
    );
  }
}

class _ReaderLinkTarget {
  const _ReaderLinkTarget(this.chapterId, this.anchor);

  final String chapterId;
  final String? anchor;
}

/// 页面切换回调实现。
class PageTurnCallbacksImpl implements PageTurnCallbacks {
  PageTurnCallbacksImpl({
    required void Function(int) onPageChangedFn,
    required VoidCallback onPreviousChapterFn,
    required VoidCallback onNextChapterFn,
    required VoidCallback onToggleControlsFn,
  }) : _onPageChangedFn = onPageChangedFn,
       _onPreviousChapterFn = onPreviousChapterFn,
       _onNextChapterFn = onNextChapterFn,
       _onToggleControlsFn = onToggleControlsFn;

  final void Function(int) _onPageChangedFn;
  final VoidCallback _onPreviousChapterFn;
  final VoidCallback _onNextChapterFn;
  final VoidCallback _onToggleControlsFn;

  @override
  void onPageChanged(int pageIndex) => _onPageChangedFn(pageIndex);

  @override
  void onPreviousChapter() => _onPreviousChapterFn();

  @override
  void onNextChapter() => _onNextChapterFn();

  @override
  void onToggleControls() => _onToggleControlsFn();
}
