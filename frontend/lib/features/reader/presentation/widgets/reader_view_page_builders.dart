import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
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

  // ── State 字段访问器（由 State 实现） ──
  ReaderContentLoader? get contentLoader;
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
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: settings.immersiveMode,
      isPageMode: isPageMode,
    );
    return (size.height - topInset - chromeLayout.viewportVerticalReserve) *
        0.25;
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
    final chapterTitle =
        content.title.isNotEmpty
            ? content.title
            : (currentChapter?.title ?? '');

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
            // 用户真实触摸：消耗模式切换冻结锚点
            if (modeSwitchAnchor != null) modeSwitchAnchor = null;
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

  Widget buildScrollModeContent(
    ReaderChapterContent content,
    ReaderItemDetail detail,
  ) {
    _schedulePendingScrollRestore();

    final chapterData = contentLoader?.get(currentChapterId, settings);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        lastPointerDownTime = DateTime.now();
        // 用户真实触摸：消耗模式切换冻结锚点
        if (modeSwitchAnchor != null) modeSwitchAnchor = null;
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
      child: ReaderViewContent(
        htmlContent: content.content,
        settings: settings,
        itemId: itemId,
        annotations: annotationHandler?.chapterAnnotations ?? [],
        rawBlocks: chapterData?.blocks,
        scrollController: scrollController,
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
        onTap: toggleControls,
      ),
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
      scrollProgress = 0;
      positionTracker.setCharOffset(0, currentChapterId);
      isRestoringProgress = false;
      modeSwitchInProgress = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });
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
          final contentY = contentLoader?.charOffsetToPixelOffset(
            currentChapterId,
            capturedCharOffset,
            pageWidth: capturedPageWidth,
            settings: capturedSettings,
            textScale: capturedTextScale,
          );
          if (contentY == null || contentY <= 0) return 0;
          return (contentY - capturedAnchorY).clamp(0.0, max);
        },
        isUserScrolling: () => lastPointerDownTime.isAfter(restoreScheduledAt),
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
    final capturedPageWidth = computePageWidth();
    final capturedTextScale = MediaQuery.textScalerOf(context).scale(1.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final restoreScheduledAt = DateTime.now();
      restore.start(
        scrollController: scrollController,
        targetOffsetBuilder: () {
          if (!scrollController.hasClients) return 0;
          final max = scrollController.position.maxScrollExtent;
          return capturedRatio * max;
        },
        isUserScrolling: () => lastPointerDownTime.isAfter(restoreScheduledAt),
        onSettled: (completed) {
          if (completed && scrollController.hasClients) {
            final max = scrollController.position.maxScrollExtent;
            final data = contentLoader?.get(currentChapterId, settings);
            if (data != null && max > 0) {
              final settledContentY = scrollController.offset + viewportAnchorY;
              final settledCharOffset =
                  contentLoader?.contentYToCharOffset(
                    currentChapterId,
                    settledContentY,
                    pageWidth: capturedPageWidth,
                    settings: settings,
                    textScale: capturedTextScale,
                  ) ??
                  0;
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
