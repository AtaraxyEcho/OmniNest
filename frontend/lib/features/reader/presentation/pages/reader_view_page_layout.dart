part of 'reader_view_page.dart';

/// 阅读器页面的构建段：骨架、层级栈、面板与顶底栏都在此组装，
/// 状态与命令分别住在 `reader_view_page_commands.dart`。
extension _ReaderViewPageBuild on _ReaderViewPageState {
  // ── Build ──

  Widget _buildReaderSkeleton() {
    return Scaffold(
      backgroundColor: _settings.readerCanvasColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(child: ReaderContentSkeleton(settings: _settings)),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 12,
            child: IconButton(
              tooltip: AppLocalizations.of(context).coreBack,
              onPressed: handleReaderExit,
              icon: Icon(
                Icons.arrow_back_rounded,
                color: _settings.onSurfaceColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(ReaderItemDetail detail, ReaderChapterContent content) {
    _annotationHandler?.chapters =
        _contentLoader?.allChapters ?? detail.chapters;

    return Focus(
      autofocus: true,
      onKeyEvent:
          (node, event) => _handleReaderKeyEvent(event, detail, content),
      child: _buildReaderStack(detail, content),
    );
  }

  Widget _buildReaderStack(
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) {
    final viewport = MediaQuery.sizeOf(context);
    // 样例 ReaderFocus 皮肤只在移动壳层形态启用（Android/手机浏览器/
    // 桌面窄窗）；桌面宽窗维持工位实底 chrome。
    final sampleChrome = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: viewport.width,
    );
    final readerLayout = ReaderControlLayout.resolve(
      viewport: viewport,
      fontSize: _settings.fontSize,
      textScale: FontScaleScope.systemScalerOf(context).scale(1),
    );
    final screenWidth = viewport.width;
    final contentWidth = math.min(screenWidth, readerLayout.contentFrameWidth);
    final offset = (screenWidth - contentWidth) / 2;
    // 滚动模式全视口由正文承接，不再计算边距侧按热区。
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: _settings.immersiveMode,
      isPageMode: _isPageMode,
      // 本页 body 未套 SafeArea（全屏排版），正文自行兜底刘海与手势条。
      safePadding: MediaQuery.viewPaddingOf(context),
    );

    return Stack(
      children: [
        // 内容层（z=1）+ 护眼暖色与亮度滤镜（z=2，严格置于顶底栏与浮层面板之下）。
        Positioned.fill(
          key: const Key('readerContentViewportPadding'),
          child: ReaderComfortFilter(
            brightness: _settings.brightness,
            warmth: _settings.warmth,
            // 舞台背景平滑渐变 + 新模式单向进场柔化过渡（绝不同时保留两棵带 ScrollController 的子树）
            child: AnimatedContainer(
              duration:
                  animationsDisabled
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              decoration:
                  _settings.usesBookDesk
                      ? BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.2),
                          radius: 1.1,
                          colors: [
                            Color.lerp(
                              _settings.bookDeskColor,
                              Colors.white,
                              0.12,
                            )!,
                            _settings.bookDeskColor,
                          ],
                          stops: const [0.0, 0.70],
                        ),
                      )
                      : BoxDecoration(color: _settings.surfaceColor),
              child: FontScaleScope.withSystemScaleOnly(
                context: context,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey<String>(
                    'mode-${_settings.readingMode}-${_settings.pageTurnMode}',
                  ),
                  tween: Tween<double>(
                    begin: animationsDisabled ? 1.0 : 0.0,
                    end: 1.0,
                  ),
                  duration:
                      animationsDisabled
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder:
                      (context, t, child) => Opacity(
                        opacity: t,
                        alwaysIncludeSemantics: true,
                        child: Transform.scale(
                          scale: 0.988 + 0.012 * t,
                          child: child,
                        ),
                      ),
                  child: _buildContent(content, detail),
                ),
              ),
            ),
          ),
        ),
        // Book 模式左右悬浮圆形翻页箭头（对齐样例 `.bk-arrow.l / .r`）
        if (_settings.usesBookDesk &&
            !sampleChrome &&
            viewport.width >= 960) ...[
          Positioned(
            left: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: _BookFloatingArrow(
                icon: Icons.chevron_left_rounded,
                tooltip: AppLocalizations.of(context).readerPreviousPage,
                onTap: () {
                  if (_selectionActive) clearReaderSelection();
                  _pageTurnController.previous();
                },
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: _BookFloatingArrow(
                icon: Icons.chevron_right_rounded,
                tooltip: AppLocalizations.of(context).readerNextPage,
                onTap: () {
                  if (_selectionActive) clearReaderSelection();
                  _pageTurnController.next();
                },
              ),
            ),
          ),
        ],
        // 本章图片降级计数提示：控制栏展开时让位，关闭后只在本章内静音。
        if (!_showControls &&
            _dismissedImageBudgetChapterId != _currentChapterId &&
            shouldShowImageBudgetNotice(content.droppedImageCount))
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: offset,
            right: offset,
            child: ReaderImageBudgetNotice(
              count: content.droppedImageCount ?? 0,
              settings: _settings,
              label: AppLocalizations.of(
                context,
              ).readerImagesNotLoaded(content.droppedImageCount!),
              hint: AppLocalizations.of(context).readerImagesNotLoadedHint,
              dismissTooltip: AppLocalizations.of(context).coreClose,
              onDismiss:
                  () => _updateState(
                    () => _dismissedImageBudgetChapterId = _currentChapterId,
                  ),
            ),
          ),
        // 进度恢复加载遮罩：定位完成后自动消失
        // 内容未加载时 skeleton 已有加载指示器，不重复显示
        if (_isRestoringProgress && _cachedContent != null)
          Positioned.fill(
            child: ReaderDeferredRestoreOverlay(settings: _settings),
          ),
        // 滚动模式对齐样例 ReaderView.tsx:419：不再在左右边距叠加 SideTapZone，
        // 全视口交由 ListView 响应滚轮与触控，仅中央 30%-70% 单击切换控制栏。
        // 顶栏和底栏只占自己的几何范围。正文必须一直保留指针命中，才能在
        // chrome 首次显示时继续左右翻页、上下滚动；正文的中心点击由
        // ReaderPageView/ReaderViewContent 统一切换 chrome，避免一个全屏遮罩
        // 把手势截断后只能先隐藏栏再翻页。
        // 顶部栏
        _buildTopBar(detail, content, sampleChrome: sampleChrome),
        // 底部栏
        _buildBottomBar(detail, content, sampleChrome: sampleChrome),
        // Positioned 必须是 Stack 的直接子节点。控件原先自己返回 Positioned，
        // 又被包进 IgnorePointer → AnimatedOpacity 的交叉淡入链里，StackParentData
        // 因此挂到 FadeTransition 上，阅读页每帧抛 Incorrect use of ParentDataWidget。
        // 定位几何上提到这里，动画链留在 Positioned 内部。
        // 常驻进度胶囊只在工位皮肤下保留：移动端样例页脚自带进度行，
        // 再挂一条就是同一条信息的两种密度叠在一起。
        if (chromeLayout.showPersistentProgress && !sampleChrome)
          Positioned(
            left: sampleChrome ? 20 : null,
            right: sampleChrome ? 20 : 16,
            bottom:
                (sampleChrome ? 10 : 16) +
                MediaQuery.viewPaddingOf(context).bottom,
            child: ValueListenableBuilder<double?>(
              valueListenable: _bookProgressNotifier,
              builder:
                  (context, bookProgress, _) => IgnorePointer(
                    ignoring: _showControls,
                    child: AnimatedOpacity(
                      // 常驻进度胶囊与控制栏里的进度是同一条信息的两种密度。
                      // 条件挂载会让两个几何不同的控件在切换瞬间互换，观感上是"进度原地跳走"；
                      // 改为常驻并与控制栏同速交叉淡入淡出。
                      opacity: _showControls ? 0 : 1,
                      duration:
                          animationsDisabled
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                      alwaysIncludeSemantics: true,
                      child: ValueListenableBuilder<int>(
                        valueListenable: pageCountNotifier,
                        builder:
                            (context, totalPageCount, _) =>
                                ReaderProgressIndicator(
                                  key: const Key('readerPersistentProgress'),
                                  settings: _settings,
                                  progress: bookProgress ?? 0,
                                  currentPage:
                                      _isPageMode ? _pageModePage : null,
                                  totalPages:
                                      _isPageMode && totalPageCount > 0
                                          ? totalPageCount
                                          : null,
                                  sampleChrome: sampleChrome,
                                ),
                      ),
                    ),
                  ),
            ),
          ),
        ..._buildOverlays(content),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showChapterLoadingOverlay,
            child: AnimatedOpacity(
              opacity: _showChapterLoadingOverlay ? 1.0 : 0.0,
              duration:
                  animationsDisabled
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
              alwaysIncludeSemantics: true,
              child: ColoredBox(
                color: _settings.readerCanvasColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _settings.accentColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentChapterTitle,
                        style: TextStyle(
                          color: _settings.onSurfaceVariantColor,
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ..._buildReaderPanels(
          detail,
          content,
          readerLayout,
          sampleChrome: sampleChrome,
        ),
      ],
    );
  }

