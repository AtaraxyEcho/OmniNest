part of 'reader_view_page_builders.dart';

/// 翻页/滚动模式的页面内容构建方法。
extension ReaderViewPageBuildersContent on ReaderViewPageBuilders {
  // ── 翻页模式 ──

  Widget buildPageModeContent(
    ReaderChapterContent content,
    ReaderItemDetail detail,
  ) {
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
        final contentPages = navigator?.readablePageCount ?? 0;
        final hasMore = !(navigator?.isFullyPaginated ?? false);
        // 章末收页挂在正文之后。稿子的 `.chapter-end` 在滚动模式里跟着最后一句走，
        // 而翻页模式一屏就是一页：末页剩余空间实测有约两成不足一张卡片（168px），
        // 钉在页底就会挤掉正文最后几行——翻页内容层不可滚，被挤掉的是看不见的字。
        final pageCount = readerDisplayPageCount(
          contentPages: contentPages,
          fullyPaginated: !hasMore,
        );
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
              if (index >= contentPages) {
                // 收页在正文切片之外：越界的一律不渲染，正好等于正文页数的是收页。
                return isReaderChapterEndPage(
                      pageIndex: index,
                      contentPages: contentPages,
                      fullyPaginated: !hasMore,
                    )
                    ? _buildChapterEndPage(detail, pageLayout, chromeLayout)
                    : null;
              }
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

  /// 按切片取可见块：规则收在 `BlockClipper.clipBlocksByPageRange`，
  /// 渲染侧与语料 walker 共用同一条，不再各写一份零宽块的归属判断。
  List<ContentBlock> _sliceVisibleBlocks(ChapterData data, PageSlice slice) =>
      BlockClipper.clipBlocksByPageRange(data.blocks, slice);

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
      stylesheetCss: data.content.stylesheetCss,
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
    // 尺寸与颜色取自稿子 `.chapter-kicker`，且不再跟着屏宽浮动：微型标签的层级
    // 靠字重与字距维持，放大只会把它推成正文一档。
    return Text(
      chapterTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: settings.chapterKickerStyle(),
    );
  }

  // ── 滚动模式 ──

  /// 稿子的章末两块：发丝线行写真实的章节位次与全书进度（原型那行
  /// "还剩约 7 分钟"是假数据），末章只留分隔行，不摆点了没反应的卡。
  Widget _buildChapterEndCard(ReaderItemDetail detail) {
    final l10n = AppLocalizations.of(context);
    final chapters = _chapterList(detail);
    final index = chapters.indexWhere(
      (chapter) => chapter.id == currentChapterId,
    );
    final next = _nextChapterOf(detail);
    final percent = ((lastKnownBookProgress ?? 0) * 100).round();
    return ReaderChapterEndCard(
      settings: settings,
      chapterLabel:
          index >= 0
              ? l10n.readerBookChapterPosition(
                index + 1,
                chapters.length,
                percent,
              )
              : '',
      nextChapterTitle: next?.title,
      onNextChapter: next == null ? null : () => tryNavigateChapter(1),
    );
  }

  /// 章末收页：整页只有稿子那两块，贴在页底。
  ///
  /// 收页不进正文块列表，因此不参与字符域：它没有自己的字符区间，位置记账归到本章
  /// 末尾（见 `computePageCharOffset`），进度与恢复都不会把读者退回章首。
  Widget _buildChapterEndPage(
    ReaderItemDetail detail,
    ReaderControlLayout pageLayout,
    ReaderChromeLayout chromeLayout,
  ) {
    return Container(
      color: settings.surfaceColor,
      width: double.infinity,
      // 左右与正文列同一份内缩，否则卡片与上一句的首字对不齐。
      padding: chromeLayout.contentPadding.copyWith(
        left: pageLayout.horizontalPadding,
        right: pageLayout.horizontalPadding,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_buildChapterEndCard(detail)],
      ),
    );
  }

  ReaderChapter? _nextChapterOf(ReaderItemDetail detail) {
    final chapters = _chapterList(detail);
    final index = chapters.indexWhere(
      (chapter) => chapter.id == currentChapterId,
    );
    if (index < 0 || index + 1 >= chapters.length) {
      return null;
    }
    return chapters[index + 1];
  }

  List<ReaderChapter> _chapterList(ReaderItemDetail detail) {
    final loaded = contentLoader?.allChapters;
    if (loaded != null && loaded.isNotEmpty) {
      return loaded;
    }
    return detail.chapters;
  }

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
          stylesheetCss: content.stylesheetCss,
          settings: settings,
          itemId: itemId,
          annotations: annotationHandler?.chapterAnnotations ?? [],
          rawBlocks: chapterData?.blocks,
          blockExtents: chapterData?.blockExtents,
          scrollController: scrollController,
          footer: _buildChapterEndCard(detail),
          // 章末两块的高度随文字缩放同步放大：卡内文本吃缩放，高度不跟就会在紧约束下
          // 溢出。取卡片实际所在内容层的缩放（已剔除应用字体档位），页面环境值在档位
          // 低于标准时比渲染矮整整一行。
          footerExtent: ReaderChapterEndCard.heightFor(
            hasNextChapter: _nextChapterOf(detail) != null,
            scaler: FontScaleScope.systemScalerOf(context),
          ),
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
