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
        // 单一几何事实源：测量、分页、恢复与渲染全部从此处取值，根除缓存乒乓。
        final metrics = resolveViewportMetrics(
          viewportOverride: viewportSize,
          textScaleOverride: textScale,
          safePaddingOverride: MediaQuery.viewPaddingOf(context),
        );
        final spread = metrics.isSpread;
        final frame = metrics.frameSize;
        final halfWidth = metrics.halfWidth;
        final pageInsets = metrics.pageInsets;
        final pageWidth = metrics.pageWidth;
        final pageHeight = metrics.pageHeight;
        final folioBottom = metrics.folioBottom;
        final alignedPageIndex = metrics.alignPageIndex(pageModePage);
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

        final pageView = ReaderPageView(
          key: ValueKey(
            'reader-page-$currentChapterId-'
            '${settings.pageTurnMode}-${spread ? 'spread' : 'single'}',
          ),
          spread: spread,
          paperEdgeColor: settings.paperEdgeColor,
          bookmarked: isBookmarked,
          // 仅对真正影响书页排版的字段求 hash，拖动外层亮度/暖色滑块不再误触发 Book 快照重抓。
          contentRevision: Object.hash(
            settings.themeIndex,
            settings.fontSize,
            settings.lineHeight,
            settings.fontFamily,
            settings.justify,
            settings.marginPreset,
            settings.followBookTypesetting,
            annotationHandler?.chapterAnnotations.length ?? 0,
            activeSearchQuery,
          ),
          crossChapterSnapshotBuilder: (delta) {
            final targetChapterIdx = chapterIdx + delta;
            if (targetChapterIdx < 0 || targetChapterIdx >= chapters.length) {
              return null;
            }
            return ColoredBox(
              color: settings.surfaceColor,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    chapters[targetChapterIdx].title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: settings.onSurfaceVariantColor,
                      fontSize: AppTypography.titleMedium,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          },
          controller: pageTurnController,
          pageCountNotifier: pageCountNotifier,
          state: PagedState(
            chapterId: currentChapterId,
            pageIndex: alignedPageIndex,
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
          onClearSelection: clearReaderSelection,
          snapshotPageBuilder: (index) {
            if (index < 0) return null;
            final slice = contentLoader?.computePage(
              chapterId: currentChapterId,
              settings: settings,
              pageWidth: pageWidth,
              pageHeight: pageHeight,
              pageIndex: index,
              textScale: textScale,
            );
            if (slice == null) {
              final confirmed = navigator?.confirmedTotalPages ?? contentPages;
              return index == confirmed
                  ? _buildChapterEndPage(detail, pageLayout, chromeLayout)
                  : null;
            }
            final pageData = contentLoader?.get(currentChapterId, settings);
            if (pageData == null) return null;
            // 补齐封面章首页快照分支，杜绝封面页点击翻页瞬间变成普通正文模板。
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
            return _PageWithFolio(
              number: index + 1,
              folioBottom: folioBottom,
              bookmarked: false,
              ribbonRight: (spread ? halfWidth : frame.width) * 0.08,
              child: buildPageContent(
                pageData,
                slice,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                pageInsets: pageInsets,
                pageContentWidth: pageWidth,
                selectionDisabled: true,
              ),
            );
          },
          pageBuilder: (index) {
            if (index < 0) return null;
            // A2 修复：不再用 index >= contentPages 硬截断，直接按需推进 getSlice，
            // 杜绝后台全章分页期间快速翻页出现白页。
            final slice = contentLoader?.computePage(
              chapterId: currentChapterId,
              settings: settings,
              pageWidth: pageWidth,
              pageHeight: pageHeight,
              pageIndex: index,
              textScale: textScale,
            );
            if (slice == null) {
              final totalContentPages =
                  navigator?.confirmedTotalPages ??
                  navigator?.readablePageCount ??
                  contentPages;
              return isReaderChapterEndPage(
                    pageIndex: index,
                    contentPages: totalContentPages,
                    fullyPaginated: navigator?.isFullyPaginated ?? !hasMore,
                  )
                  ? _buildChapterEndPage(detail, pageLayout, chromeLayout)
                  : null;
            }
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
            return _PageWithFolio(
              number: index + 1,
              folioBottom: folioBottom,
              // 样例缎带只挂在「当前这一页」；相邻预构建页不能一起挂。
              bookmarked: !spread && isBookmarked && index == alignedPageIndex,
              ribbonRight: (spread ? halfWidth : frame.width) * 0.08,
              child: buildPageContent(
                pageData,
                slice,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                // 原型 PageFace 只在章节第一页显示章头；把章节标题传给每个
                // 切片会让 Swipe/Book 每翻一页重复一遍章头，并额外吃掉页高。
                chapterTitle: index == 0 ? chapterTitle : null,
                pageInsets: pageInsets,
                pageContentWidth: pageWidth,
              ),
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
              final normalizedIndex = metrics.alignPageIndex(index);
              if (pageModePage != normalizedIndex) {
                pageModePage = normalizedIndex;
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
        );
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => lastPointerDownTime = DateTime.now(),
          child:
              spread
                  ? Center(child: _SpreadFrame(size: frame, child: pageView))
                  : pageView,
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
    EdgeInsets? pageInsets,
    double? pageContentWidth,
    bool selectionDisabled = false,
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
      chapterId: data.chapterId,
      annotations: annotationHandler?.chapterAnnotations ?? [],
      searchQuery: activeSearchQuery,
      visibleBlocks: blocks,
      rawBlocks: data.blocks,
      scrollPhysics: scrollPhysics,
      isFirstBlockContinuation: isFirstBlockContinuation,
      pageInsets: pageInsets,
      pageContentWidth: pageContentWidth,
      selectionDisabled: selectionDisabled,
      onHighlight: (text, start, end) {
        if (!mounted) return;
        annotationHandler?.highlight(text, start, end, context);
      },
      onHighlightColor: (text, start, end, color) {
        if (!mounted) return;
        annotationHandler?.highlight(text, start, end, context, color: color);
      },
      onUpdateAnnotationColor: (annotation, color) {
        if (!mounted) return;
        annotationHandler?.updateColor(annotation, color, context);
      },
      onAnnotate: (text, start, end) {
        if (!mounted) return;
        annotationHandler?.annotate(text, start, end, context);
      },
      onAnnotateInline: (text, start, end, note) {
        if (!mounted) return;
        annotationHandler?.annotateInline(
          selectedText: text,
          startOffset: start,
          endOffset: end,
          note: note,
          context: context,
        );
      },
      onRemoveHighlight: (a) {
        if (!mounted) return;
        annotationHandler?.delete(a, context);
      },
      onRemoveAnnotation: (a) {
        if (!mounted) return;
        annotationHandler?.delete(a, context);
      },
      onLinkTap: handleReaderLinkTap,
      onSelectionActive: onReaderSelectionActive,
      onRegisterSelectionKeyActions: registerReaderSelectionKeyActions,
      // 翻页模式的点击热区由 ReaderPageView 顶层交互层统一分发，
      // 内容层再响应会与顶层各触发一次 toggleControls，两次取反导致
      // 点击中间无法弹出控制栏。
      onTap: null,
    );

    // 章首标题统一由正文首块 HeadingBlock 参与分页测高与绘制，不再在正文外层
    // 追加独立 Column 章头，彻底消除第 0 页底部 54px 裁字。
    return content;
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
          chapterId: currentChapterId,
          annotations: annotationHandler?.chapterAnnotations ?? [],
          searchQuery: activeSearchQuery,
          rawBlocks: chapterData?.blocks,
          blockExtents: chapterData?.blockExtents,
          scrollController: scrollController,
          scrollColumnMaxWidth: resolveViewportMetrics().scrollColumnMaxWidth,
          scrollHorizontalPadding:
              resolveViewportMetrics().scrollHorizontalPadding,
          onBackwardChapterRequest: handleBackwardChapterOverscroll,
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
          onHighlightColor: (text, start, end, color) {
            if (!mounted) return;
            annotationHandler?.highlight(
              text,
              start,
              end,
              context,
              color: color,
            );
          },
          onUpdateAnnotationColor: (annotation, color) {
            if (!mounted) return;
            annotationHandler?.updateColor(annotation, color, context);
          },
          onAnnotate: (text, start, end) {
            if (!mounted) return;
            annotationHandler?.annotate(text, start, end, context);
          },
          onRemoveHighlight: (a) {
            if (!mounted) return;
            annotationHandler?.delete(a, context);
          },
          onRemoveAnnotation: (a) {
            if (!mounted) return;
            annotationHandler?.delete(a, context);
          },
          onLinkTap: handleReaderLinkTap,
          onSelectionActive: onReaderSelectionActive,
          onRegisterSelectionKeyActions: registerReaderSelectionKeyActions,
          onTap: toggleControls,
        ),
      ),
    );
  }
}

