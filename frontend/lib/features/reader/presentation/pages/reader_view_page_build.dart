part of 'reader_view_page.dart';

/// [_ReaderViewPageState] 的根构建树：路由退出、详情/章节错误与骨架态。
extension _ReaderViewPageRootBuild on _ReaderViewPageState {
  Widget buildReaderView(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));
    final bookAsync = ref.watch(parsedBookProvider(widget.itemId));
    if (detailAsync.asData?.value.item.isComic == false) {
      ref.watch(cachedBookHandleProvider(widget.itemId));
      ref.watch(epubParserServiceProvider(widget.itemId));
    }

    // 从已解析的书籍中按需加载当前章节内容
    final latestParsedBook = bookAsync.asData?.value;
    final parsedBook = latestParsedBook ?? _parsedBookSnapshot;
    final loadedContent = _cachedContent;
    // 章节列表按 parsedBook 身份缓存，避免每次 build O(章节) 重分配。
    final chapters = _cachedChaptersFor(parsedBook);
    _scheduleReaderBuildWork(
      latestParsedBook: latestParsedBook,
      loadedContent: loadedContent,
      chapters: chapters,
      providerHasError: bookAsync.hasError && parsedBook == null,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        clearReaderSelection();
        syncProgressSync();
        _syncProgressOnExit();
        ref.invalidate(readerItemDetailProvider(widget.itemId));
        safePop();
      },
      child: Scaffold(
        backgroundColor: _settings.surfaceColor,
        body: detailAsync.when(
          data: (detail) {
            if (bookAsync.hasError && parsedBook == null) {
              return AppErrorView(
                message: AppLocalizations.of(context).readerChapterLoadFailed,
                onBack: safePop,
                onRetry: () {
                  ref.invalidate(parsedBookProvider(widget.itemId));
                },
              );
            }
            final content = loadedContent ?? _cachedContent;

            if (kDebugMode) {
              readerDebugLog(
                'ReaderView build: content=${content != null}, _contentLoader=${_contentLoader != null}, _isLoadingChapter=$_isLoadingChapter, chapters=${chapters.length}',
              );
            }
            if (content == null || _contentLoader == null) {
              if (parsedBook != null &&
                  _chapterLoadCoordinator.hasFailed(_currentChapterId)) {
                return AppErrorView(
                  message: AppLocalizations.of(context).readerChapterLoadFailed,
                  onBack: safePop,
                  onRetry: () {
                    _chapterLoadCoordinator.clearFailure(_currentChapterId);
                    _updateState(() {});
                    unawaited(loadChapterContentIfNeeded(parsedBook));
                  },
                );
              }
              if (kDebugMode) {
                readerDebugLog(
                  'ReaderView: showing skeleton (content=${content != null}, loader=${_contentLoader != null})',
                );
              }
              if (_isSwitchingChapter && !_showChapterLoadingOverlay) {
                return ColoredBox(color: _settings.surfaceColor);
              }
              return _buildReaderSkeleton();
            }

            // Provider 数据更新检测：仅在章节加载完成后检查
            if (!_isLoadingChapter &&
                _contentLoader!.get(_currentChapterId, _settings) != null) {
              final latestSnapshot = ReaderProgressSnapshot.fromServer(
                detailAsync.asData?.value.progress,
              );
              final latestTime = latestSnapshot.updatedAt;
              final shouldApply =
                  latestSnapshot.chapterId == _currentChapterId &&
                  latestTime != null &&
                  (_lastAppliedProgressAt == null ||
                      latestTime.isAfter(_lastAppliedProgressAt!)) &&
                  !_isOwnProgressEcho(latestSnapshot, latestTime);
              if (shouldApply) {
                scheduleProgressSnapshotApply(latestSnapshot);
              }
            }

            return _buildReader(detail, content);
          },
          error:
              (e, _) => AppErrorView(
                message: e.toString(),
                onBack: safePop,
                onRetry:
                    () =>
                        ref.invalidate(readerItemDetailProvider(widget.itemId)),
              ),
          loading: _buildReaderSkeleton,
        ),
      ),
    );
  }
}
