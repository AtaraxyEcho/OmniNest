part of 'reader_view_page.dart';

/// 章节加载失败提示：能确定可执行动作时不用通用文案。
///
/// 未标注原因的失败（例如本地整本超过解析上限）走通用文案，
/// 不猜测成"需要联网"。
String chapterLoadErrorMessage(
  AppLocalizations l10n,
  ReaderChapterFailure? reason,
) {
  return switch (reason) {
    ReaderChapterFailure.needsNetwork => l10n.readerChapterNeedsNetwork,
    ReaderChapterFailure.needsReparse => l10n.readerChapterNeedsReparse,
    ReaderChapterFailure.unsupportedEncoding =>
      l10n.readerChapterUnsupportedEncoding,
    null => l10n.readerChapterLoadFailed,
  };
}

/// [_ReaderViewPageState] 的根构建树：路由退出、详情/章节错误与骨架态。
extension _ReaderViewPageRootBuild on _ReaderViewPageState {
  Widget buildReaderView(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));
    final bookAsync = ref.watch(parsedBookProvider(widget.itemId));
    if (detailAsync.asData?.value.item.isComic == false) {
      ref.watch(cachedBookHandleProvider(widget.itemId));
      ref.watch(epubParserServiceProvider(widget.itemId));
      // TXT 兜底链的整本解码缓存必须随阅读页保活：该服务只被 ref.read 取用，
      // 没有监听就会在每次读取后被回收，导致离线切章反复解码整本书。
      ref.watch(txtParserServiceProvider);
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
                  message: chapterLoadErrorMessage(
                    AppLocalizations.of(context),
                    _chapterLoadCoordinator.failureReason,
                  ),
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
                message: describeUserFacingError(e).displayMessage,
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