  /// 构建章节列表面板（直接在 Stack 内渲染，不使用独立路由）。
  ///
  /// 书名眉标由 [ReaderAdaptivePanelOverlay] 的头部负责，这里不再传一遍。
  Widget _buildChapterPanel(ReaderItemDetail detail) {
    final allChapters = _chaptersFor(detail);

    return ChapterPanel(
      chapters: allChapters,
      currentChapterId: _currentChapterId,
      settings: _settings,
      onChapterTap: (chapterId) {
        _closeReaderPanel();
        onChapterSelected(chapterId);
      },
    );
  }

  List<Widget> _buildOverlays(ReaderChapterContent content) => [
    if (_showTts)
      Positioned(
        bottom: _showControls ? 82 : 0,
        left: 0,
        right: 0,
        child: ReaderTtsControls(text: getPlainText(content.content)),
      ),
    if (_showReturnControl) buildReturnToProgressControl(),
    if (_showRemoteProgressCue) buildRemoteProgressCue(),
  ];

  /// 底部浮动"返回原进度"控件（参考微信读书样式）。
  ///
  /// 底部栏显示时，控件上移到底部栏上方。

  Widget _buildTopBar(
    ReaderItemDetail detail,
    ReaderChapterContent content, {
    bool sampleChrome = false,
  }) {
    final dur =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240);
    final badgeCount =
        (_annotationHandler?.annotations.length ?? 0) + _bookmarks.length;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: _showControls ? Offset.zero : const Offset(0, -0.15),
        duration: dur,
        curve: MotionToken.curve,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: dur,
          alwaysIncludeSemantics: true,
          child: IgnorePointer(
            ignoring: !_showControls,
            child: MouseRegion(
              onEnter: (_) => onHoverControls(true),
              onExit: (_) => onHoverControls(false),
              child: ReaderViewTopBar(
                settings: _settings,
                bookTitle: detail.item.title,
                chapterTitle: content.title,
                sampleChrome: sampleChrome,
                onBack: handleReaderExit,
                onSearch: () => _toggleReaderPanel(ReaderPanelType.search),
                onShowShortcuts:
                    () => _toggleReaderPanel(ReaderPanelType.shortcuts),
                onAddBookmark:
                    _bookmarkBusy
                        ? null
                        : () => toggleBookmark(detail, content),
                onToggleBookshelf: () => toggleBookshelf(detail),
                onToggleTts: () {
                  _hideTimer?.cancel();
                  _updateState(() {
                    _panelCoordinator.close();
                    _showTts = !_showTts;
                  });
                },
                onShowAnnotations:
                    () => _toggleReaderPanel(ReaderPanelType.annotations),
                isBookmarked: _isBookmarked,
                isInBookshelf:
                    _bookshelfOverride ?? detail.item.addedToBookshelf,
                desktopPrototypeChrome: !sampleChrome,
                pageModeEnabled: supportsPageMode,
                activePanel: _panelCoordinator.active,
                annotationBadgeCount: badgeCount,
                onSettingsChanged: onSettingsChanged,
                onShowContents:
                    () => _toggleReaderPanel(ReaderPanelType.contents),
                onShowSettings:
                    () => _toggleReaderPanel(ReaderPanelType.settings),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    ReaderItemDetail detail,
    ReaderChapterContent content, {
    bool sampleChrome = false,
  }) {
    final chapters = _chaptersFor(detail);
    final dur =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240);
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: _showControls ? Offset.zero : const Offset(0, 0.15),
        duration: dur,
        curve: MotionToken.curve,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: dur,
          alwaysIncludeSemantics: true,
          child: IgnorePointer(
            ignoring: !_showControls,
            child: MouseRegion(
              onEnter: (_) => onHoverControls(true),
              onExit: (_) => onHoverControls(false),
              child: ValueListenableBuilder<double?>(
                valueListenable: _bookProgressNotifier,
                builder:
                    (context, bookProgress, _) => ValueListenableBuilder<int>(
                      valueListenable: pageCountNotifier,
                      builder:
                          (context, pageCount, _) => ReaderViewBottomBar(
                            settings: _settings,
                            progress: bookProgress ?? 0,
                            isPageMode: _isPageMode,
                            currentPage: _isPageMode ? pageModePage : null,
                            totalPages: _isPageMode ? pageCount : null,
                            sampleChrome: sampleChrome,
                            desktopPrototypeChrome: !sampleChrome,
                            onPrevious:
                                () => _navigateReader(detail, forward: false),
                            onNext:
                                () => _navigateReader(detail, forward: true),
                            onPreviousChapter: () => tryNavigateChapter(-1),
                            onNextChapter: () => tryNavigateChapter(1),
                            chapterIndex: _currentChapterPosition(chapters),
                            chapterCount: chapters.length,
                            onShowContents:
                                () => _toggleReaderPanel(
                                  ReaderPanelType.contents,
                                ),
                            onShowSettings:
                                () => _toggleReaderPanel(
                                  ReaderPanelType.settings,
                                ),
                            onToggleImmersive: _toggleReaderImmersive,
                            onAddBookmark:
                                _bookmarkBusy
                                    ? null
                                    : () => toggleBookmark(detail, content),
                            onProgressSeek: (value) => _seekBookProgress(value),
                          ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 阅读页章节列表的统一来源：已装载的内容加载器优先（正在读的就是这一份），
  /// 其次服务端清单映射，最后才是详情响应带的章节。
  ///
  /// 后端详情响应不下发章节，只读 `detail.chapters` 时目录恒空，底栏的
  /// "第 N / M 章" 整块不出现，章节位次也永远解析不到。
  List<ReaderChapter> _chaptersFor(ReaderItemDetail detail) {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    return readerChapterSource(
      loaded: _contentLoader?.allChapters,
      manifest: parsedBook == null ? null : _cachedChaptersFor(parsedBook),
      fromDetail: detail.chapters,
    );
  }

  /// 当前章在目录里的 1-based 序号；章节尚未装载或不在册时返回 null。
  int? _currentChapterPosition(List<ReaderChapter> chapters) {
    final index = chapters.indexWhere(
      (chapter) => chapter.id == _currentChapterId,
    );
    return index < 0 ? null : index + 1;
  }

  Widget _buildContent(ReaderChapterContent content, ReaderItemDetail detail) {
    if (kDebugMode) {
      readerDebugLog(
        'ReaderView: rendering content — '
        'mode=${_isPageMode ? "page" : "scroll"}, '
        'contentLength=${content.content.length}',
      );
    }
    if (_isPageMode) return buildPageModeContent(content, detail);
    return buildScrollModeContent(content, detail);
  }
}

/// 阅读页章节列表的来源优先级：已装载的章节 > 服务端清单映射 > 详情响应带的章节。
///
/// 后端详情响应只带 item 与 progress，`ReaderItemDetail.chapters` 恒为空：
/// 直接读它时底栏的"第 N / M 章"整块不出现，章末卡的位次与"下一章"也解析不到。
/// 前两级为 null 或空列表时继续降级，避免章节切换的瞬间目录空掉。
List<ReaderChapter> readerChapterSource({
  required List<ReaderChapter>? loaded,
  required List<ReaderChapter>? manifest,
  required List<ReaderChapter> fromDetail,
}) {
  if (loaded != null && loaded.isNotEmpty) {
    return loaded;
  }
  if (manifest != null && manifest.isNotEmpty) {
    return manifest;
  }
  return fromDetail;
}

/// Book 模式左右悬浮圆形翻页按钮（对齐样例 `.bk-arrow`：48×48 圆形半透明，悬停放大 1.1x）。
class _BookFloatingArrow extends StatefulWidget {
  const _BookFloatingArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_BookFloatingArrow> createState() => _BookFloatingArrowState();
}

class _BookFloatingArrowState extends State<_BookFloatingArrow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedScale(
          scale: _hovered ? 1.1 : 1.0,
          duration: MotionToken.reduced(context, MotionToken.pageSwitch),
          curve: Curves.easeOutBack,
          child: Material(
            color: Colors.white.withValues(alpha: _hovered ? 0.18 : 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: widget.onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(widget.icon, size: 24, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
