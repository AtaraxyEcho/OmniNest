part of 'comic_reader_view.dart';

/// 漫画阅读器的模式切换、双页拼合、独立缩放、旋转、书签、跳转与内容构建。
extension _ComicReaderViewSections on ComicReaderViewState {
  /// 预加载当前页前后的图片。
  void _preloadAdjacent() {
    if (_totalPages <= 0) {
      return;
    }
    unawaited(
      preloadComicAdjacentPages(
        ref,
        widget.itemId,
        _pages,
        _anchor.pageIndex,
        before: 2,
        after: 4,
      ),
    );
  }

  int _quarterTurnsForPage(ComicPage page) =>
      (_pageQuarterTurns[page.id] ?? 0) % 4;

  /// 客户端首帧解码实测像素尺寸回填：无元数据宽图在回填后自动重算双页槽位，
  /// 并保持当前 `_anchor.pageIndex` 不跳页。
  void _onPageIntrinsicSizeResolved(int pageIndex, Size size) {
    if (!mounted || pageIndex < 0 || pageIndex >= _totalPages) return;
    if (size.width <= 0 || size.height <= 0) return;
    final prev = _resolvedPageSizes[pageIndex];
    if (prev != null &&
        (prev.width - size.width).abs() < 1.0 &&
        (prev.height - size.height).abs() < 1.0) {
      return;
    }
    final page = _pages[pageIndex];
    final wasWide = _isWideSpreadPage(page);
    _resolvedPageSizes[pageIndex] = size;
    final nowWide = _isWideSpreadPage(page);
    if (wasWide != nowWide) {
      _update(() {});
    }
  }

  bool _isWideSpreadPage(ComicPage page) {
    final resolved = _resolvedPageSizes[page.pageIndex];
    final rawW = resolved?.width ?? page.width?.toDouble();
    final rawH = resolved?.height ?? page.height?.toDouble();
    if (rawW == null || rawH == null || rawW <= 0 || rawH <= 0) {
      return false;
    }
    final oddTurn = _quarterTurnsForPage(page).isOdd;
    final w = oddTurn ? rawH : rawW;
    final h = oddTurn ? rawW : rawH;
    return w > h * 1.15;
  }

  /// 旋转当前主阅读页 90°（按 pageId 记忆 0/1/2/3），并刷新卷页缓存。
  void _rotateCurrentPage([int delta = 1]) {
    if (_totalPages <= 0 || _anchor.pageIndex >= _pages.length) return;
    final page = _pages[_anchor.pageIndex];
    final nextTurns = ((_pageQuarterTurns[page.id] ?? 0) + delta) % 4;
    _resetCurrentSlotZoom();
    _update(() {
      if (nextTurns == 0) {
        _pageQuarterTurns.remove(page.id);
      } else {
        _pageQuarterTurns[page.id] = nextTurns;
      }
      _rotationRevision++;
    });
  }

  /// 离屏抓图前确保目标页图片字节已载入内存缓存，
  /// 并使用与 `ComicPageImage` 完全一致的 `ResizeImage` 缓存键精准预热。
  Future<bool> _prepareComicPageForSnapshot(
    int pageIndex, {
    required double targetLogicalWidth,
  }) async {
    if (pageIndex < 0 || pageIndex >= _totalPages) {
      return false;
    }
    final loader = ref.read(comicImageLoaderProvider);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth =
        (targetLogicalWidth * dpr).round().clamp(1, 2560).toInt();
    final page = _pages[pageIndex];
    final bytes =
        loader.getCachedBytesSync(
          widget.itemId,
          page.id,
          sourcePath: page.sourcePath,
        ) ??
        await loader
            .getImage(widget.itemId, page.sourcePath, pageId: page.id)
            .catchError((_) => null);
    if (!mounted || bytes == null || bytes.isEmpty) {
      return false;
    }
    try {
      await precacheImage(
        ComicPageImage.resolveProvider(bytes, cacheWidth),
        context,
      );
    } on Object {
      // 解码失败仍允许降级由 ComicPageImage 错误态兜底。
    }
    return mounted;
  }

  /// 双页虚拟叶模式下的离屏抓图预热（`leafIndex = slotIndex * 2 + (isSecondLeaf ? 1 : 0)`）。
  Future<bool> _prepareComicSpreadLeafSnapshot(
    int leafIndex, {
    required List<_ComicSpreadSlot> slots,
    required double bookLogicalWidth,
  }) async {
    if (leafIndex < 0) return false;
    final slotIndex = leafIndex ~/ 2;
    if (slotIndex < 0 || slotIndex >= slots.length) {
      return false;
    }
    final isSecondLeaf = leafIndex.isOdd;
    final slot = slots[slotIndex];
    if (slot.pageIndices.isEmpty) return false;

    if (slot.isWideSpread) {
      return _prepareComicPageForSnapshot(
        slot.pageIndices.first,
        targetLogicalWidth: bookLogicalWidth,
      );
    }
    if (slot.pageIndices.length == 2) {
      final pageIndex =
          isSecondLeaf ? slot.pageIndices[1] : slot.pageIndices[0];
      return _prepareComicPageForSnapshot(
        pageIndex,
        targetLogicalWidth: bookLogicalWidth / 2.0,
      );
    }
    // 封面槽或奇数落单槽：对侧为纯封里纸面，无需等待图片下载解码。
    if (isSecondLeaf) {
      return true;
    }
    return _prepareComicPageForSnapshot(
      slot.pageIndices.first,
      targetLogicalWidth: bookLogicalWidth / 2.0,
    );
  }

