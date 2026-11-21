part of 'comic_reader_view.dart';

/// 单页或双页跨页渲染槽。
class _ComicSpreadSlot {
  const _ComicSpreadSlot(this.pageIndices);

  final List<int> pageIndices;

  int get startPageIndex => pageIndices.first;
  int get endPageIndex => pageIndices.last;
}

class _ComicPageTurnCallbacks implements PageTurnCallbacks {
  const _ComicPageTurnCallbacks({
    required this.onPageChangedFn,
    required this.onToggleControlsFn,
  });

  final ValueChanged<int> onPageChangedFn;
  final VoidCallback onToggleControlsFn;

  @override
  void onPageChanged(int pageIndex) => onPageChangedFn(pageIndex);

  @override
  void onPreviousChapter() {}

  @override
  void onNextChapter() {}

  @override
  void onToggleControls() => onToggleControlsFn();
}

/// 漫画阅读器的模式切换、双页拼合、独立缩放、书签、跳转与内容构建。
extension _ComicReaderViewSections on ComicReaderViewState {
  /// 预加载当前页前后的图片。
  void _preloadAdjacent() {
    if (_totalPages <= 0) {
      return;
    }
    final loader = ref.read(comicImageLoaderProvider);
    final start = (_anchor.pageIndex - 2).clamp(0, _totalPages - 1).toInt();
    final end = (_anchor.pageIndex + 4).clamp(0, _totalPages - 1).toInt();
    final pagesToLoad = <ComicPage>[];
    for (var i = start; i <= end; i++) {
      pagesToLoad.add(_pages[i]);
    }
    unawaited(loader.preloadImages(widget.itemId, pagesToLoad));
  }

  ComicReadingMode _modeFromName(String mode) {
    return switch (mode) {
      'book' => ComicReadingMode.book,
      'page' || 'swipe' => ComicReadingMode.page,
      _ => ComicReadingMode.scroll,
    };
  }

  String _modeName(ComicReadingMode mode) {
    return switch (mode) {
      ComicReadingMode.book => 'book',
      ComicReadingMode.page => 'page',
      ComicReadingMode.scroll => 'scroll',
    };
  }

  ComicReaderLayout _resolveLayout(
    Size viewport, {
    ComicReaderDisplaySettings? settings,
  }) {
    final resolved = settings ?? _displaySettings;
    return ComicReaderLayout.resolve(
      viewport: viewport,
      preferredContentWidth: resolved.contentWidth,
      fullWidth: resolved.fullWidth,
    );
  }

  /// 计算当前视口下的单/双页槽位列表：
  /// - 首页封面单页居中；
  /// - 跨页宽图（width > height * 1.15）自动独占整屏；
  /// - 其余页按顺序两两配对。
  List<_ComicSpreadSlot> _buildSpreadSlots(double viewportWidth) {
    if (_totalPages <= 0) return const [];
    final useDual =
        _isPagedMode && _displaySettings.dualPage && viewportWidth >= 720;
    if (!useDual) {
      return [
        for (var i = 0; i < _totalPages; i++) _ComicSpreadSlot([i]),
      ];
    }

    bool isWideSpread(ComicPage page) {
      final w = page.width;
      final h = page.height;
      return w != null && h != null && h > 0 && w > h * 1.15;
    }

    final slots = <_ComicSpreadSlot>[];
    var i = 0;
    while (i < _totalPages) {
      final current = _pages[i];
      // 首页封面或跨页宽图独占整屏
      if (i == 0 || isWideSpread(current)) {
        slots.add(_ComicSpreadSlot([i]));
        i++;
        continue;
      }
      if (i + 1 < _totalPages && !isWideSpread(_pages[i + 1])) {
        slots.add(_ComicSpreadSlot([i, i + 1]));
        i += 2;
      } else {
        slots.add(_ComicSpreadSlot([i]));
        i++;
      }
    }
    return slots;
  }

  int _slotIndexForPage(List<_ComicSpreadSlot> slots, int pageIndex) {
    if (slots.isEmpty) return 0;
    for (var i = 0; i < slots.length; i++) {
      if (pageIndex >= slots[i].startPageIndex &&
          pageIndex <= slots[i].endPageIndex) {
        return i;
      }
    }
    return slots.length - 1;
  }

  /// 切换阅读模式（依次循环或直切指定模式），保持当前阅读锚点。
  void _switchReadingMode() {
    final nextMode = switch (_readingMode) {
      ComicReadingMode.book => 'page',
      ComicReadingMode.page => 'scroll',
      ComicReadingMode.scroll => 'book',
    };
    _selectReadingMode(nextMode);
  }