/// 跨页外框：`more.css:98` 的 `.spread { transform: none !important }` 覆盖
/// 掉 `desktop.css:429` 的 rotateX(6deg)，终值没有 3D 倾斜与 hover 抬平。
/// 保留 6px 圆角，换成 more.css 给出的双层投影。
/// 跨页外框：不裁切外挂纸叠，阴影与圆角统一由 ReaderPageSpread 承担。
class _SpreadFrame extends StatelessWidget {
  const _SpreadFrame({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size.width, height: size.height, child: child);
  }
}

/// 书签缎带（样例 `.ribbon`；extra.css 覆盖成 16×40、right 8%、燕尾）。
class _BookmarkRibbon extends StatelessWidget {
  const _BookmarkRibbon();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -40, end: 0),
      duration: MotionToken.resolve(context, MotionToken.normal),
      curve: Curves.easeOutCubic,
      builder:
          (context, dy, child) =>
              Transform.translate(offset: Offset(0, dy), child: child),
      child: ClipPath(
        clipper: const _RibbonClipper(),
        child: Container(
          width: 16,
          height: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();

  @override
  Path getClip(Size size) =>
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width / 2, size.height * 0.8)
        ..lineTo(0, size.height)
        ..close();

  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}

/// 页脚页码（样例 `.folio`：11px、距底 4.5%、约 40% 不透明度）。
class _PageWithFolio extends StatelessWidget {
  const _PageWithFolio({
    required this.number,
    required this.child,
    required this.folioBottom,
    required this.bookmarked,
    required this.ribbonRight,
  });

  final int number;
  final Widget child;

  /// 样例 `.folio { bottom: 4.5% }`（跨页）；单页被 reader.css 覆盖为 22px。
  final double folioBottom;
  final bool bookmarked;
  final double ribbonRight;

  @override
  Widget build(BuildContext context) {
    // labelSmall 在 Material 3 即稿子的 11px，不另写裸字号。
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      letterSpacing: 0.06,
    );
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (bookmarked)
          Positioned(
            right: ribbonRight,
            top: 0,
            child: IgnorePointer(child: _BookmarkRibbon()),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: folioBottom,
          child: IgnorePointer(
            child: Center(child: Text('$number', style: style)),
          ),
        ),
      ],
    );
  }
}
