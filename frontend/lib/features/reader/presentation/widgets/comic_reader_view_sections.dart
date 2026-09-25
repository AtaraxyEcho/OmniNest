part of 'comic_reader_view.dart';

/// 漫画阅读器的模式切换、跳转、命令处理与内容构建。
extension _ComicReaderViewSections on _ComicReaderViewState {
  /// 预加载当前页前后的图片。
  void _preloadAdjacent() {
    if (_totalPages <= 0) {
      return;
    }
    final loader = ref.read(comicImageLoaderProvider);
    final start = (_anchor.pageIndex - 2).clamp(0, _totalPages - 1).toInt();
    final end = (_anchor.pageIndex + 3).clamp(0, _totalPages - 1).toInt();
    final pagesToLoad = <ComicPage>[];
    for (var i = start; i <= end; i++) {
      pagesToLoad.add(_pages[i]);
    }
    unawaited(loader.preloadImages(widget.itemId, pagesToLoad));
  }

  ComicReadingMode _modeFromName(String mode) {
    return mode == 'page' ? ComicReadingMode.page : ComicReadingMode.scroll;
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

  /// 切换阅读模式（翻页与连续滚动），保持当前阅读锚点。
  void _switchReadingMode() {
    final nextMode =
        _readingMode == ComicReadingMode.page
            ? ComicReadingMode.scroll
            : ComicReadingMode.page;
    _applyDisplaySettings(
      _displaySettings.copyWith(
        readingMode: nextMode == ComicReadingMode.page ? 'page' : 'scroll',
      ),
    );
  }

  void _applyDisplaySettings(ComicReaderDisplaySettings settings) {
    final previousMode = _readingMode;
    final nextMode = _modeFromName(settings.readingMode);
    final frozenAnchor = _anchor;

    _update(() {
      _displaySettings = settings;
      _readingMode = nextMode;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _layoutIndex.updateContentWidth(
        _resolveLayout(MediaQuery.sizeOf(context)).contentWidth,
      );
      if (previousMode == ComicReadingMode.page &&
          nextMode == ComicReadingMode.scroll) {
        _startScrollRestore(frozenAnchor);
      } else if (previousMode == ComicReadingMode.scroll &&
          nextMode == ComicReadingMode.page) {
        _pageController.jumpToPage(frozenAnchor.pageIndex);
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
    await ref.read(readerPreferencesProvider.notifier).save({
      ...current,
      ...settings.toPreferences(),
    });
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
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls) {
          _update(() => _showControls = false);
        }
      });
    }
  }

  void _togglePanel(ReaderPanelType panel) {
    _hideControlsTimer?.cancel();
    _update(() {
      _panelCoordinator.toggle(panel);
      _showControls = false;
    });
  }

  void _closePanel() {
    if (_panelCoordinator.close()) {
      _update(() {});
    }
  }

  /// 跳转到指定目录节点的起始页。
  void _jumpToCatalogNode(ComicCatalogNode node) {
    final targetIndex = _pages.indexWhere((p) => p.catalogNodeId == node.id);
    if (targetIndex < 0) {
      return;
    }
    _jumpToPage(targetIndex);
  }

  void _jumpToPage(int index) {
    if (_totalPages <= 0) {
      return;
    }
    final targetIndex = index.clamp(0, _totalPages - 1).toInt();
    if (targetIndex == _anchor.pageIndex) {
      return;
    }

    _resetImageTransform();
    final page = _pages[targetIndex];
    _update(() {
      _anchor = ComicAnchor(
        pageId: page.id,
        pageIndex: targetIndex,
        pageFingerprint: page.fingerprint,
        sourceId: page.sourceId,
        sourcePageIndex: page.sourcePageIndex,
        catalogKey: page.catalogKey,
        manifestVersion: _manifest.manifestVersion,
      );
    });

    if (_readingMode == ComicReadingMode.page) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (_scrollController.hasClients) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final targetOffset = _layoutIndex.scrollTo(
        targetIndex,
        0.0,
        viewportHeight,
      );
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, max),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    _saveProgress();
  }

  void _handleContentTap(Offset position) {
    if (_imageZoomed) {
      _toggleControls();
      return;
    }
    if (_readingMode != ComicReadingMode.page || _totalPages <= 0) {
      _toggleControls();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final x = position.dx;
    if (x < width * 0.32) {
      _goToRelativePage(_isRtl ? 1 : -1);
    } else if (x > width * 0.68) {
      _goToRelativePage(_isRtl ? -1 : 1);
    } else {
      _toggleControls();
    }
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
          _readingMode == ComicReadingMode.page
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
      case ReaderCommand.toggleImmersive:
        _toggleControls();
        return;
      case ReaderCommand.toggleFullscreen:
        _toggleFullscreen();
        return;
      case ReaderCommand.showShortcuts:
        _togglePanel(ReaderPanelType.shortcuts);
        return;
      case ReaderCommand.nextPage:
        _goToRelativePage(1);
        return;
      case ReaderCommand.previousPage:
        _goToRelativePage(-1);
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
      case ReaderCommand.toggleBookmark:
      case ReaderCommand.openSearch:
      case ReaderCommand.openAnnotations:
      case ReaderCommand.increaseFont:
      case ReaderCommand.decreaseFont:
      case ReaderCommand.resetTypography:
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onBack();
      }
    });
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

  void _resetImageTransform() {
    _transformationController.value = Matrix4.identity();
    _imageZoomed = false;
  }

  void _updateImageZoomState() {
    _imageZoomed = _transformationController.value.getMaxScaleOnAxis() > 1.01;
  }

  void _goToRelativePage(int delta) {
    _jumpToPage(_anchor.pageIndex + delta);
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// 构建漫画内容。
  Widget _buildContent() {
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
        onTap: _handleContentTap,
        child: _buildScrollMode(),
      );
    }
    return ReaderTapDetector(onTap: _handleContentTap, child: _buildPageMode());
  }

  /// 竖向连续滚动模式。
  Widget _buildScrollMode() {
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
                    surfaceColor: Colors.black,
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

  /// 单页翻页模式。
  Widget _buildPageMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _resolveLayout(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return PageView.builder(
          controller: _pageController,
          itemCount: _totalPages,
          reverse: _isRtl,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            return Padding(
              padding: layout.pagedPadding,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 4.0,
                onInteractionUpdate: (_) => _updateImageZoomState(),
                onInteractionEnd: (_) => _updateImageZoomState(),
                child: ComicPageImage(
                  page: _pages[index],
                  itemId: widget.itemId,
                  surfaceColor: Colors.black,
                  layout: ComicPageImageLayout.paged,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
