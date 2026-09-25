part of 'reader_view_page_mixin.dart';

/// 章节内容加载、预取与导航意图应用。
extension ReaderViewPageMixinLoad on ReaderViewPageMixin {
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 内容加载
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 初始化内容加载器（仅首次）。
  void initContentLoader(List<ReaderChapter> chapters) {
    if (contentLoader != null) return;
    contentLoader = ReaderContentLoader(allChapters: chapters);
  }

  /// 加载当前章节内容并恢复阅读进度。
  Future<void> loadCurrentChapter(ReaderChapterContent content) async {
    if (kDebugMode) {
      readerDebugLog(
        'ReaderView: loadCurrentChapter called, contentLoader=${contentLoader != null}, isLoadingChapter=$isLoadingChapter',
      );
    }
    if (contentLoader == null || isLoadingChapter) return;
    if (!mounted) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: loadCurrentChapter aborted - not mounted');
      }
      return;
    }
    final requestedChapterId = currentChapterId;
    final generation = loadGeneration;
    final navigationIntent = chapterNavigationIntent;
    isLoadingChapter = true;
    contentLoader!.setActive(requestedChapterId);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    try {
      if (kDebugMode) {
        readerDebugLog(
          'ReaderView: loadChapter starting for $requestedChapterId, content length=${content.content.length}',
        );
      }

      final progressFuture =
          navigationIntent.entryPoint == ReaderChapterEntryPoint.resume
              ? loadLocalProgress(requestedChapterId)
              : Future<ReaderProgressSnapshot?>.value();
      final chapterData = await contentLoader!.loadChapter(
        chapterId: requestedChapterId,
        content: content,
        pageWidth: computePageWidth(),
        pageHeight: isPageMode ? computePageHeight() : 0.0,
        settings: settings,
        textScale: textScale,
        prepareScrollLayout: !isPageMode,
      );
      if (kDebugMode) {
        readerDebugLog(
          'ReaderView: loadChapter completed for $requestedChapterId',
        );
      }

      if (!_isCurrentChapterRequest(requestedChapterId, generation)) {
        if (kDebugMode) {
          readerDebugLog(
            'ReaderView: loadCurrentChapter aborted after load - mounted=$mounted, generation=$generation, loadGeneration=$loadGeneration',
          );
        }
        return;
      }

      preloadAdjacent();

      final snapshot = await progressFuture;
      if (!_isCurrentChapterRequest(requestedChapterId, generation)) return;

      if (navigationIntent.entryPoint == ReaderChapterEntryPoint.resume &&
          snapshot != null) {
        applyProgressSnapshot(snapshot);
      } else {
        _applyChapterNavigationIntent(
          navigationIntent,
          requestedChapterId,
          chapterData,
        );
      }

      chapterNavigationIntent = const ReaderChapterNavigationIntent.resume();
      chapterLoadingTimer?.cancel();
      showChapterLoadingOverlay = false;
      isSwitchingChapter = false;
      isLoadingChapter = false;
      refreshBookProgressNow();
      if (mounted) _updateState(() {});
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: loadCurrentChapter failed: $e');
      }
      if (_isCurrentChapterRequest(requestedChapterId, generation)) {
        isRestoringProgress = false;
        restore.cancel();
      }
    } finally {
      if (_isCurrentChapterRequest(requestedChapterId, generation)) {
        chapterLoadingTimer?.cancel();
        showChapterLoadingOverlay = false;
        isSwitchingChapter = false;
        isLoadingChapter = false;
        refreshBookProgressNow();
        if (mounted) _updateState(() {});
      }
    }
  }

  bool _isCurrentChapterRequest(String chapterId, int generation) {
    return mounted &&
        generation == loadGeneration &&
        chapterId == currentChapterId;
  }

  void _applyChapterNavigationIntent(
    ReaderChapterNavigationIntent intent,
    String chapterId,
    ChapterData chapterData,
  ) {
    final charOffset = switch (intent.entryPoint) {
      ReaderChapterEntryPoint.resume => 0,
      ReaderChapterEntryPoint.start => 0,
      ReaderChapterEntryPoint.end => math.max(0, chapterData.totalChars - 1),
      ReaderChapterEntryPoint.offset => (intent.charOffset ?? 0).clamp(
        0,
        chapterData.totalChars,
      ),
      ReaderChapterEntryPoint.anchor =>
        resolveAnchorCharOffset(chapterId, intent.anchorHref) ?? 0,
    };
    pendingChapterProgress = null;
    // 目录跳章等显式导航：先展示"返回原阅读进度"胶囊（3s 自动隐藏，
    // 点按回跳），再处理章首/章尾的落位分支——start 意图 charOffset=0
    // 会走下方早退，展示逻辑必须在早退之前。
    if (intent.offerReturn && returnToProgressSnapshot != null) {
      showReturnToProgressSnackBar();
    }
    if (charOffset <= 0) {
      pendingRestoreCharOffset = null;
      isRestoringProgress = false;
      pageModePage = 0;
      scrollProgress = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });
      return;
    }
    pendingRestoreCharOffset = charOffset;
    isRestoringProgress = true;
    if (intent.offerReturn && returnToProgressSnapshot != null) {
      showReturnToProgressSnackBar();
    }
  }

  /// 预加载相邻章节。
  void preloadAdjacent() {
    if (contentLoader == null) return;
    final needFetch = contentLoader!.setActive(currentChapterId);
    for (final chapterId in needFetch) {
      unawaited(prefetchChapter(chapterId));
    }
  }

  /// 预加载指定章节内容。
  Future<void> prefetchChapter(String chapterId) async {
    if (!mounted) return;
    try {
      final book = await ref.read(parsedBookProvider(itemId).future);
      if (!mounted) return;
      final content = await getChapterContent(ref, itemId, book, chapterId);
      if (!mounted || contentLoader == null || content == null) return;
      final textScale = MediaQuery.textScalerOf(context).scale(1.0);
      await contentLoader!.loadChapter(
        chapterId: chapterId,
        content: content,
        pageWidth: computePageWidth(),
        pageHeight: 0.0,
        settings: settings,
        textScale: textScale,
        // 预取期完成 phase-one 测高：切章帧零测量，消除落点顶走内容。
        prepareScrollLayout: true,
      );
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: prefetch $chapterId failed: $e');
      }
    }
  }

  /// 按需加载当前章节内容（仅当缓存内容不匹配时）。
  Future<void> loadChapterContentIfNeeded(ParsedBook parsedBook) async {
    if (!mounted) {
      return;
    }
    final requestedChapterId = canonicalReaderChapterId(
      parsedBook,
      currentChapterId,
    );
    if (requestedChapterId != currentChapterId) {
      currentChapterId = requestedChapterId;
    }
    if (cachedContent != null && requestedChapterId == lastLoadedChapterId) {
      return;
    }
    if (chapterLoadCoordinator.hasFailed(requestedChapterId)) {
      return;
    }
    if (chapterLoadCoordinator.isLoading &&
        chapterLoadCoordinator.loadingChapterId == requestedChapterId) {
      return;
    }

    final requestGeneration = chapterLoadCoordinator.begin(requestedChapterId);
    try {
      if (kDebugMode) {
        readerDebugLog(
          'ReaderView: loading chapter content for $requestedChapterId',
        );
      }
      final content = await getChapterContent(
        ref,
        itemId,
        parsedBook,
        requestedChapterId,
      );
      if (kDebugMode) {
        readerDebugLog(
          'ReaderView: chapter content loaded: ${content != null ? "${content.title} (${content.content.length} chars)" : "null"}',
        );
      }
      if (mounted &&
          content != null &&
          chapterLoadCoordinator.isCurrent(
            requestGeneration,
            requestedChapterId,
          ) &&
          requestedChapterId == currentChapterId) {
        chapterLoadCoordinator.succeed(requestGeneration, requestedChapterId);
        _updateState(() {
          cachedContent = content;
          lastLoadedChapterId = requestedChapterId;
        });
      } else if (mounted &&
          content == null &&
          chapterLoadCoordinator.isCurrent(
            requestGeneration,
            requestedChapterId,
          ) &&
          requestedChapterId == currentChapterId) {
        chapterLoadCoordinator.fail(requestGeneration, requestedChapterId);
        isSwitchingChapter = false;
        isRestoringProgress = false;
        _updateState(() {});
      }
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: chapter content load failed: $e');
      }
      if (mounted &&
          chapterLoadCoordinator.isCurrent(
            requestGeneration,
            requestedChapterId,
          ) &&
          requestedChapterId == currentChapterId) {
        chapterLoadCoordinator.fail(requestGeneration, requestedChapterId);
        isSwitchingChapter = false;
        isRestoringProgress = false;
        _updateState(() {});
      }
    }
  }
}
