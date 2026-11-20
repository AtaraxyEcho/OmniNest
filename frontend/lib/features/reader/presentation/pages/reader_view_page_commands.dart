part of 'reader_view_page.dart';

/// 滚动模式跳章首/章尾的滑行时长；减动效下改走 jumpTo。
const Duration _chapterBoundaryScrollDuration = Duration(milliseconds: 220);

extension _ReaderViewPageCommands on _ReaderViewPageState {
  KeyEventResult _handleReaderKeyEvent(
    KeyEvent event,
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 选区键盘动作优先于页面命令：正文里有有效选区时，1–5 与 N 归选区工具栏。
    final selectionActions = _selectionKeyActions;
    if (runReaderSelectionKeyShortcut(event.logicalKey, selectionActions)) {
      return KeyEventResult.handled;
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
      selectionActionsActive: selectionActions != null,
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
        // 手机浏览器与不支持翻页的正文保持静默，与设置面板隐藏分页开关的口径一致。
        if (!supportsPageMode) {
          return;
        }
        onSettingsChanged(_settings.withReadingModeToggled());
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
    handleReaderExit();
  }

  void _toggleReaderPanel(ReaderPanelType panel) {
    _hideTimer?.cancel();
    final viewport = MediaQuery.sizeOf(context);
    final isDesktopShell =
        !shouldUseResponsiveMobileShell(
          mobilePlatform: isMobilePlatform,
          width: viewport.width,
        );
    _updateState(() {
      _panelCoordinator.toggle(panel);
      if (_panelCoordinator.active != ReaderPanelType.search) {
        _activeSearchQuery = '';
      }
      _showControls = isDesktopShell ? true : false;
      _showTts = false;
    });
  }

  void _closeReaderPanel() {
    if (_panelCoordinator.close()) {
      _updateState(() => _activeSearchQuery = '');
    }
  }

  void _onSearchQueryChanged(String query) {
    final trimmed = query.trim();
    if (trimmed == _activeSearchQuery) return;
    _updateState(() => _activeSearchQuery = trimmed);
  }

  void _toggleReaderImmersive() {
    final enableImmersive = !_settings.immersiveMode;
    if (enableImmersive) {
      _hideTimer?.cancel();
      _panelCoordinator.close();
      _updateState(() {
        _showControls = false;
        _activeSearchQuery = '';
      });
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
    final target = start ? 0.0 : _scrollController.position.maxScrollExtent;
    // 减动效下不做全书高度的滑行：位移本身是导航目的，动画只是过程。
    if (MotionToken.prefersReduced(context)) {
      _scrollController.jumpTo(target);
      return;
    }
    unawaited(
      _scrollController.animateTo(
        target,
        duration: _chapterBoundaryScrollDuration,
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

  /// 全书搜索面板。
  ///
  /// 检索源使用块模型文本，而不是 `stripHtml(章节 HTML)`：后者是第三套下标域——HTML 标签
  /// 换出的空格在它里面占字符、在块字符域里不占，行首缩进与 TXT 掩码空白反过来在它里面被
  /// 折叠掉。命中下标直接当 `charOffset` 用，长章节能偏出几段。
  Widget _buildSearchPanel(ReaderChapterContent content) {
    final corpus =
        _contentLoader?.get(_currentChapterId, _settings)?.searchCorpus;
    return ReaderFindPanel(
      plainText: corpus?.plainText ?? getPlainText(content.content),
      settings: _settings,
      searchBook: _searchBook,
      onQueryChanged: _onSearchQueryChanged,
      onSelectBookMatch: _openReaderBookSearchResult,
      onSelect:
          corpus == null
              ? _openReaderSearchResult
              : (plainIndex) =>
                  _openReaderSearchResult(corpus.toCharOffset(plainIndex)),
    );
  }

  Future<ReaderBookSearchResponse> _searchBook(
    String query,
    bool Function() isCancelled,
  ) async {
    final loader = _contentLoader;
    if (loader == null) {
      return (
        matches: const <ReaderBookSearchMatch>[],
        truncated: false,
        incomplete: true,
      );
    }
    final book = await ref.read(parsedBookProvider(widget.itemId).future);
    if (isCancelled()) {
      return (
        matches: const <ReaderBookSearchMatch>[],
        truncated: false,
        incomplete: false,
      );
    }
    final chapters = loader.allChapters;
    final results = <ReaderBookSearchMatch>[];
    var incomplete = false;
    var truncated = false;
    for (var index = 0; index < chapters.length; index++) {
      if (isCancelled()) break;
      final chapter = chapters[index];
      try {
        final cachedData = loader.getByChapterId(chapter.id);
        final ChapterSearchCorpus corpus;
        if (cachedData != null) {
          corpus = cachedData.searchCorpus;
        } else {
          final content =
              loader.contentFor(chapter.id) ??
              await getChapterContent(ref, widget.itemId, book, chapter.id);
          if (isCancelled()) break;
          if (content == null) {
            incomplete = true;
            continue;
          }
          corpus = await loader.searchCorpusForChapter(
            chapterId: chapter.id,
            content: content,
          );
          if (isCancelled()) break;
        }
        final remaining = readerSearchMatchLimit - results.length;
        final scan =
            !kIsWeb && corpus.plainText.length >= readerSearchIsolateThreshold
                ? await compute(scanReaderSearchChunk, (
                  corpus.plainText,
                  query,
                  remaining,
                ))
                : scanReaderSearchChunk((corpus.plainText, query, remaining));
        for (final offset in scan.offsets) {
          results.add(
            ReaderBookSearchMatch.fromText(
              chapterId: chapter.id,
              chapterTitle: chapter.title,
              plainText: corpus.plainText,
              plainOffset: offset,
              matchLength: query.length,
              charOffset: corpus.toCharOffset(offset),
            ),
          );
        }
        if (scan.truncated) {
          truncated = true;
          break;
        }
      } catch (_) {
        incomplete = true;
      }
      await Future<void>.delayed(Duration.zero);
    }
    return (matches: results, truncated: truncated, incomplete: incomplete);
  }

  void _openReaderBookSearchResult(ReaderBookSearchMatch result) {
    if (result.chapterId == _currentChapterId) {
      _openReaderSearchResult(result.charOffset);
      return;
    }
    _closeReaderPanel();
    unawaited(
      switchToChapter(
        result.chapterId,
        intent: ReaderChapterNavigationIntent.offset(
          result.charOffset,
          offerReturn: true,
        ),
      ),
    );
  }

  List<Widget> _buildReaderPanels(
    ReaderItemDetail detail,
    ReaderChapterContent content,
    ReaderControlLayout layout, {
    bool sampleChrome = false,
  }) {
    final active = _panelCoordinator.active;
    final Widget overlay;
    if (active == null) {
      overlay = const SizedBox.shrink(key: ValueKey('reader-panel-none'));
    } else {
      final l10n = AppLocalizations.of(context);
      final title = switch (active) {
        ReaderPanelType.contents => l10n.readerTableOfContents,
        ReaderPanelType.settings => l10n.readerSettingsTitle,
        ReaderPanelType.search => l10n.readerSearchInBook,
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
          _annotationHandler?.buildPanel(
                context,
                bookmarks: _bookmarks,
                onSelectBookmark: (bm) {
                  onAnnotationSelected(bm.chapterId, bm.charOffset);
                },
                onDeleteBookmark: (bm) async {
                  await ref
                      .read(readerDataManagerProvider)
                      .deleteBookmark(bm.id);
                  await checkBookmarkState();
                },
              ) ??
              const SizedBox.shrink(),
        ReaderPanelType.shortcuts => ReaderShortcutPanel(
          settings: _settings,
          isComic: false,
        ),
      };
      if (!sampleChrome && layout.usesSidePanel) {
        final popoverWidth = switch (active) {
          ReaderPanelType.contents => 360.0,
          ReaderPanelType.settings => 380.0,
          ReaderPanelType.search => 400.0,
          ReaderPanelType.annotations => 380.0,
          ReaderPanelType.shortcuts => 360.0,
        };
        overlay = DesktopReaderPopover(
          key: ValueKey(active),
          alignLeft: false,
          width: popoverWidth,
          eyebrow: title,
          onDismissOutside: _closeReaderPanel,
          child: child,
        );
      } else {
        overlay = ReaderAdaptivePanelOverlay(
          key: ValueKey(active),
          title: title,
          settings: _settings,
          layout: layout,
          eyebrow: detail.item.title,
          onClose: _closeReaderPanel,
          child: child,
        );
      }
    }
    // 槽位始终存在：关闭面板时由 AnimatedSwitcher 保留旧子树并播放退场，
    // 直接返回空列表会瞬间摘除整棵子树，没有任何过渡。
    return [
      Positioned.fill(
        child: AnimatedSwitcher(
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 260),
          ),
          reverseDuration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 200),
          ),
          switchInCurve: MotionToken.curve,
          switchOutCurve: MotionToken.curveIn,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0.06, -0.02),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            final scale = Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(
                  scale: scale,
                  alignment: Alignment.topRight,
                  child: child,
                ),
              ),
            );
          },
          layoutBuilder:
              (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  for (final child in previousChildren)
                    IgnorePointer(child: child),
                  if (currentChild != null) currentChild,
                ],
              ),
          child: overlay,
        ),
      ),
    ];
  }
}
