part of 'reader_view_page_mixin.dart';

/// 进度快照读取与本地/服务端同步。
extension ReaderViewPageMixinProgress on ReaderViewPageMixin {
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 进度恢复与保存
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 加载本地+服务端+路由进度，返回最新的快照。
  Future<ReaderProgressSnapshot?> loadLocalProgress(String chapterId) async {
    final localSnapshot = await ReaderProgressHelper.loadLocalProgress(
      itemId: itemId,
      chapterId: chapterId,
    );
    if (!mounted) return null;
    final progressDetail = ref.read(readerItemDetailProvider(itemId)).value;
    final serverSnapshot = ReaderProgressSnapshot.fromServer(
      progressDetail?.progress,
    );
    final routeSnapshot = initialProgress;
    final result = latestProgressForCurrentChapter([
      routeSnapshot,
      localSnapshot,
      serverSnapshot,
    ]);
    if (kDebugMode) {
      readerDebugLog(
        'ProgressLoad RESULT: ${result != null ? "chapterId=${result.chapterId}, progress=${result.progress}, charOffset=${result.charOffset}" : "null"}',
      );
    }
    return result;
  }

  /// 从候选快照中选取当前章节最新的进度。
  ReaderProgressSnapshot? latestProgressForCurrentChapter(
    List<ReaderProgressSnapshot?> snapshots,
  ) {
    final all = snapshots.whereType<ReaderProgressSnapshot>().toList();
    ReaderProgressSnapshot? chapterMatch;
    for (final s in all) {
      if (s.chapterId == currentChapterId) {
        chapterMatch = ReaderProgressSnapshot.latest(chapterMatch, s);
      }
    }
    if (chapterMatch != null) return chapterMatch;
    // chapterId 为空的 generic 快照无法证明属于当前章节，施加会把
    // 服务端旧数据错映射到任意打开的章节；只记录观测日志不再回退。
    if (all.any((s) => s.chapterId.isEmpty) && kDebugMode) {
      readerDebugLog(
        'ProgressLoad: generic snapshot ignored for $currentChapterId',
      );
    }
    return null;
  }

  /// dispose 后构建简单快照（不依赖 ref）。
  ReaderProgressSnapshot? buildSimpleSnapshot(double? progressOverride) {
    final chapterProg = (progressOverride ?? scrollProgress).clamp(0.0, 1.0);
    return ReaderProgressSnapshot(
      chapterId: currentChapterId,
      progress: bookProgress,
      chapterProgress: chapterProg,
      chapterTitle: cachedContent?.title ?? '',
      mode: isPageMode ? 'page' : 'scroll',
      updatedAt: DateTime.now(),
    );
  }

  /// 计算当前阅读进度。
  double computeProgress() {
    return scrollProgress;
  }

  /// 异步同步进度到本地和服务端。
  ///
  /// 服务端采用主流阅读器的节流策略：本地写入保持连续（协调器合并），
  /// 上报仅在「距上次超过最小间隔且位置确有变化」或 force 时执行，
  /// 避免滚动/点击逐次产生请求；章节切换等强一致场景传 force。
  Future<void> syncProgressAsync({
    double? progressOverride,
    bool force = false,
    String? chapterId,
    int? charOffset,
    int? generation,
  }) async {
    if (generation != null && generation != syncProgressGeneration) {
      return;
    }
    if (isLoadingChapter && !force) {
      if (kDebugMode) {
        readerDebugLog(
          'ProgressSync SKIP: isLoadingChapter=true, force=$force',
        );
      }
      return;
    }
    final snapshot =
        mounted
            ? buildProgressSnapshot(
              progressOverride: progressOverride,
              chapterId: chapterId,
              charOffset: charOffset,
            )
            : buildSimpleSnapshot(progressOverride);
    if (snapshot == null) {
      if (kDebugMode) {
        readerDebugLog('ProgressSync SKIP: snapshot is null');
      }
      return;
    }
    if (kDebugMode) {
      readerDebugLog(
        'ProgressSync START: chapter=${snapshot.chapterId}, '
        'progress=${snapshot.progress}, mode=${snapshot.mode}',
      );
    }

    progressSaveCoordinator.schedule(snapshot);
    noteOwnProgressSave(snapshot);
    await progressSaveCoordinator.flush();
    if (!mounted ||
        (generation != null && generation != syncProgressGeneration)) {
      return;
    }

    // 节流判定：未跨过最小间隔且位置变化不显著时不上报
    final now = DateTime.now();
    final lastAt = _lastServerSyncAt;
    final movedEnough =
        snapshot.chapterId != _lastSyncedChapterId ||
        (snapshot.charOffset - (_lastSyncedCharOffset ?? -1)).abs() >= 64 ||
        (snapshot.progress - (_lastSyncedProgress ?? -1)).abs() >= 0.002;
    if (!force &&
        (now.difference(lastAt ?? DateTime.fromMillisecondsSinceEpoch(0)) <
                ReaderViewPageMixin._serverSyncMinInterval ||
            !movedEnough)) {
      return;
    }
    _lastServerSyncAt = now;
    _lastSyncedProgress = snapshot.progress;
    _lastSyncedChapterId = snapshot.chapterId;
    _lastSyncedCharOffset = snapshot.charOffset;
    await ref
        .read(readerProgressSyncServiceProvider)
        .sync(
          itemId: itemId,
          charOffset: snapshot.charOffset,
          progressPercent: snapshot.progress,
          readingMode: snapshot.mode,
          chapterId: snapshot.chapterId,
        );
  }

  /// 同步保存进度到本地（不阻塞、不依赖 mounted 状态）。
  void syncProgressSync() {
    if (restore.shouldSuppressWrites) return;
    final snapshot = buildProgressSnapshot();
    if (snapshot == null) return;
    if (kDebugMode) {
      readerDebugLog(
        'ProgressSyncSync: chapter=${snapshot.chapterId}, '
        'progress=${snapshot.progress}, offset=${snapshot.charOffset}',
      );
    }
    progressSaveCoordinator.schedule(snapshot);
    noteOwnProgressSave(snapshot);
    unawaited(progressSaveCoordinator.flush());
  }
}
