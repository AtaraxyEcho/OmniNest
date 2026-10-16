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
        unawaited(_scrollReaderViewport(0.88));
        return;
      case ReaderCommand.previousViewport:
        unawaited(_scrollReaderViewport(-0.88));
        return;
      case ReaderCommand.scrollForward:
        unawaited(_scrollReaderViewport(0.16));
        return;
      case ReaderCommand.scrollBackward:
        unawaited(_scrollReaderViewport(-0.16));
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

  Future<void> _scrollReaderViewport(double viewportFactor) async {
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

  /// 底栏进度条拖拽：按全书比例定位到目标章与章内比例。
  ///
  /// 口径见 [seekTargetFromBookProgress]：跨章只带比例，同章按当章 painted 字符数
  /// 换算成块字符偏移。
  Future<void> _seekBookProgress(double progress) async {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    if (parsedBook == null || parsedBook.chapters.isEmpty) {
      return;
    }
    final target = seekTargetFromBookProgress(
      manifestCharCounts: parsedBook.chapters
          .map((chapter) => chapter.charCount)
          .toList(growable: false),
      progress: progress,
    );
    final chapters = _contentLoader?.allChapters ?? const <ReaderChapter>[];
    if (target.chapterIndex >= chapters.length) {
      return;
    }
    final targetChapter = chapters[target.chapterIndex];
    final chapterData = _contentLoader?.get(targetChapter.id, _settings);
    if (targetChapter.id == _currentChapterId && chapterData != null) {
      _seekWithinChapter(
        (target.chapterRatio * chapterData.totalChars).round(),
      );
      return;
    }
    await switchToChapter(
      targetChapter.id,
      intent: ReaderChapterNavigationIntent.proportion(
        target.chapterRatio,
        offerReturn: true,
      ),
    );
  }

  /// 同章跳转落位并按目标位置记账。
  ///
  /// 恢复静默窗口会丢弃这一段的滚动读数，用户主动拖到的位置若只等滚动回调写入，
  /// 进度显示与落盘都停在拖拽之前。
  void _seekWithinChapter(int charOffset) {
    _openReaderSearchResult(charOffset);
    _positionTracker.setCharOffset(charOffset, _currentChapterId);
    refreshBookProgressNow();
    final snapshot = buildProgressSnapshot();
    if (snapshot == null) {
      return;
    }
    scheduleLocalProgressSave(
      chapterProgress: snapshot.chapterProgress,
      charOffset: snapshot.charOffset,
      mode: snapshot.mode,
    );
    unawaited(
      syncProgressAsync(
        progressOverride: snapshot.chapterProgress,
        chapterId: snapshot.chapterId,
        charOffset: snapshot.charOffset,
        generation: ++syncProgressGeneration,
        force: true,
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

  /// 批注卡片点按：跳到批注所在章节与章内偏移。
  ///
  /// 同章复用章内搜索命中的落位通道；跨章带偏移意图切章，内容由
  /// [ReaderChapterNavigationIntent] 在加载完成后落位。
  void onAnnotationSelected(String? chapterId, int startOffset) {
    _closeReaderPanel();
    if (chapterId == null || chapterId == _currentChapterId) {
      _openReaderSearchResult(startOffset);
      return;
    }
    unawaited(
      switchToChapter(
        chapterId,
        intent: ReaderChapterNavigationIntent.offset(
          startOffset,
          offerReturn: true,
        ),
      ),
    );
  }

  /// 章内搜索面板。
  ///
  /// 检索源换成块模型文本，而不是 `stripHtml(章节 HTML)`：后者是第三套下标域——HTML 标签
  /// 换出的空格在它里面占字符、在块字符域里不占，行首缩进与 TXT 掩码空白反过来在它里面被
  /// 折叠掉。命中下标直接当 `charOffset` 用，长章节能偏出几段。
  /// 章节刚被换出缓存、还没有块时退回原串，下标语义与改动前一致。
  Widget _buildSearchPanel(ReaderChapterContent content) {
    final corpus =
        _contentLoader?.get(_currentChapterId, _settings)?.searchCorpus;
    return ReaderFindPanel(
      plainText: corpus?.plainText ?? getPlainText(content.content),
      settings: _settings,
      onSelect:
          corpus == null
              ? _openReaderSearchResult
              : (plainIndex) =>
                  _openReaderSearchResult(corpus.toCharOffset(plainIndex)),
    );
  }

  List<Widget> _buildReaderPanels(
    ReaderItemDetail detail,
    ReaderChapterContent content,
    ReaderControlLayout layout, {
    bool sampleChrome = false,
  }) {
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
        mobile: sampleChrome,
      ),
      ReaderPanelType.search => _buildSearchPanel(content),
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
          eyebrow: detail.item.title,
          onClose: _closeReaderPanel,
          child: child,
        ),
      ),
    ];
  }
}
