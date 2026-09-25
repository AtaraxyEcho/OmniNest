part of 'reader_view_page.dart';

/// 章节映射缓存、状态更新辅助、音量键翻页与构建工作调度。
extension _ReaderViewPageBuildWork on _ReaderViewPageState {
  /// 按(parsedBook 身份)缓存章节映射，避免每次 build O(章节) 重分配。
  List<ReaderChapter> _cachedChaptersFor(ParsedBook? parsedBook) {
    if (parsedBook == null) {
      return const <ReaderChapter>[];
    }
    if (!identical(_chaptersCacheSource, parsedBook)) {
      _chaptersCacheSource = parsedBook;
      _chaptersCache =
          parsedBook.chapters
              .asMap()
              .entries
              .map(
                (e) => ReaderChapter.fromParsed(
                  e.key,
                  e.value.title,
                  contentPath: e.value.contentPath,
                ),
              )
              .toList();
    }
    return _chaptersCache;
  }

  /// 音量键事件映射为阅读命令：下键向后翻，上键向前翻。
  void _handleVolumeKeyEvent(ReaderVolumeKeyDirection direction) {
    if (!mounted) {
      return;
    }
    final forward = direction == ReaderVolumeKeyDirection.down;
    if (_isPageMode) {
      final command =
          forward ? ReaderCommand.nextPage : ReaderCommand.previousPage;
      if (_requiresReaderCommandGate(command) && !_readerCommandGate.accept()) {
        return;
      }
      if (forward) {
        _pageTurnController.next();
      } else {
        _pageTurnController.previous();
      }
      return;
    }
    unawaited(_scrollReaderViewport(forward ? 0.88 : -0.88));
  }

  void _scheduleReaderBuildWork({
    required ParsedBook? latestParsedBook,
    required ReaderChapterContent? loadedContent,
    required List<ReaderChapter> chapters,
    required bool providerHasError,
  }) {
    if (latestParsedBook != null) {
      _pendingParsedBook = latestParsedBook;
    }
    _pendingReaderContent = loadedContent;
    _pendingReaderChapters = List<ReaderChapter>.of(chapters);
    _pendingReaderProviderError = providerHasError;
    if (_readerBuildWorkScheduled) {
      return;
    }
    _readerBuildWorkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readerBuildWorkScheduled = false;
      if (!mounted) {
        return;
      }

      final parsedBook = _pendingParsedBook;
      final content = _pendingReaderContent;
      final chapters = _pendingReaderChapters ?? const <ReaderChapter>[];
      final providerHasError = _pendingReaderProviderError;
      _pendingParsedBook = null;
      _pendingReaderContent = null;
      _pendingReaderChapters = null;
      _pendingReaderProviderError = false;

      if (parsedBook != null) {
        _parsedBookSnapshot = parsedBook;
        unawaited(loadChapterContentIfNeeded(parsedBook));
      }

      var stateChanged = false;
      if (_isSwitchingChapter && providerHasError && parsedBook == null) {
        _isSwitchingChapter = false;
        _showChapterLoadingOverlay = false;
        stateChanged = true;
      }

      if (content != null) {
        if (_contentLoader == null) {
          initContentLoader(chapters);
          stateChanged = true;
        }
        final chapterData = _contentLoader?.get(_currentChapterId, _settings);
        if (!_isLoadingChapter &&
            (_isSwitchingChapter || chapterData == null)) {
          unawaited(loadCurrentChapter(content));
        }
      }

      if (stateChanged && mounted) {
        _updateState(() {});
      }
    });
  }
}
