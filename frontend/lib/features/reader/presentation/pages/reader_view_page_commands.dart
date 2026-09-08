part of 'reader_view_page.dart';

extension _ReaderViewPageCommands on _ReaderViewPageState {
  KeyEventResult _handleReaderKeyEvent(
    KeyEvent event,
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final inputFocused =
        focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    final command = const ReaderShortcutResolver().resolve(
      key: event.logicalKey,
      mode:
          _isPageMode
              ? ReaderShortcutMode.textPage
              : ReaderShortcutMode.textScroll,
      shiftPressed: hardware.isShiftPressed,
      controlPressed: hardware.isControlPressed || hardware.isMetaPressed,
      textInputFocused: inputFocused,
      isWeb: kIsWeb,
    );
    if (command == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && !_isRepeatableReaderCommand(command)) {
      return KeyEventResult.handled;
    }
    if (_requiresReaderCommandGate(command) && !_readerCommandGate.accept()) {
      return KeyEventResult.handled;
    }
    _executeReaderCommand(command, detail, content);
    return KeyEventResult.handled;
  }

  bool _isRepeatableReaderCommand(ReaderCommand command) {
    return command == ReaderCommand.scrollForward ||
        command == ReaderCommand.scrollBackward ||
        command == ReaderCommand.nextViewport ||
        command == ReaderCommand.previousViewport;
  }

  bool _requiresReaderCommandGate(ReaderCommand command) {
    return command == ReaderCommand.nextPage ||
        command == ReaderCommand.previousPage ||
        command == ReaderCommand.nextChapter ||
        command == ReaderCommand.previousChapter ||
        command == ReaderCommand.increaseFont ||
        command == ReaderCommand.decreaseFont ||
        command == ReaderCommand.resetTypography;
  }

  void _executeReaderCommand(
    ReaderCommand command,
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) {
    switch (command) {
      case ReaderCommand.closeLayer:
        _closeReaderLayer();
        return;
      case ReaderCommand.toggleContents:
        _toggleReaderPanel(ReaderPanelType.contents);
        return;
      case ReaderCommand.toggleBookmark:
        if (!_bookmarkBusy) {
          unawaited(toggleBookmark(detail, content));
        }
        return;
      case ReaderCommand.openSearch:
        _toggleReaderPanel(ReaderPanelType.search);
        return;
      case ReaderCommand.openAnnotations:
        _toggleReaderPanel(ReaderPanelType.annotations);
        return;
      case ReaderCommand.toggleImmersive:
        _toggleReaderImmersive();
        return;
      case ReaderCommand.toggleFullscreen:
        _toggleReaderFullscreen();
        return;
      case ReaderCommand.showShortcuts:
        _toggleReaderPanel(ReaderPanelType.shortcuts);
        return;
      case ReaderCommand.increaseFont:
        onSettingsChanged(
          _settings.copyWith(
            fontSize: (_settings.fontSize + 1).clamp(14.0, 28.0),
          ),
        );
        return;
      case ReaderCommand.decreaseFont:
        onSettingsChanged(
          _settings.copyWith(
            fontSize: (_settings.fontSize - 1).clamp(14.0, 28.0),
          ),
        );
        return;
      case ReaderCommand.resetTypography:
        onSettingsChanged(
          _settings.copyWith(
            fontSize: AppTypography.titleLarge,
            lineHeight: 1.8,
          ),
        );
        return;
      case ReaderCommand.nextPage:
        _pageTurnController.next();
        return;
      case ReaderCommand.previousPage:
        _pageTurnController.previous();
        return;
      case ReaderCommand.nextViewport:
        unawaited(_scrollReaderViewport(detail, 0.88));
        return;
      case ReaderCommand.previousViewport:
        unawaited(_scrollReaderViewport(detail, -0.88));
        return;
      case ReaderCommand.scrollForward:
        unawaited(_scrollReaderViewport(detail, 0.16));
        return;
      case ReaderCommand.scrollBackward:
        unawaited(_scrollReaderViewport(detail, -0.16));
        return;
      case ReaderCommand.chapterStart:
        _jumpToReaderChapterBoundary(start: true);
        return;
      case ReaderCommand.chapterEnd:
        _jumpToReaderChapterBoundary(start: false);
        return;
      case ReaderCommand.nextChapter:
        tryNavigateChapter(1);
        return;
      case ReaderCommand.previousChapter:
        tryNavigateChapter(-1);
        return;
      case ReaderCommand.toggleReadingMode:
        return;
    }
  }

  void _closeReaderLayer() {
    if (_panelCoordinator.close()) {
      _updateState(() {});
      return;
    }
    if (_showTts) {
      _updateState(() => _showTts = false);
      return;
    }
    if (_showControls) {
      _updateState(() => _showControls = false);
      return;
    }
    if (_settings.immersiveMode) {
      _toggleReaderImmersive();
      return;
    }
    syncProgressSync();
    safePop();
  }