  void _selectReadingMode(String mode) {
    _applyDisplaySettings(_displaySettings.copyWith(readingMode: mode));
  }

  void _applyDisplaySettings(ComicReaderDisplaySettings settings) {
    final previousMode = _readingMode;
    final nextMode = _modeFromName(settings.readingMode);
    final frozenAnchor = _anchor;

    _resetAllSlotTransforms();
    _update(() {
      _displaySettings = settings;
      _readingMode = nextMode;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _layoutIndex.updateContentWidth(
        _resolveLayout(MediaQuery.sizeOf(context)).contentWidth,
      );
      if (previousMode != ComicReadingMode.scroll &&
          nextMode == ComicReadingMode.scroll) {
        _startScrollRestore(frozenAnchor);
      } else if (previousMode == ComicReadingMode.scroll &&
          nextMode != ComicReadingMode.scroll) {
        _saveProgress();
      } else if (nextMode == ComicReadingMode.scroll) {
        _startScrollRestore(frozenAnchor);
      }
      _update(() {
        _anchor = frozenAnchor;
      });
    });

    _displaySettingsSaveTimer?.cancel();
    _pendingDisplaySettings = settings;
    _displaySettingsSaveTimer = Timer(const Duration(milliseconds: 320), () {
      _pendingDisplaySettings = null;
      unawaited(_saveDisplaySettings(settings));
    });
  }

  Future<void> _saveDisplaySettings(ComicReaderDisplaySettings settings) async {
    final current = await ref.read(readerPreferencesProvider.future);
    if (!mounted) return;
    await ref
        .read(readerPreferencesProvider.notifier)
        .save(
          mergeComicReaderPreferences(
            current: current,
            appliedDisplaySettings: settings,
            itemId: widget.itemId,
          ),
        );
  }

