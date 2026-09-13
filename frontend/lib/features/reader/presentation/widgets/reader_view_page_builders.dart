import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
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
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
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
  set lastPointerDownTime(DateTime value);
  Size? get pageViewportSize;
  set pageViewportSize(Size? value);
  bool get showReturnControl;
  bool get showControls;
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
  int windowContentYToCharOffset(String chapterId, double windowContentY);
  double chapterStartScrollOffset(String chapterId);
  void restoreToChapterStart(String chapterId);
  bool get pointerDownActive;
  set pointerDownActive(bool value);
  bool isUserScrollActive({required DateTime since});

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
    final slice = contentLoader?.computePage(
      chapterId: currentChapterId,
      settings: settings,
      pageWidth: computePageWidth(),
      pageHeight: computePageHeight(),
      pageIndex: pageIndex,
      textScale: MediaQuery.textScalerOf(context).scale(1.0),
    );
    return slice?.startCharOffset ?? 0;
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
        final data = contentLoader?.get(currentChapterId, settings);
        final navigator = data?.getOrCreatePageNavigator(
          pageWidth,
          pageHeight,
          settings,
          textScale: textScale,
        );
        final pageCount = navigator?.readablePageCount ?? 0;
        final hasMore = !(navigator?.isFullyPaginated ?? false);
        if (navigator != null && data != null) {
          _schedulePageNavigatorWarmup(navigator, pageModePage, data.chapterId);
        }

        if (pendingRestoreCharOffset != null && data != null) {
          _schedulePendingPageCharOffsetRestore(data);
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
          child: ReaderPageView(
            key: ValueKey(
              'reader-page-$currentChapterId-'
              '${settings.pageTurnMode}',
            ),
            controller: pageTurnController,
            state: PagedState(
              chapterId: currentChapterId,
              pageIndex: pageModePage,
              pageCount: pageCount,
              hasMore: hasMore,
              hasPreviousChapter: chapterIdx > 0,
              hasNextChapter: chapterIdx < chapters.length - 1,
              isPaginating:
                  isSwitchingChapter ||
                  isLoadingChapter ||
                  chapterLoadCoordinator.isLoading ||
                  pageLocator.isLocating ||
                  isRestoringProgress,
            ),
            selectionActive: selectionActive,
            pageBuilder: (index) {
              final slice = contentLoader?.computePage(
                chapterId: currentChapterId,
                settings: settings,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                pageIndex: index,
                textScale: textScale,
              );
              if (slice == null) return null;
              final pageData = contentLoader?.get(currentChapterId, settings);
              if (pageData == null) return null;
              return buildPageContent(
                pageData,
                slice,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                chapterTitle: chapterTitle,
              );
            },
            callbacks: PageTurnCallbacksImpl(
              onPageChangedFn: (index) {
                dismissReturnSnackBar();
                if (pageModePage != index) {
                  pageModePage = index;
                  _requestReaderRebuild();
                }
                if (modeSwitchInProgress) {
                  modeSwitchInProgress = false;
                  return;
                }
                if (isRestoringProgress || isSwitchingChapter) return;
                if (DateTime.now().isBefore(restoreSilenceUntil)) return;
                // 模式切换期间（modeSwitchAnchor 未被用户交互消耗）：
                // 只更新展示进度，不写 tracker 和 SQLite。
                if (modeSwitchAnchor != null) {
                  final data = contentLoader?.get(currentChapterId, settings);
                  if (data != null && data.totalChars > 0) {
                    final charOffset = computePageCharOffset(index);
                    scrollProgress = (charOffset / data.totalChars).clamp(
                      0.0,
                      1.0,
                    );
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
                prefetchNextChapterAtBoundary(index);
              },
              onPreviousChapterFn: () => tryNavigateChapter(-1),
              onNextChapterFn: () => tryNavigateChapter(1),
              onToggleControlsFn: toggleControls,
            ),
            surfaceColor: settings.surfaceColor,
            turnMode: parsePageTurnMode(settings.pageTurnMode),
          ),
        );
      },
    );
  }

  // ── 单页内容 ──

  Widget buildPageContent(
    ChapterData data,
    PageSlice slice, {
    ScrollPhysics? scrollPhysics,
    String? chapterTitle,
  }) {
    final blocks = BlockClipper.clipBlocksByCharRange(
      data.blocks,
      slice.startCharOffset,
      slice.endCharOffset,
    );

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

  /// 用 contentLoader 数据重建连续滚动窗口。
  ///
  /// build 热路径调用：fingerprint 未变化时整段跳过（含测高启动与 notify）。
  /// dropHtmlForNeighbors 由 setActive/loadChapter 负责，不在此处理。
  void rebuildContinuousWindow() {
    if (_continuousWindowRebuilding) {
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
      );
      // 滑窗已按首尾高度补偿，勿再按锚点 prefix 二次修正。
      if (!windowSlid) {
        _compensateScrollForPrefixDelta(previousPrefix);
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
      ...loader.neighborChapterIds(currentChapterId),
    ];
    for (final id in ids) {
      final data = loader.getByChapterId(id);
      final heights = data?.cumulativeHeights;
      hash = Object.hash(
        hash,
        id,
        data?.blocks.length ?? 0,
        data?.totalChars ?? 0,
        data?.layoutVersion ?? -1,
        heights == null || heights.isEmpty ? -1.0 : heights.last,
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

  /// 滑窗时保持视口：前缀章卸载则 offset 减高，前缀章新增则加高。
  void _compensateScrollForWindowSlide({
    required List<ContinuousChapterEntry> prevEntries,
    required String? prevFirstId,
    required String? prevLastId,
    required double prevFirstHeight,
    required double prevLastHeight,
  }) {
    if (prevEntries.isEmpty || !scrollController.hasClients) {
      return;
    }
    // 与 _compensateScrollForPrefixDelta 同套状态守卫：恢复/加载/切章期间
    // 滚动偏移由对应流程掌控，此处补偿会产生叠加跳变。
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
    if (delta.abs() < 0.5) {
      return;
    }
    final captured = delta;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      final max = scrollController.position.maxScrollExtent;
      final target = (scrollController.offset + captured).clamp(0.0, max);
      scrollController.jumpTo(target);
    });
  }

  /// 前缀章高度变化时补偿滚动偏移，避免测高收敛导致视口跳动。
  void _compensateScrollForPrefixDelta(double? previousPrefix) {
    if (previousPrefix == null ||
        isRestoringProgress ||
        restore.shouldSuppressWrites ||
        isLoadingChapter ||
        isSwitchingChapter) {
      return;
    }
    // 用户正在拖动/点击时不做像素补偿，避免封面图加载导致的回跳。
    final timeSincePointerDown =
        DateTime.now().difference(lastPointerDownTime).inMilliseconds;
    if (timeSincePointerDown < 800) {
      return;
    }
    final nextPrefix = continuousScrollController.prefixHeightOf(
      currentChapterId,
    );
    final delta = nextPrefix - previousPrefix;
    if (delta.abs() < 0.5 || !scrollController.hasClients) {
      return;
    }
    final captured = delta;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      final max = scrollController.position.maxScrollExtent;
      final target = (scrollController.offset + captured).clamp(0.0, max);
      scrollController.jumpTo(target);
    });
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
    _schedulePendingScrollRestore();
    rebuildContinuousWindow();

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
            positionTracker.setCharOffset(capturedCharOffset, currentChapterId);
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
    try {
      final targetPage = await findPageByCharOffset(
        chapterData,
        restoreCharOffset,
      );
      if (!mounted) {
        return;
      }
      if (targetPage == null || requestedChapterId != currentChapterId) {
        // 定位被取消或章节已切换：当前章节请求结束时必须退出恢复态，避免遮罩滞留
        if (requestedChapterId == currentChapterId) {
          setState(() {
            isRestoringProgress = false;
            modeSwitchInProgress = false;
          });
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
      setState(() {
        pageModePage = targetPage;
        modeSwitchInProgress = false;
        isRestoringProgress = false;
      });
    } catch (e) {
      if (mounted && requestedChapterId == currentChapterId) {
        setState(() {
          isRestoringProgress = false;
          modeSwitchInProgress = false;
        });
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
            if (data != null && max > 0) {
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
          label: l10n.readerReturnToProgress,
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
