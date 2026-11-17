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

        // 样例 `.bookview.mode-flip`：翻页模式在宽屏是双页跨页；滑动与滚动
        // 模式仍单页满铺。跨页只改呈现与步进，页码/页数/进度口径不变。
        final spread =
            settings.pageTurnMode != 'slide' && viewportSize.width >= 1100;
        // 样例 `.spread`：整幅跨页 1.42 宽高比，最高 780；超出时居中留白，
        // 而不是把两页拉到视口边缘。分页宽高必须跟着画框走，否则文字会溢出。
        final frame =
            spread
                ? _spreadFrame(viewportSize)
                : Size(viewportSize.width, viewportSize.height);
        // 扣除中缝 70px（与 reader_page_spread.dart 的 _spreadGutterWidth 同值；
        // 两者分属不同库，改动时须同步）。
        final halfWidth =
            spread ? math.max(280.0, (frame.width - 70) / 2) : frame.width;
        // 样例 `.pg { padding: 7% 9% 8% }`：CSS 的 padding 百分比一律按包含块
        // 宽度算（含上下），包含块是跨页里的半页。
        // 单页按 `reader.css:51` 覆盖成
        // `max(64px,9vh) max(24px,(100% - 680px)/2) max(56px,9vh)`：正文列
        // 收敛到 680，上下各留一档安全边距。窄视口仍是旧口径——64px 上边距
        // 在手机高度上会直接吃掉正文。
        final singleInsets =
            !spread && frame.width >= 900
                ? ReaderControlLayout.singlePageInsets(frame)
                : null;
        final pageInsets =
            spread
                ? EdgeInsets.only(
                  left: halfWidth * 0.09,
                  right: halfWidth * 0.09,
                  top: halfWidth * 0.07,
                  bottom: halfWidth * 0.08,
                )
                : singleInsets;
        final pageWidth =
            spread
                ? math.max(80.0, halfWidth - (pageInsets?.horizontal ?? 0))
                : pageInsets != null
                ? math.max(80.0, frame.width - pageInsets.horizontal)
                : pageLayout.textColumnWidth;
        // 页脚 folio 预留 20px，避免页码压住最后一行正文；跨页内距同样要从
        // 分页高度里扣掉，否则切片算出的文字会顶到页框之外。
        final availablePageHeight =
            frame.height -
            chromeLayout.chapterHeaderReserve -
            21 -
            (pageInsets?.vertical ?? 0);
        final pageHeight = availablePageHeight > 1 ? availablePageHeight : 1.0;
        // 样例 `.folio { bottom: 4.5% }`，单页被 reader.css 覆盖成 22px。
        final folioBottom = spread ? frame.height * 0.045 : 22.0;
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
            return _PageWithFolio(
              number: index + 1,
              folioBottom: folioBottom,
              // 样例缎带只挂在「当前这一页」；相邻预构建页不能一起挂。
              bookmarked: isBookmarked && index == pageModePage,
              ribbonRight: (spread ? halfWidth : frame.width) * 0.08,
              child: buildPageContent(
                pageData,
                slice,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                chapterTitle: chapterTitle,
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

  /// 跨页画框：1.42 宽高比、最高 780，同时不超出视口。
  Size _spreadFrame(Size viewport) {
    final height = math.min(
      780.0,
      math.min(viewport.height, viewport.width / 1.42),
    );
    return Size(height * 1.42, height);
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
      visibleBlocks: blocks,
      rawBlocks: data.blocks,
      scrollPhysics: scrollPhysics,
      isFirstBlockContinuation: isFirstBlockContinuation,
      pageInsets: pageInsets,
      pageContentWidth: pageContentWidth,
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
          chapterId: currentChapterId,
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
class _SpreadFrame extends StatelessWidget {
  const _SpreadFrame({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 90,
            spreadRadius: -24,
            offset: const Offset(0, 50),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: -10,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );
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
