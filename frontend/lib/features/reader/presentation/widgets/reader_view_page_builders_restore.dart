part of 'reader_view_page_builders.dart';

/// 字符偏移/滚动/页码进度恢复流程。
extension ReaderViewPageBuildersRestore on ReaderViewPageBuilders {
  void _handlePendingCharOffsetRestore() {
    final restoreCharOffset = pendingRestoreCharOffset;
    pendingRestoreCharOffset = null;
    if (restoreCharOffset == null) {
      isRestoringProgress = false;
      modeSwitchInProgress = false;
      return;
    }
    final chapterData = contentLoader?.get(currentChapterId, settings);
    if (chapterData == null || chapterData.totalChars <= 0) {
      // 数据未就绪，重新排队等待下次 build 重试
      pendingRestoreCharOffset = restoreCharOffset;
      return;
    }

    if (restoreCharOffset <= 0) {
      scrollProgress = 0;
      positionTracker.setCharOffset(0, currentChapterId);
      isRestoringProgress = false;
      modeSwitchInProgress = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });
      return;
    }

    final progress = (restoreCharOffset / chapterData.totalChars).clamp(
      0.0,
      1.0,
    );
    scrollProgress = progress;
    final capturedCharOffset = restoreCharOffset;
    final capturedPageWidth = computePageWidth();
    final capturedSettings = settings;
    final capturedTextScale = MediaQuery.textScalerOf(context).scale(1.0);
    final capturedAnchorY = viewportAnchorY;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final restoreScheduledAt = DateTime.now();
      // 目标内容坐标只依赖冻结输入：恢复 tick 逐帧调用本构造器，
      // 缓存避免每帧全章线性扫描 + TextPainter 测量。精测收敛
      // （hasPreciseHeights 翻转）时重算一次，估算落点随精测自愈。
      double? cachedRestoreContentY;
      bool cachedRestorePrecise = false;
      restore.start(
        scrollController: scrollController,
        targetOffsetBuilder: () {
          if (!scrollController.hasClients) return 0;
          final max = scrollController.position.maxScrollExtent;
          if (max <= 0) return 0;
          final precise =
              contentLoader
                  ?.get(currentChapterId, settings)
                  ?.hasPreciseHeights ??
              false;
          if (!precise) {
            // 高度未精测：估算图对章尾低估可达数十个百分点，此时落位
            // 会停在半途。触发精测并原地保持（返回 null 不 settle），
            // 待收敛后由本 builder 给出真实目标。
            contentLoader?.ensurePreciseHeights(
              chapterId: currentChapterId,
              pageWidth: capturedPageWidth,
              settings: capturedSettings,
              textScale: capturedTextScale,
            );
            return null;
          }
          if (cachedRestoreContentY == null ||
              cachedRestorePrecise != precise) {
            cachedRestoreContentY = contentLoader?.charOffsetToPixelOffset(
              currentChapterId,
              capturedCharOffset,
              pageWidth: capturedPageWidth,
              settings: capturedSettings,
              textScale: capturedTextScale,
            );
            cachedRestorePrecise = precise;
          }
          final contentY = cachedRestoreContentY;
          if (contentY == null || contentY <= 0) return 0;
          return (contentY - capturedAnchorY).clamp(0.0, max);
        },
        isUserScrolling: () => lastPointerDownTime.isAfter(restoreScheduledAt),
        onSettled: (completed) {
          if (completed) {
            positionTracker.setCharOffset(capturedCharOffset, currentChapterId);
          } else {
            // 被用户滚动中断或超时：当前真实位置即事实，恢复静默窗口
            // 让进度写入立即恢复，追踪由下一次滚动回调修正
            restoreSilenceUntil = DateTime.fromMillisecondsSinceEpoch(0);
          }
          isRestoringProgress = false;
          if (mounted) _updateState(() {});
        },
      );
    });
  }

  void _schedulePendingScrollRestore() {
    if (pendingRestoreCharOffset == null && pendingChapterProgress == null) {
      return;
    }
    if (_scrollRestoreScheduled) {
      return;
    }
    _scrollRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollRestoreScheduled = false;
      if (!mounted) {
        return;
      }
      if (pendingRestoreCharOffset != null) {
        _handlePendingCharOffsetRestore();
      } else if (pendingChapterProgress != null) {
        _handlePendingProgressRestore();
      }
    });
  }

  void _schedulePendingPageCharOffsetRestore(ChapterData chapterData) {
    if (_pageRestoreScheduled) {
      return;
    }
    _pageRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageRestoreScheduled = false;
      if (!mounted) {
        return;
      }
      final restoreCharOffset = pendingRestoreCharOffset;
      pendingRestoreCharOffset = null;
      if (restoreCharOffset == null) {
        isRestoringProgress = false;
        modeSwitchInProgress = false;
        return;
      }
      unawaited(_restorePageCharOffset(chapterData, restoreCharOffset));
    });
  }

  Future<void> _restorePageCharOffset(
    ChapterData chapterData,
    int restoreCharOffset,
  ) async {
    final requestedChapterId = currentChapterId;
    try {
      final targetPage = await findPageByCharOffset(
        chapterData,
        restoreCharOffset,
      );
      if (!mounted) {
        return;
      }
      if (kDebugMode) {
        readerDebugLog(
          'PageRestore: charOffset=$restoreCharOffset → '
          'targetPage=$targetPage (chapter=$requestedChapterId)',
        );
      }
      if (targetPage == null || requestedChapterId != currentChapterId) {
        // 定位被取消或章节已切换：当前章节请求结束时必须退出恢复态，避免遮罩滞留
        if (requestedChapterId == currentChapterId) {
          _updateState(() {
            isRestoringProgress = false;
            modeSwitchInProgress = false;
          });
        }
        return;
      }
      final totalChars = chapterData.totalChars;
      final capturedProgress =
          totalChars <= 0
              ? 0.0
              : (restoreCharOffset / totalChars).clamp(0.0, 1.0).toDouble();
      scrollProgress = capturedProgress;
      positionTracker.setCharOffset(restoreCharOffset, currentChapterId);
      // locate 按需算出目标页后，页数通知器可能仍停留在预热进度；先同步到
      // 导航器实际页数，避免恢复跳转因 PageView item 数不足被钳制到半途页。
      final navigator = chapterData.getOrCreatePageNavigator(
        computePageWidth(),
        computePageHeight(),
        settings,
        textScale: MediaQuery.textScalerOf(context).scale(1.0),
      );
      if (pageCountNotifier.value < targetPage + 1) {
        pageCountNotifier.value = navigator.readablePageCount;
      }
      // 落位动画（_syncPageView animateToPage）期间物理页会路过中间页，
      // 静默窗内的提交按闸门丢弃，动画结束后的正常翻页不受影响。
      restoreSilenceUntil = DateTime.now().add(
        const Duration(milliseconds: 450),
      );
      _updateState(() {
        pageModePage = targetPage;
        modeSwitchInProgress = false;
        isRestoringProgress = false;
      });
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog(
          'PageRestore: locate failed charOffset=$restoreCharOffset '
          '(chapter=$requestedChapterId): $e',
        );
      }
      if (mounted && requestedChapterId == currentChapterId) {
        _updateState(() {
          isRestoringProgress = false;
          modeSwitchInProgress = false;
        });
      }
    }
  }

  void _handlePendingProgressRestore() {
    final progressRatio = pendingChapterProgress!.clamp(0.0, 1.0);
    pendingChapterProgress = null;
    scrollProgress = progressRatio;
    final capturedRatio = progressRatio;
    final capturedPageWidth = computePageWidth();
    final capturedTextScale = MediaQuery.textScalerOf(context).scale(1.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final restoreScheduledAt = DateTime.now();
      restore.start(
        scrollController: scrollController,
        targetOffsetBuilder: () {
          if (!scrollController.hasClients) return 0;
          final max = scrollController.position.maxScrollExtent;
          return capturedRatio * max;
        },
        isUserScrolling: () => lastPointerDownTime.isAfter(restoreScheduledAt),
        onSettled: (completed) {
          if (completed && scrollController.hasClients) {
            final max = scrollController.position.maxScrollExtent;
            final data = contentLoader?.get(currentChapterId, settings);
            if (data != null && max > 0) {
              final settledContentY = scrollController.offset + viewportAnchorY;
              final settledCharOffset =
                  contentLoader?.contentYToCharOffset(
                    currentChapterId,
                    settledContentY,
                    pageWidth: capturedPageWidth,
                    settings: settings,
                    textScale: capturedTextScale,
                  ) ??
                  0;
              positionTracker.updateFromScroll(
                offset: scrollController.offset,
                maxExtent: max,
                totalChars: data.totalChars,
                chapterId: currentChapterId,
                charOffset: settledCharOffset,
              );
            }
          } else if (!completed) {
            restoreSilenceUntil = DateTime.fromMillisecondsSinceEpoch(0);
          }
          isRestoringProgress = false;
          if (mounted) _updateState(() {});
        },
      );
    });
  }
}
