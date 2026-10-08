part of 'reader_view_page_builders.dart';

/// 翻页/滚动模式的页面内容构建方法。
extension ReaderViewPageBuildersContent on ReaderViewPageBuilders {
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
          // 翻页模式下不按触摸消耗冻结锚点：单击只是开关工具栏，锚点一旦被
          // 清掉，buildProgressSnapshot 就退到页首偏移，记账位置凭空回退半页。
          // 锚点改由真实翻页（onPageChanged 换页）或切章释放。
          onPointerDown: (_) => lastPointerDownTime = DateTime.now(),
          child: ReaderPageView(
            key: ValueKey(
              'reader-page-$currentChapterId-'
              '${settings.pageTurnMode}',
            ),
            controller: pageTurnController,
            pageCountNotifier: pageCountNotifier,
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
              // 封面章首页：整页封面渲染（严格结构判定，非图块即否决）。
              if (index == 0 && isDedicatedCoverPage(blocks: pageData.blocks)) {
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
                // 物理页回调先过闸门再回写：恢复/模式切换动画的中间页
                // 一旦写入 pageModePage 并触发重建，_syncPageView 会把
                // PageView 拉回中间页，恢复目标永远无法到达。
                if (modeSwitchInProgress) {
                  modeSwitchInProgress = false;
                  return;
                }
                if (isRestoringProgress || isSwitchingChapter) return;
                if (DateTime.now().isBefore(restoreSilenceUntil)) return;
                final landingEcho = isModeSwitchLandingEcho(
                  anchorActive: modeSwitchAnchor != null,
                  changedPageIndex: index,
                  landedPageIndex: pageModePage,
                );
                if (pageModePage != index) {
                  pageModePage = index;
                  _requestReaderRebuild();
                }
                if (landingEcho) {
                  // 切换落地的那一页：位置以精确锚点显示，不写 tracker 与
                  // SQLite，否则刚切完模式就把位置退回页首。
                  final data = contentLoader?.get(currentChapterId, settings);
                  final anchor = modeSwitchAnchor;
                  if (data != null && anchor != null && data.totalChars > 0) {
                    scrollProgress = (anchor / data.totalChars).clamp(0.0, 1.0);
                  }
                  return;
                }
                if (modeSwitchAnchor != null) {
                  // 真实翻页：锚点使命结束，之后按页首记账。
                  modeSwitchAnchor = null;
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

  /// 按切片取可见块：字符区间非空走字符裁剪；零字符切片（图片
  /// 独占页）走块索引裁剪，避免零宽块被字符裁剪丢弃。
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

  Widget buildScrollModeContent(
    ReaderChapterContent content,
    ReaderItemDetail detail,
  ) {
    _schedulePendingScrollRestore();

    final chapterData = contentLoader?.get(currentChapterId, settings);
    // 滚动模式没有视口变化的触发点，这里顺带核对高度表是否仍属于当前排版；
    // 方法内部只在过期时安排一次帧末重算，尺寸未变时直接返回。
    ensureScrollMetricsFresh();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        lastPointerDownTime = DateTime.now();
        // 滚动模式的锚点兜底是像素实时读数，释放后仍然准确，触摸即可消耗；
        // 翻页模式不能照搬，见上方 LandingEcho 分支。
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // 章首向上越界 = 用户在本章顶部继续上滚，回退到上一章末尾。
          if (notification is OverscrollNotification &&
              notification.overscroll < 0 &&
              notification.depth == 0) {
            // layout/overscroll 回调中禁止同步切章，延迟到帧末。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              handleBackwardChapterOverscroll();
            });
          }
          return false;
        },
        child: ReaderViewContent(
          htmlContent: content.content,
          settings: settings,
          itemId: itemId,
          annotations: annotationHandler?.chapterAnnotations ?? [],
          rawBlocks: chapterData?.blocks,
          blockExtents: chapterData?.blockExtents,
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
      ),
    );
  }
}