  /// 切换控件显示/隐藏。
  void _toggleControls() {
    if (_panelCoordinator.close()) {
      _update(() {});
      return;
    }
    _update(() => _showControls = !_showControls);
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    if (_showControls && !_panelCoordinator.isOpen) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls && !_panelCoordinator.isOpen) {
          _update(() => _showControls = false);
        }
      });
    }
  }

  /// 展开右侧磨砂抽屉时保持顶栏可见，支持一键切换目录 / 书签 / 设置面板。
  void _togglePanel(ReaderPanelType panel) {
    _hideControlsTimer?.cancel();
    _update(() {
      _panelCoordinator.toggle(panel);
      _showControls = true;
    });
  }

  void _closePanel() {
    if (_panelCoordinator.close()) {
      _update(() {});
      _scheduleControlsHide();
    }
  }

  // ── 漫画书签 ──

  ReaderBookmark? _findBookmarkForPage(
    List<ReaderBookmark> bookmarks,
    int pageIndex,
  ) {
    for (final bm in bookmarks) {
      if (bm.charOffset == pageIndex) {
        return bm;
      }
    }
    return null;
  }

  Future<void> _toggleCurrentPageBookmark(
    List<ReaderBookmark> bookmarks,
  ) async {
    if (_totalPages <= 0) return;
    final dataManager = ref.read(readerDataManagerProvider);
    final existing = _findBookmarkForPage(bookmarks, _anchor.pageIndex);
    if (existing != null) {
      await dataManager.deleteBookmark(existing.id);
    } else {
      final page = _pages[_anchor.pageIndex];
      final progress = ((_anchor.pageIndex + 1) / _totalPages).clamp(0.0, 1.0);
      await dataManager.createBookmark(
        itemId: widget.itemId,
        charOffset: _anchor.pageIndex,
        progressPercent: progress,
        chapterId: page.catalogNodeId,
        note: 'P.${_anchor.pageIndex + 1}',
      );
    }
    if (mounted) {
      ref.invalidate(readerItemBookmarksProvider(widget.itemId));
    }
  }

  Future<void> _deleteBookmark(ReaderBookmark bookmark) async {
    await ref.read(readerDataManagerProvider).deleteBookmark(bookmark.id);
    if (mounted) {
      ref.invalidate(readerItemBookmarksProvider(widget.itemId));
    }
  }

  /// 跳转到指定目录节点的起始页。
  void _jumpToCatalogNode(ComicCatalogNode node) {
    final targetIndex = resolveComicCatalogStartPage(_manifest, node.id);
    if (targetIndex == null || targetIndex >= _totalPages) {
      return;
    }
    _jumpToPage(targetIndex);
  }

  void _jumpToPage(int index) {
    if (_totalPages <= 0) {
      return;
    }
    final targetIndex = index.clamp(0, _totalPages - 1).toInt();
    if (comicJumpIsNoOp(
      targetIndex: targetIndex,
      currentPageIndex: _anchor.pageIndex,
      intraPageOffset: _anchor.intraPageOffset,
      isPageMode: _isPagedMode,
    )) {
      return;
    }

    _resetAllSlotTransforms();
    final page = _pages[targetIndex];
    final targetAnchor = ComicAnchor(
      pageId: page.id,
      pageIndex: targetIndex,
      pageFingerprint: page.fingerprint,
      sourceId: page.sourceId,
      sourcePageIndex: page.sourcePageIndex,
      catalogKey: page.catalogKey,
      intraPageOffset: 0.0,
      manifestVersion: _manifest.manifestVersion,
    );
    _update(() {
      _anchor = targetAnchor;
    });

    if (_readingMode == ComicReadingMode.scroll) {
      _startScrollRestore(targetAnchor);
    }
    _saveProgress();
  }

  void _turnSlotByDelta(int delta) {
    if (!_isPagedMode) {
      _scrollByPage(delta);
      return;
    }
    if (_imageZoomed) {
      _resetCurrentSlotZoom();
    }
    if (delta > 0) {
      _pageTurnController.next();
    } else if (delta < 0) {
      _pageTurnController.previous();
    }
  }

  void _handleScrollContentTap(Offset position) {
    if (_showControls) {
      _toggleControls();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final x = position.dx;
    if (x < width * 0.3 || x > width * 0.7) {
      return;
    }
    _toggleControls();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final textInputFocused =
        focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    final command = const ReaderShortcutResolver().resolve(
      key: event.logicalKey,
      mode:
          _isPagedMode
              ? ReaderShortcutMode.comicPage
              : ReaderShortcutMode.comicScroll,
      shiftPressed: hardware.isShiftPressed,
      controlPressed: hardware.isControlPressed || hardware.isMetaPressed,
      isRtl: _isRtl,
      textInputFocused: textInputFocused,
      imageZoomed: _imageZoomed,
    );
    if (command == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && !_isRepeatableCommand(command)) {
      return KeyEventResult.handled;
    }
    if (_requiresCommandGate(command) && !_commandGate.accept()) {
      return KeyEventResult.handled;
    }
    _executeCommand(command);
    return KeyEventResult.handled;
  }

  bool _isRepeatableCommand(ReaderCommand command) {
    return command == ReaderCommand.nextViewport ||
        command == ReaderCommand.previousViewport ||
        command == ReaderCommand.scrollForward ||
        command == ReaderCommand.scrollBackward;
  }

  bool _requiresCommandGate(ReaderCommand command) {
    return command == ReaderCommand.nextPage ||
        command == ReaderCommand.previousPage ||
        command == ReaderCommand.toggleReadingMode;
  }

  void _executeCommand(ReaderCommand command) {
    switch (command) {
      case ReaderCommand.closeLayer:
        _closeLayer();
        return;
      case ReaderCommand.toggleContents:
        _togglePanel(ReaderPanelType.contents);
        return;
      case ReaderCommand.toggleBookmark:
        final bms =
            ref
                .read(readerItemBookmarksProvider(widget.itemId))
                .asData
                ?.value ??
            const <ReaderBookmark>[];
        unawaited(_toggleCurrentPageBookmark(bms));
        return;
      case ReaderCommand.toggleImmersive:
        _toggleControls();
        return;
      case ReaderCommand.toggleFullscreen:
        _toggleFullscreen();
        return;
      case ReaderCommand.showShortcuts:
        _togglePanel(ReaderPanelType.shortcuts);
        return;
      case ReaderCommand.increaseFont:
        _zoomByStep(0.35);
        return;
      case ReaderCommand.decreaseFont:
        _zoomByStep(-0.35);
        return;
      case ReaderCommand.resetTypography:
        _resetCurrentSlotZoom();
        return;
      case ReaderCommand.nextPage:
        _turnSlotByDelta(1);
        return;
      case ReaderCommand.previousPage:
        _turnSlotByDelta(-1);
        return;
      case ReaderCommand.nextViewport:
        _scrollByPage(1);
        return;
      case ReaderCommand.previousViewport:
        _scrollByPage(-1);
        return;
      case ReaderCommand.scrollForward:
        _scrollByPage(1, viewportFactor: 0.16);
        return;
      case ReaderCommand.scrollBackward:
        _scrollByPage(-1, viewportFactor: 0.16);
        return;
      case ReaderCommand.chapterStart:
        _jumpToPage(0);
        return;
      case ReaderCommand.chapterEnd:
        _jumpToPage(_totalPages - 1);
        return;
      case ReaderCommand.toggleReadingMode:
        _switchReadingMode();
        return;
      case ReaderCommand.openSearch:
      case ReaderCommand.openAnnotations:
      case ReaderCommand.nextChapter:
      case ReaderCommand.previousChapter:
        return;
    }
  }

  void _closeLayer() {
    if (_panelCoordinator.close()) {
      _update(() {});
      return;
    }
    if (_imageZoomed) {
      _resetCurrentSlotZoom();
      return;
    }
    if (_showControls) {
      _hideControlsTimer?.cancel();
      _update(() => _showControls = false);
      return;
    }
    _requestExit();
  }

  void _requestExit() {
    if (_exitRequested || !mounted) {
      return;
    }
    _exitRequested = true;
    unawaited(() async {
      await flushReadingProgress();
      if (mounted) {
        widget.onBack();
      }
    }());
  }

  void _toggleFullscreen() {
    switch (resolveFullscreenCommandTarget(
      isWeb: isWebPlatform,
      isDesktop: isDesktopPlatform,
    )) {
      case FullscreenCommandTarget.browser:
        fs.toggleFullscreen();
      case FullscreenCommandTarget.windowChrome:
        unawaited(
          ref.read(windowChromeControllerProvider.notifier).toggleFullscreen(),
        );
      case FullscreenCommandTarget.none:
        break;
    }
  }

  // ── 每页独立缩放控制器（离屏复位 1.0x，放大 > 1.02 自动锁翻页拖拽） ──

  TransformationController _controllerForSlot(int slotIndex) {
    return _slotTransformControllers.putIfAbsent(
      slotIndex,
      TransformationController.new,
    );
  }

  void _resetOffscreenSlotTransforms(int activeSlotIndex) {
    for (final entry in _slotTransformControllers.entries) {
      if (entry.key != activeSlotIndex &&
          entry.value.value.getMaxScaleOnAxis() > 1.001) {
        entry.value.value = Matrix4.identity();
      }
    }
    final activeScale =
        _slotTransformControllers[activeSlotIndex]?.value.getMaxScaleOnAxis() ??
        1.0;
    if ((activeScale - _currentZoomScale).abs() > 0.005) {
      _update(() => _currentZoomScale = activeScale);
    }
  }

  void _resetAllSlotTransforms() {
    for (final ctrl in _slotTransformControllers.values) {
      if (ctrl.value.getMaxScaleOnAxis() > 1.001) {
        ctrl.value = Matrix4.identity();
      }
    }
    if (_currentZoomScale != 1.0) {
      _update(() => _currentZoomScale = 1.0);
    }
  }

  void _resetCurrentSlotZoom() {
    if (!_isPagedMode) return;
    final slots = _buildSpreadSlots(MediaQuery.sizeOf(context).width);
    final activeSlotIndex = _slotIndexForPage(slots, _anchor.pageIndex);
    final ctrl = _slotTransformControllers[activeSlotIndex];
    if (ctrl != null) {
      ctrl.value = Matrix4.identity();
    }
    if (_currentZoomScale != 1.0) {
      _update(() => _currentZoomScale = 1.0);
    }
  }

  void _syncSlotZoomScale(int slotIndex) {
    final ctrl = _slotTransformControllers[slotIndex];
    if (ctrl == null) return;
    final scale = ctrl.value.getMaxScaleOnAxis().clamp(1.0, 4.0);
    final wasZoomed = _imageZoomed;
    final nowZoomed = scale > 1.02;
    if (wasZoomed != nowZoomed || (scale - _currentZoomScale).abs() > 0.02) {
      _update(() => _currentZoomScale = scale);
    }
  }

  void _applyZoomScaleToSlot(
    int slotIndex,
    double targetScale, {
    Offset? focalPoint,
    Size? viewportSize,
  }) {
    final clamped = targetScale.clamp(1.0, 4.0);
    final ctrl = _controllerForSlot(slotIndex);
    if (clamped <= 1.01) {
      ctrl.value = Matrix4.identity();
      _update(() => _currentZoomScale = 1.0);
      return;
    }
    final size = viewportSize ?? MediaQuery.sizeOf(context);
    final focal = focalPoint ?? Offset(size.width / 2, size.height / 2);
    final dx = (focal.dx * (1 - clamped)).clamp(
      size.width * (1 - clamped),
      0.0,
    );
    final dy = (focal.dy * (1 - clamped)).clamp(
      size.height * (1 - clamped),
      0.0,
    );
    ctrl.value =
        Matrix4.identity()
          ..translateByDouble(dx, dy, 0.0, 1.0)
          ..scaleByDouble(clamped, clamped, 1.0, 1.0);
    _update(() => _currentZoomScale = clamped);
  }

  void _zoomByStep(double delta) {
    if (!_isPagedMode) return;
    final slots = _buildSpreadSlots(MediaQuery.sizeOf(context).width);
    final activeSlotIndex = _slotIndexForPage(slots, _anchor.pageIndex);
    _applyZoomScaleToSlot(activeSlotIndex, _currentZoomScale + delta);
  }

  void _toggleDoubleTapZoom(int slotIndex, Size slotSize) {
    final nextScale = _imageZoomed ? 1.0 : 2.5;
    _applyZoomScaleToSlot(
      slotIndex,
      nextScale,
      focalPoint: _lastDoubleTapLocalPosition,
      viewportSize: slotSize,
    );
  }

  void _handleCtrlWheelZoom(
    PointerSignalEvent event,
    int slotIndex,
    Size slotSize,
  ) {
    if (event is! PointerScrollEvent) return;
    final hardware = HardwareKeyboard.instance;
    if (!hardware.isControlPressed && !hardware.isMetaPressed) return;
    final delta = event.scrollDelta.dy < 0 ? 0.25 : -0.25;
    _applyZoomScaleToSlot(
      slotIndex,
      _currentZoomScale + delta,
      focalPoint: event.localPosition,
      viewportSize: slotSize,
    );
  }

  void _scrollByPage(int direction, {double viewportFactor = 0.88}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target =
        _scrollController.offset +
        position.viewportDimension * viewportFactor * direction;
    _scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: MotionToken.reduced(context, const Duration(milliseconds: 220)),
      curve: Curves.easeOut,
    );
  }

  /// 构建漫画内容。
  Widget _buildContent({
    required List<_ComicSpreadSlot> slots,
    required int activeSlotIndex,
    required bool isBookmarked,
    required Color stageBg,
  }) {
    if (_totalPages <= 0) {
      return Center(
        child: Text(
          AppLocalizations.of(context).readerNoContent,
          style: TextStyle(color: _settings.onSurfaceVariantColor),
        ),
      );
    }
    if (_readingMode == ComicReadingMode.scroll) {
      return ReaderTapDetector(
        onTap: _handleScrollContentTap,
        child: _buildScrollMode(stageBg),
      );
    }
    return _buildPagedMode(
      slots: slots,
      activeSlotIndex: activeSlotIndex,
      isBookmarked: isBookmarked,
      stageBg: stageBg,
    );
  }

  /// 竖向连续滚动模式。
  Widget _buildScrollMode(Color stageBg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final layout = _resolveLayout(viewport);
        _layoutIndex.updateContentWidth(layout.contentWidth);
        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
            vertical: _displaySettings.pageGap,
          ),
          itemCount: _totalPages,
          itemBuilder: (context, index) {
            return Center(
              child: SizedBox(
                width: layout.contentWidth,
                child: Padding(
                  padding: EdgeInsets.only(bottom: _displaySettings.pageGap),
                  child: ComicPageImage(
                    page: _pages[index],
                    itemId: widget.itemId,
                    surfaceColor: stageBg,
                    layout: ComicPageImageLayout.continuous,
                    onLayout:
                        (pageIndex, height) => _onPageLayout(
                          pageIndex,
                          height + _displaySettings.pageGap,
                        ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Book 3D 翻页与 Swipe 滑动模式：复用 `ReaderPageView(reverse: _isRtl, dragEnabled: !_imageZoomed)`。
  Widget _buildPagedMode({
    required List<_ComicSpreadSlot> slots,
    required int activeSlotIndex,
    required bool isBookmarked,
    required Color stageBg,
  }) {
    final turnMode =
        _readingMode == ComicReadingMode.book
            ? PageTurnMode.cover
            : PageTurnMode.slide;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final layout = _resolveLayout(viewport);
        return ReaderPageView(
          key: ValueKey(
            'comic-page-view-${widget.itemId}-${_modeName(_readingMode)}-'
            '${_displaySettings.dualPage ? 'dual' : 'single'}-${_isRtl ? 'rtl' : 'ltr'}',
          ),
          turnMode: turnMode,
          reverse: _isRtl,
          dragEnabled: !_imageZoomed,
          spread: false,
          surfaceColor: stageBg,
          paperEdgeColor: _controlSettings.paperEdgeColor,
          bookmarked: isBookmarked,
          controller: _pageTurnController,
          contentRevision: Object.hash(
            _displaySettings.dualPage,
            _displaySettings.imageFit,
            _isRtl,
            _settings.themeIndex,
          ),
          state: PagedState(
            chapterId: widget.itemId,
            pageIndex: activeSlotIndex,
            pageCount: slots.length,
            hasMore: false,
          ),
          pageBuilder: (slotIndex) {
            if (slotIndex < 0 || slotIndex >= slots.length) return null;
            return _buildSlotPage(
              slotIndex: slotIndex,
              slot: slots[slotIndex],
              layout: layout,
              slotSize: viewport,
              stageBg: stageBg,
              interactive: true,
            );
          },
          snapshotPageBuilder: (slotIndex) {
            if (slotIndex < 0 || slotIndex >= slots.length) return null;
            return _buildSlotPage(
              slotIndex: slotIndex,
              slot: slots[slotIndex],
              layout: layout,
              slotSize: viewport,
              stageBg: stageBg,
              interactive: false,
            );
          },
          callbacks: _ComicPageTurnCallbacks(
            onPageChangedFn: (newSlotIndex) {
              if (newSlotIndex < 0 || newSlotIndex >= slots.length) return;
              _resetOffscreenSlotTransforms(newSlotIndex);
              _onPageChanged(slots[newSlotIndex].startPageIndex);
            },
            onToggleControlsFn: _toggleControls,
          ),
        );
      },
    );
  }

  /// 构建单页或双页跨页内容（支持 LTR/RTL 拼合顺序、图片适应模式与独立缩放）。
  Widget _buildSlotPage({
    required int slotIndex,
    required _ComicSpreadSlot slot,
    required ComicReaderLayout layout,
    required Size slotSize,
    required Color stageBg,
    required bool interactive,
  }) {
    final indices = slot.pageIndices;
    final orderedIndices =
        indices.length == 2 && _isRtl ? [indices[1], indices[0]] : indices;

    Widget buildFittedImage(int pageIndex) {
      final img = ComicPageImage(
        page: _pages[pageIndex],
        itemId: widget.itemId,
        surfaceColor: stageBg,
        layout: ComicPageImageLayout.paged,
      );
      if (_displaySettings.imageFit == 'fitWidth') {
        return FittedBox(
          fit: BoxFit.fitWidth,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width:
                orderedIndices.length == 2
                    ? slotSize.width / 2
                    : slotSize.width,
            height: slotSize.height,
            child: img,
          ),
        );
      }
      if (_displaySettings.imageFit == 'fitHeight') {
        return FittedBox(
          fit: BoxFit.fitHeight,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width:
                orderedIndices.length == 2
                    ? slotSize.width / 2
                    : slotSize.width,
            height: slotSize.height,
            child: img,
          ),
        );
      }
      return img;
    }

    final Widget composed =
        orderedIndices.length == 1
            ? buildFittedImage(orderedIndices.first)
            : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: buildFittedImage(orderedIndices[0])),
                const SizedBox(width: 2),
                Expanded(child: buildFittedImage(orderedIndices[1])),
              ],
            );

    final padded = Padding(padding: layout.pagedPadding, child: composed);
    if (!interactive) {
      return ColoredBox(color: stageBg, child: padded);
    }

    final controller = _controllerForSlot(slotIndex);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal:
          (event) => _handleCtrlWheelZoom(event, slotIndex, slotSize),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown:
            (details) => _lastDoubleTapLocalPosition = details.localPosition,
        onDoubleTap: () => _toggleDoubleTapZoom(slotIndex, slotSize),
        child: InteractiveViewer(
          transformationController: controller,
          minScale: 1.0,
          maxScale: 4.0,
          panEnabled: _imageZoomed,
          scaleEnabled: true,
          onInteractionUpdate: (_) => _syncSlotZoomScale(slotIndex),
          onInteractionEnd: (_) => _syncSlotZoomScale(slotIndex),
          child: padded,
        ),
      ),
    );
  }
}
