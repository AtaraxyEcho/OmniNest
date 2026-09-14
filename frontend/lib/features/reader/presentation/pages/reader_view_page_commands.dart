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
    // 键盘滚动进入 Keyboard 事务（方案 §32）：无指针事件也保持事务身份。
    final didScroll = await scrollBy(
      MediaQuery.sizeOf(context).height * viewportFactor,
      kind: ReaderTransactionKind.keyboard,
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
      // 不在此写 pageModePage=0：跨章流中 0 可能是窗口更前一章。
      // 由 pendingRestore → findPageByCharOffset → startIndexOf 换算。
      _updateState(() {});
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    // 章首/章尾是窗口坐标（前有前缀章），不能用 0/maxScrollExtent：
    // 0 是上一章顶部，max 是下一章尾部。
    final prefix = continuousScrollController.prefixHeightOf(_currentChapterId);
    final entry = continuousScrollController.entryFor(_currentChapterId);
    final max = _scrollController.position.maxScrollExtent;
    final viewport = _scrollController.position.viewportDimension;
    final chapterStart = prefix.clamp(0.0, max);
    final double target;
    if (start) {
      target = chapterStart;
    } else {
      final extent =
          entry != null
              ? continuousScrollController.effectiveExtentOf(entry)
              : 0.0;
      target = (prefix + extent - viewport).clamp(chapterStart, max);
    }
    // 章节边界导航进入 Navigation 事务（方案 §33/§117）：不伪装成用户滚动。
    unawaited(
      animateToOffsetProgrammatic(
        target,
        kind: ReaderTransactionKind.navigation,
      ),
    );
  }

  Future<void> _seekBookProgress(double progress) async {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    if (parsedBook == null || parsedBook.chapters.isEmpty) {
      return;
    }
    final chapters = _contentLoader?.allChapters ?? const <ReaderChapter>[];

    // 连续模式：滑条显示的是视觉全书进度，先按视觉表换算目标章与
    // charOffset；换算结果仍走逻辑位置跳转（jumpTo / switchToChapter）。
    if (!_isPageMode) {
      final visualTarget = resolveVisualSeekTarget(progress);
      if (visualTarget != null) {
        final targetChapterId = visualTarget.$1;
        final targetOffset = visualTarget.$2;
        final currentIdx = chapters.indexWhere(
          (c) => c.id == _currentChapterId,
        );
        final targetIdx = chapters.indexWhere((c) => c.id == targetChapterId);
        final inWindow =
            currentIdx >= 0 &&
            targetIdx >= 0 &&
            (targetIdx - currentIdx).abs() <= 1 &&
            _contentLoader!.getByChapterId(targetChapterId) != null;
        if (inWindow) {
          await _seekWithinContinuousWindow(targetChapterId, targetOffset);
          return;
        }
        await switchToChapter(
          targetChapterId,
          intent: ReaderChapterNavigationIntent.offset(
            targetOffset,
            offerReturn: true,
          ),
        );
        return;
      }
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
    if (chapterIndex >= chapters.length) {
      return;
    }
    final targetChapter = chapters[chapterIndex];
    final targetOffset = target.clamp(0, counts[chapterIndex]);

    // 连续滚动：目标在窗口邻域内时直接 jumpTo，避免整树切换。
    if (!_isPageMode && _contentLoader != null) {
      final currentIdx = chapters.indexWhere((c) => c.id == _currentChapterId);
      final targetIdx = chapterIndex;
      final inWindow =
          currentIdx >= 0 &&
          (targetIdx - currentIdx).abs() <= 1 &&
          _contentLoader!.getByChapterId(targetChapter.id) != null;
      if (inWindow) {
        await _seekWithinContinuousWindow(targetChapter.id, targetOffset);
        return;
      }
    }

    await switchToChapter(
      targetChapter.id,
      intent: ReaderChapterNavigationIntent.offset(
        targetOffset,
        offerReturn: true,
      ),
    );
  }

  /// 窗口内章节：按 charOffset 换算 contentY 后 jumpTo。
  Future<void> _seekWithinContinuousWindow(
    String chapterId,
    int charOffset,
  ) async {
    final loader = _contentLoader;
    if (loader == null) {
      return;
    }
    final data = loader.getByChapterId(chapterId);
    if (data == null) {
      return;
    }
    final clamped = charOffset.clamp(0, data.totalChars);
    _isRestoringProgress = true;
    _restoreTargetCharOffset = clamped;
    _restoreSilenceUntil = DateTime.now().add(
      const Duration(milliseconds: ReaderViewPageMixin.restoreSilenceMs),
    );
    if (chapterId != _currentChapterId) {
      adoptContinuousAnchorChapter(chapterId);
    }
    final textScale = FontScaleScope.systemScalerOf(context).scale(1);
    final intraY = loader.charOffsetToPixelOffset(
      chapterId,
      clamped,
      pageWidth: computePageWidth(),
      settings: _settings,
      textScale: textScale,
    );
    _positionTracker.setCharOffset(clamped, chapterId);
    final chapterData = loader.getByChapterId(chapterId);
    final totalChars = chapterData?.totalChars ?? 0;
    final progress =
        totalChars > 0 ? (clamped / totalChars).clamp(0.0, 1.0) : 0.0;
    scrollProgress = progress;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 窗口已按新锚点重建后再取 prefix；章体起点 = 前缀 + 章头 chrome。
      final windowY =
          continuousScrollController.prefixHeightOf(chapterId) +
          ReaderContinuousScrollController.chapterHeaderExtent +
          intraY;
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        final target = (windowY - viewportAnchorY).clamp(0.0, max);
        // 视觉 seek 进入 VisualSeek 事务（方案 §33/§117）。
        jumpToOffsetProgrammatic(
          target,
          kind: ReaderTransactionKind.visualSeek,
        );
      }
      _isRestoringProgress = false;
      scheduleLocalProgressSave(
        chapterProgress: progress,
        mode: 'scroll',
        charOffset: clamped,
      );
      _updateState(() {});
    });
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

  /// 构建搜索面板：连续滚动时检索窗口内多章，翻页仍限当前章。
  Widget _buildFindPanel(ReaderChapterContent content) {
    final fromBlocks = currentChapterPlainText();
    final fallbackText =
        fromBlocks.isNotEmpty ? fromBlocks : getPlainText(content.content);

    if (_isPageMode || _contentLoader == null) {
      return ReaderFindPanel(
        plainText: fallbackText,
        settings: _settings,
        onSelect: _openReaderSearchResult,
      );
    }

    final index = _buildWindowSearchIndex();
    return ReaderFindPanel(
      plainText: index.combinedText,
      settings: _settings,
      chapterTitleOf: index.titleOf,
      onSelect: (globalOffset) {
        final hit = index.resolve(globalOffset);
        if (hit == null) {
          _openReaderSearchResult(globalOffset);
          return;
        }
        _openWindowSearchResult(hit);
      },
    );
  }

  ReaderWindowSearchIndex _buildWindowSearchIndex() {
    final loader = _contentLoader!;
    final chapters = <WindowSearchChapter>[];
    for (final entry in continuousScrollController.entries) {
      final data = loader.getByChapterId(entry.chapterId);
      if (data == null || data.blocks.isEmpty) {
        continue;
      }
      chapters.add(
        WindowSearchChapter.fromBlocks(
          chapterId: entry.chapterId,
          title:
              entry.title.isNotEmpty
                  ? entry.title
                  : _chapterTitleById(entry.chapterId),
          blocks: data.blocks,
        ),
      );
    }
    if (chapters.isEmpty) {
      final text = currentChapterPlainText();
      chapters.add(
        WindowSearchChapter(
          chapterId: _currentChapterId,
          title: _chapterTitleById(_currentChapterId),
          plainText: text,
        ),
      );
    }
    return ReaderWindowSearchIndex(chapters);
  }

  String _chapterTitleById(String chapterId) {
    final chapters = _contentLoader?.allChapters ?? const [];
    for (final c in chapters) {
      if (c.id == chapterId) {
        return c.title;
      }
    }
    return '';
  }

  void _openWindowSearchResult(WindowSearchHit hit) {
    _closeReaderPanel();
    if (_isPageMode) {
      _openReaderSearchResult(hit.localOffset);
      return;
    }
    unawaited(_seekWithinContinuousWindow(hit.chapterId, hit.localOffset));
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
      ReaderPanelType.search => _buildFindPanel(content),
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