  /// 单页 Book 模式下的离屏抓图预热。
  Future<bool> _prepareComicSingleSlotSnapshot(
    int slotIndex, {
    required List<_ComicSpreadSlot> slots,
    required double slotLogicalWidth,
  }) async {
    if (slotIndex < 0 || slotIndex >= slots.length) {
      return false;
    }
    final indices = slots[slotIndex].pageIndices;
    if (indices.isEmpty) return false;
    return _prepareComicPageForSnapshot(
      indices.first,
      targetLogicalWidth: slotLogicalWidth,
    );
  }

  BoxFit _resolveImageBoxFit() {
    return switch (_displaySettings.imageFit) {
      'fitWidth' => BoxFit.fitWidth,
      'fitHeight' => BoxFit.fitHeight,
      _ => BoxFit.contain,
    };
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

  /// 计算当前视口下的单/双页槽位列表（Book 与 Swipe 统一复用）：
  /// - 首页封面单页独占（标记 `isCover: true`）；
  /// - 跨页宽图（width > height * 1.15，含客户端实测尺寸回填）独占整屏（标记 `isWideSpread: true`）；
  /// - 其余页按顺序两两配对。
  List<_ComicSpreadSlot> _buildSpreadSlots(double viewportWidth) {
    if (_totalPages <= 0) return const [];
    final useDual = _displaySettings.resolveDualPage(
      viewportWidth: viewportWidth,
      mode: _modeName(_readingMode),
    );
    if (!useDual) {
      return [
        for (var i = 0; i < _totalPages; i++)
          _ComicSpreadSlot(
            [i],
            isCover: i == 0,
            isWideSpread: _isWideSpreadPage(_pages[i]),
          ),
      ];
    }

    final slots = <_ComicSpreadSlot>[];
    var i = 0;
    while (i < _totalPages) {
      final current = _pages[i];
      final currentWide = _isWideSpreadPage(current);
      if (i == 0) {
        slots.add(
          _ComicSpreadSlot([i], isCover: true, isWideSpread: currentWide),
        );
        i++;
        continue;
      }
      if (currentWide) {
        slots.add(_ComicSpreadSlot([i], isWideSpread: true));
        i++;
        continue;
      }
      if (i + 1 < _totalPages && !_isWideSpreadPage(_pages[i + 1])) {
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
      } else {
        _preloadAdjacent();
      }
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

  // ── 漫画书签（双页模式遍历 activeSlot.pageIndices）──

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

  ReaderBookmark? _findBookmarkForSlot(
    List<ReaderBookmark> bookmarks,
    _ComicSpreadSlot? slot,
  ) {
    if (slot == null || slot.pageIndices.isEmpty) {
      return _findBookmarkForPage(bookmarks, _anchor.pageIndex);
    }
    for (final pageIndex in slot.pageIndices) {
      final found = _findBookmarkForPage(bookmarks, pageIndex);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  Future<void> _toggleCurrentPageBookmark(
    List<ReaderBookmark> bookmarks, [
    _ComicSpreadSlot? activeSlot,
  ]) async {
    if (_totalPages <= 0) return;
    final dataManager = ref.read(readerDataManagerProvider);
    final existing = _findBookmarkForSlot(bookmarks, activeSlot);
    if (existing != null) {
      await dataManager.deleteBookmark(existing.id);
    } else {
      final targetPageIndex = activeSlot?.startPageIndex ?? _anchor.pageIndex;
      final page = _pages[targetPageIndex];
      final progress = ((targetPageIndex + 1) / _totalPages).clamp(0.0, 1.0);
      await dataManager.createBookmark(
        itemId: widget.itemId,
        charOffset: targetPageIndex,
        progressPercent: progress,
        chapterId: page.catalogNodeId,
        note: 'P.${targetPageIndex + 1}',
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
    if (!_acceptCommandGate(command)) {
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

  bool _acceptCommandGate(ReaderCommand command) {
    if (command == ReaderCommand.toggleReadingMode) {
      return _commandGate.accept();
    }
    if (command == ReaderCommand.nextPage ||
        command == ReaderCommand.previousPage) {
      if (_readingMode == ComicReadingMode.book) {
        return _bookPageCommandGate.accept();
      }
      return _commandGate.accept();
    }
    return true;
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
        final slots = _buildSpreadSlots(MediaQuery.sizeOf(context).width);
        final activeSlotIndex = _slotIndexForPage(slots, _anchor.pageIndex);
        final activeSlot =
            (activeSlotIndex >= 0 && activeSlotIndex < slots.length)
                ? slots[activeSlotIndex]
                : null;
        unawaited(_toggleCurrentPageBookmark(bms, activeSlot));
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

  // ── 每槽位独立缩放控制器（Book 与 Swipe 均支持，放大 > 1.02 时自动锁翻页拖拽） ──

  TransformationController _controllerForSlot(int slotIndex) {
    return _slotTransformControllers.putIfAbsent(
      slotIndex,
      TransformationController.new,
    );
  }

  void _pruneOffscreenSlotTransforms(int activeSlotIndex) {
    final toRemove = <int>[];
    for (final key in _slotTransformControllers.keys) {
      if ((key - activeSlotIndex).abs() > 4) {
        toRemove.add(key);
      }
    }
    for (final key in toRemove) {
      _slotTransformControllers.remove(key)?.dispose();
    }
  }

  void _resetOffscreenSlotTransforms(int activeSlotIndex) {
    _pruneOffscreenSlotTransforms(activeSlotIndex);
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
    Size slotSize, {
    Offset? focalPoint,
  }) {
    if (event is! PointerScrollEvent) return;
    final hardware = HardwareKeyboard.instance;
    if (!hardware.isControlPressed && !hardware.isMetaPressed) return;
    final delta = event.scrollDelta.dy < 0 ? 0.25 : -0.25;
    _applyZoomScaleToSlot(
      slotIndex,
      _currentZoomScale + delta,
      focalPoint: focalPoint ?? event.localPosition,
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
}
