part of 'reader_view_page.dart';

/// 阅读器页面的构建段：骨架、层级栈、面板与顶底栏都在此组装，
/// 状态与命令分别住在 `reader_view_page_commands.dart`。
extension _ReaderViewPageBuild on _ReaderViewPageState {
  // ── Build ──

  Widget _buildReaderSkeleton() {
    return Scaffold(
      backgroundColor: _resolveSurface(),
      body: SafeArea(child: ReaderContentSkeleton(settings: _settings)),
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
    final edgeWidth = (contentWidth * 0.12).clamp(44.0, 72.0);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: _settings.immersiveMode,
      isPageMode: _isPageMode,
      // 本页 body 未套 SafeArea（全屏排版），正文自行兜底刘海与手势条。
      safePadding: MediaQuery.viewPaddingOf(context),
    );

    return Stack(
      children: [
        // 内容层：剔除应用字体档位仅保留系统缩放，保证自绘分页测量与渲染一致
        Positioned.fill(
          child: FontScaleScope.withSystemScaleOnly(
            context: context,
            child: Padding(
              key: const Key('readerContentViewportPadding'),
              padding: chromeLayout.contentPadding,
              child: _buildContent(content, detail),
            ),
          ),
        ),
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
        // 点击区域（控制栏显示时禁用，翻页模式下由 ReaderPageView 自行处理）
        if (!_showControls && !_isPageMode && !_selectionActive) ...[
          // 左边缘：向上滚动
          Positioned(
            top: 35,
            left: 0,
            width: offset + edgeWidth,
            bottom: 16,
            child: SideTapZone(
              onTap: () => handleSideTap(detail, forward: false),
            ),
          ),
          // 右边缘：向下滚动
          Positioned(
            top: 35,
            left: offset + contentWidth - edgeWidth,
            right: 0,
            bottom: 16,
            child: SideTapZone(
              onTap: () => handleSideTap(detail, forward: true),
            ),
          ),
        ],
        // 控制栏显示时：全屏遮罩（点击任意位置关闭控制栏）
        if (_showControls)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _updateState(() => _showControls = false);
              },
              child: const SizedBox.expand(),
            ),
          ),
        // 顶部栏（在遮罩之上，可接收点击）
        _buildTopBar(detail, content, sampleChrome: sampleChrome),
        // 底部栏（在遮罩之上，可接收点击）
        _buildBottomBar(detail, content, sampleChrome: sampleChrome),
        // Positioned 必须是 Stack 的直接子节点。控件原先自己返回 Positioned，
        // 又被包进 IgnorePointer → AnimatedOpacity 的交叉淡入链里，StackParentData
        // 因此挂到 FadeTransition 上，阅读页每帧抛 Incorrect use of ParentDataWidget。
        // 定位几何上提到这里，动画链留在 Positioned 内部。
        if (chromeLayout.showPersistentProgress)
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
                      child: ReaderProgressIndicator(
                        key: const Key('readerPersistentProgress'),
                        settings: _settings,
                        progress: bookProgress ?? 0,
                        currentPage: _isPageMode ? _pageModePage : null,
                        totalPages: null, // 懒分页不预知总页数
                        sampleChrome: sampleChrome,
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
              child: ColoredBox(
                color: _resolveSurface(),
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
        ..._buildReaderPanels(detail, content, readerLayout),
      ],
    );
  }

  /// 构建章节列表面板（直接在 Stack 内渲染，不使用独立路由）
  Widget _buildChapterPanel(ReaderItemDetail detail) {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    final allChapters =
        parsedBook == null ? detail.chapters : _cachedChaptersFor(parsedBook);

    return ChapterPanel(
      chapters: allChapters,
      currentChapterId: _currentChapterId,
      settings: _settings,
      onChapterTap: (chapterId) {
        _closeReaderPanel();
        onChapterSelected(chapterId);
      },
      onDismiss: _closeReaderPanel,
      embedded: true,
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
  ];

  /// 底部浮动"返回原进度"控件（参考微信读书样式）。
  ///
  /// 底部栏显示时，控件上移到底部栏上方。

  Widget _buildTopBar(
    ReaderItemDetail detail,
    ReaderChapterContent content, {
    bool sampleChrome = false,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration:
            MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
        // 语义子树常驻：opacity 归零默认摘除语义，会触发 Windows 桥更新失败。
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
              onBack: () {
                syncProgressSync();
                safePop();
              },
              onSearch: () => _toggleReaderPanel(ReaderPanelType.search),
              onShowShortcuts:
                  () => _toggleReaderPanel(ReaderPanelType.shortcuts),
              onAddBookmark:
                  _bookmarkBusy ? null : () => toggleBookmark(detail, content),
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
              isInBookshelf: _bookshelfOverride ?? detail.item.addedToBookshelf,
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
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration:
            MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
        alwaysIncludeSemantics: true,
        child: IgnorePointer(
          ignoring: !_showControls,
          child: MouseRegion(
            onEnter: (_) => onHoverControls(true),
            onExit: (_) => onHoverControls(false),
            child: ValueListenableBuilder<double?>(
              valueListenable: _bookProgressNotifier,
              builder:
                  (context, bookProgress, _) => ReaderViewBottomBar(
                    settings: _settings,
                    progress: bookProgress ?? 0,
                    isPageMode: _isPageMode,
                    sampleChrome: sampleChrome,
                    onPrevious: () => _navigateReader(detail, forward: false),
                    onNext: () => _navigateReader(detail, forward: true),
                    onShowContents:
                        () => _toggleReaderPanel(ReaderPanelType.contents),
                    onShowSettings:
                        () => _toggleReaderPanel(ReaderPanelType.settings),
                    onToggleImmersive: _toggleReaderImmersive,
                    onProgressSeek: (value) => _seekBookProgress(value),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ReaderChapterContent content, ReaderItemDetail detail) {
    if (kDebugMode) {
      readerDebugLog(
        'ReaderView: rendering content — '
        'mode=${_isPageMode ? "page" : "scroll"}, '
        'contentLength=${content.content.length}',
      );
    }
    if (_isPageMode) return buildPageModeContent(content);
    return buildScrollModeContent(content, detail);
  }
}