  void _toggleReaderPanel(ReaderPanelType panel) {
    _hideTimer?.cancel();
    _updateState(() {
      _panelCoordinator.toggle(panel);
      _showControls = false;
      _showTts = false;
    });
  }

  void _closeReaderPanel() {
    if (_panelCoordinator.close()) {
      _updateState(() {});
    }
  }

  void _toggleReaderImmersive() {
    final enableImmersive = !_settings.immersiveMode;
    if (enableImmersive) {
      _hideTimer?.cancel();
      _panelCoordinator.close();
      _updateState(() => _showControls = false);
    }
    onSettingsChanged(_settings.copyWith(immersiveMode: enableImmersive));
  }

  void _toggleReaderFullscreen() {
    if (isDesktopPlatform) {
      unawaited(
        ref.read(windowChromeControllerProvider.notifier).toggleFullscreen(),
      );
      return;
    }
    if (!kIsWeb) {
      fs.toggleFullscreen();
    }
  }

  void _navigateReader(ReaderItemDetail detail, {required bool forward}) {
    if (_isPageMode) {
      if (forward) {
        _pageTurnController.next();
      } else {
        _pageTurnController.previous();
      }
      return;
    }
    unawaited(handleSideTap(detail, forward: forward));
  }

  Future<void> _scrollReaderViewport(
    ReaderItemDetail detail,
    double viewportFactor,
  ) async {
    final didScroll = await scrollBy(
      MediaQuery.sizeOf(context).height * viewportFactor,
    );
    if (!didScroll && mounted) {
      tryNavigateChapter(viewportFactor > 0 ? 1 : -1);
    }
  }

  void _jumpToReaderChapterBoundary({required bool start}) {
    if (_isPageMode) {
      final data = _contentLoader?.get(_currentChapterId, _settings);
      final targetOffset =
          start || data == null ? 0 : math.max(0, data.totalChars - 1);
      _pendingRestoreCharOffset = targetOffset;
      _isRestoringProgress = true;
      _updateState(() {
        if (start) {
          _pageModePage = 0;
        }
      });
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    unawaited(
      _scrollController.animateTo(
        start ? 0 : _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _seekBookProgress(double progress) async {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    if (parsedBook == null || parsedBook.chapters.isEmpty) {
      return;
    }
    final counts = parsedBook.chapters
        .map((chapter) => math.max(1, chapter.charCount))
        .toList(growable: false);
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    var target = (progress.clamp(0.0, 1.0) * total).floor();
    var chapterIndex = 0;
    while (chapterIndex < counts.length - 1 && target >= counts[chapterIndex]) {
      target -= counts[chapterIndex];
      chapterIndex++;
    }
    final chapters = _contentLoader?.allChapters ?? const <ReaderChapter>[];
    if (chapterIndex >= chapters.length) {
      return;
    }
    final targetChapter = chapters[chapterIndex];
    final targetOffset = target.clamp(0, counts[chapterIndex]);
    await switchToChapter(
      targetChapter.id,
      intent: ReaderChapterNavigationIntent.offset(
        targetOffset,
        offerReturn: true,
      ),
    );
  }

  void _openReaderSearchResult(int offset) {
    _closeReaderPanel();
    _pendingRestoreCharOffset = offset;
    _isRestoringProgress = true;
    if (_isPageMode) {
      repaginateCurrentChapter(restoreCharOffset: offset);
    } else {
      restoreScrollPositionFromOffset(offset);
    }
    _updateState(() {});
  }

  List<Widget> _buildReaderPanels(
    ReaderItemDetail detail,
    ReaderChapterContent content,
    ReaderControlLayout layout,
  ) {
    final active = _panelCoordinator.active;
    if (active == null) {
      return const [];
    }
    final l10n = AppLocalizations.of(context);
    final title = switch (active) {
      ReaderPanelType.contents => l10n.readerTableOfContents,
      ReaderPanelType.settings => l10n.readerSettingsTitle,
      ReaderPanelType.search => l10n.readerSearchCurrentChapter,
      ReaderPanelType.annotations => l10n.readerAnnotations,
      ReaderPanelType.shortcuts => l10n.readerShortcutsTitle,
    };
    final child = switch (active) {
      ReaderPanelType.contents => _buildChapterPanel(detail),
      ReaderPanelType.settings => ReaderViewSettingsPanel(
        settings: _settings,
        onSettingsChanged: onSettingsChanged,
        embedded: true,
      ),
      ReaderPanelType.search => ReaderFindPanel(
        plainText: getPlainText(content.content),
        settings: _settings,
        onSelect: _openReaderSearchResult,
      ),
      ReaderPanelType.annotations =>
        _annotationHandler?.buildPanel(context) ?? const SizedBox.shrink(),
      ReaderPanelType.shortcuts => ReaderShortcutPanel(
        settings: _settings,
        isComic: false,
      ),
    };
    return [
      Positioned.fill(
        child: ReaderAdaptivePanelOverlay(
          title: title,
          settings: _settings,
          layout: layout,
          onClose: _closeReaderPanel,
          child: child,
        ),
      ),
    ];
  }
}
