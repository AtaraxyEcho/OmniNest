import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reader_progress_save_coordinator.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_helper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// reader_view_page.dart 的业务逻辑 mixin。
///
/// 提取所有非 build、非 lifecycle 方法，降低主文件行数。
/// 通过抽象 getter/setter 访问 State 字段，与 ReaderViewPageBuilders 分离。
mixin ReaderViewPageMixin on ConsumerState<ReaderViewPage> {
  // ── 由 State 提供的抽象成员（字段访问） ──

  ReaderPositionTracker get positionTracker;
  ReaderContentLoader? get contentLoader;
  set contentLoader(ReaderContentLoader? value);
  ScrollController get scrollController;
  ScrollRestore get restore;
  ReaderViewSettings get settings;
  set settings(ReaderViewSettings value);
  String get currentChapterId;
  set currentChapterId(String value);
  ReaderChapterContent? get cachedContent;
  set cachedContent(ReaderChapterContent? value);
  ReaderAnnotationHandler? get annotationHandler;

  // ── 渲染状态 ──

  dynamic /* List<_FlatPageEntry> */ get flatPages;
  set flatPages(dynamic value);
  int get currentPageIndex;
  set currentPageIndex(int value);
  int get pageModePage;
  set pageModePage(int value);

  // ── 进度 ──

  double get scrollProgress;
  set scrollProgress(double value);
  DateTime? get lastAppliedProgressAt;
  set lastAppliedProgressAt(DateTime? value);

  /// 记录本机推送的进度快照，供 provider 回灌时判定自身回声。
  void noteOwnProgressSave(ReaderProgressSnapshot snapshot);
  double? get pendingChapterProgress;
  set pendingChapterProgress(double? value);
  int? get pendingRestoreCharOffset;
  set pendingRestoreCharOffset(int? value);
  ReaderChapterNavigationIntent get chapterNavigationIntent;
  set chapterNavigationIntent(ReaderChapterNavigationIntent value);
  bool get isRestoringProgress;
  set isRestoringProgress(bool value);
  bool get modeSwitchInProgress;
  set modeSwitchInProgress(bool value);

  /// 模式切换时冻结的 charOffset，跨多次 onPageChanged 保留原始锚点。
  int? get modeSwitchAnchor;
  set modeSwitchAnchor(int? value);
  int get restoreTargetCharOffset;
  set restoreTargetCharOffset(int value);
  DateTime get restoreSilenceUntil;
  set restoreSilenceUntil(DateTime value);
  DateTime get lastPointerDownTime;

  // ── 章节切换 ──

  ReaderProgressSnapshot? get returnToProgressSnapshot;
  set returnToProgressSnapshot(ReaderProgressSnapshot? value);
  bool get showReturnControl;
  set showReturnControl(bool value);
  Timer? get returnControlTimer;
  set returnControlTimer(Timer? value);
  Timer? get dismissReturnTimer;
  set dismissReturnTimer(Timer? value);

  // ── 并发控制 ──

  bool get isAnimating;
  set isAnimating(bool value);
  bool get isSwitchingChapter;
  set isSwitchingChapter(bool value);
  bool get isLoadingChapter;
  set isLoadingChapter(bool value);
  bool get showChapterLoadingOverlay;
  set showChapterLoadingOverlay(bool value);
  Timer? get chapterLoadingTimer;
  set chapterLoadingTimer(Timer? value);
  int get loadGeneration;
  set loadGeneration(int value);
  ReaderViewSettings? get pendingSettings;
  set pendingSettings(ReaderViewSettings? value);

  // ── UI 状态 ──

  bool get showControls;
  set showControls(bool value);
  bool get showTts;
  set showTts(bool value);
  bool get isHoveringControls;
  set isHoveringControls(bool value);
  bool get isBookmarked;
  set isBookmarked(bool value);
  bool get isInBookshelf;
  set isInBookshelf(bool value);
  bool get bookmarkBusy;
  set bookmarkBusy(bool value);
  bool get bookshelfBusy;
  set bookshelfBusy(bool value);

  Timer? get hideTimer;
  set hideTimer(Timer? value);
  Timer? get persistTimer;
  set persistTimer(Timer? value);
  Timer? get repaginateTimer;
  set repaginateTimer(Timer? value);
  ReaderProgressSaveCoordinator get progressSaveCoordinator;
  int get syncProgressGeneration;
  set syncProgressGeneration(int value);
  String? get cachedPlainText;
  set cachedPlainText(String? value);
  String? get cachedContentSource;
  set cachedContentSource(String? value);
  Size? get lastViewportSize;
  set lastViewportSize(Size? value);

  // ── 阅读会话 ──

  DateTime get sessionStart;
  static const hideDelay = Duration(seconds: 3);
  static const restoreSilenceMs = 400;

  // ── 按需加载章节内容 ──

  ReaderChapterLoadCoordinator get chapterLoadCoordinator;
  ReaderPageLocator get pageLocator;
  String? get lastLoadedChapterId;
  set lastLoadedChapterId(String? value);

  // ── 计算属性 ──

  bool get isPageMode;

  String get currentChapterTitle;

  double get bookProgress;

  Size? get pageViewportSize;
  set pageViewportSize(Size? value);

  // ── Widget 访问 ──

  String get itemId;
  Map<String, dynamic>? get initialProgressPayload;

  // ── 跨 mixin 方法（由 ReaderViewPageBuilders 实现） ──

  double computePageWidth();
  double computePageHeight();
  double get viewportAnchorY;
  int computePageCharOffset(int pageIndex);
  int? resolveAnchorCharOffset(String chapterId, String? anchor);
  void applyImmersiveMode(bool immersive);
  void persistSettings(ReaderViewSettings settings);
  Future<void> checkBookmarkState();
  void startHideTimer();

  // ── 由 State 实现的抽象方法 ──

  /// 构建扁平化页面列表（依赖私有类型 _FlatPageEntry）。
  dynamic /* List<_FlatPageEntry> */ buildFlatPages();
  void clearReaderSelection();

  // ── 常量 ──

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
      flatPages = buildFlatPages();
      if (kDebugMode) {
        readerDebugLog(
          'ReaderView: flatPages.length=${(flatPages as List).length}',
        );
      }
      currentPageIndex = globalPageIndexFor(requestedChapterId, 0);

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
      if (mounted) setState(() {});
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
        if (mounted) setState(() {});
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

  /// 根据 chapterId 和 localPageIndex 查找全局页面索引。
  int globalPageIndexFor(String chapterId, int localPageIndex) {
    final pages = flatPages as List;
    for (var i = 0; i < pages.length; i++) {
      final entry = pages[i];
      if (entry.chapterId == chapterId &&
          entry.localPageIndex == localPageIndex) {
        return i;
      }
    }
    return 0;
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
        prepareScrollLayout: false,
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
        setState(() {
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
        setState(() {});
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
        setState(() {});
      }
    }
  }

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
    final routeSnapshot = ReaderProgressSnapshot.fromPayload(
      initialProgressPayload,
    );
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

  /// 应用进度快照到当前阅读位置。
  void applyProgressSnapshot(ReaderProgressSnapshot snapshot) {
    if (snapshot.chapterId.isNotEmpty &&
        snapshot.chapterId != currentChapterId) {
      if (kDebugMode) {
        readerDebugLog(
          'ProgressRestore SKIP: chapter mismatch '
          '(snapshot=${snapshot.chapterId}, current=$currentChapterId)',
        );
      }
      return;
    }
    final chapterData = contentLoader?.get(currentChapterId, settings);
    if (chapterData == null) {
      if (kDebugMode) {
        readerDebugLog('ProgressRestore SKIP: chapterData is null');
      }
      return;
    }

    double chapterProgress = snapshot.chapterProgress;
    if (chapterProgress <= 0 &&
        snapshot.charOffset > 0 &&
        chapterData.totalChars > 0) {
      chapterProgress = (snapshot.charOffset / chapterData.totalChars).clamp(
        0.0,
        1.0,
      );
    }
    lastAppliedProgressAt = snapshot.updatedAt ?? DateTime.now();

    if (kDebugMode) {
      readerDebugLog(
        'ProgressRestore APPLY: chapter=${snapshot.chapterId}, '
        'progress=$chapterProgress, charOffset=${snapshot.charOffset}, '
        'currentScrollProgress=$scrollProgress, '
        'mode=${isPageMode ? "page" : "scroll"}',
      );
    }

    if (isPageMode) {
      scrollProgress = chapterProgress;
      isRestoringProgress = true;
      pendingRestoreCharOffset = snapshot.charOffset;
      positionTracker.setCharOffset(snapshot.charOffset, snapshot.chapterId);
      if (mounted) setState(() {});
      return;
    }

    {
      positionTracker.setCharOffset(snapshot.charOffset, snapshot.chapterId);
      if (kDebugMode) {
        readerDebugLog(
          'ProgressRestore DEBUG: charOffset=${snapshot.charOffset}, '
          'chapterProgress=$chapterProgress, '
          'totalChars=${chapterData.totalChars}',
        );
      }
      isRestoringProgress = true;
      restoreTargetCharOffset = snapshot.charOffset;
      restoreSilenceUntil = DateTime.now().add(
        const Duration(milliseconds: restoreSilenceMs),
      );
      scrollProgress = chapterProgress;
      if (snapshot.charOffset > 0) {
        pendingChapterProgress = null;
        pendingRestoreCharOffset = snapshot.charOffset;
      } else {
        pendingRestoreCharOffset = null;
        pendingChapterProgress = chapterProgress;
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 根据字符偏移定位对应页码。
  Future<int?> findPageByCharOffset(
    ChapterData chapterData,
    int charOffset,
  ) async {
    if (charOffset <= 0 || chapterData.blocks.isEmpty) return 0;

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final navigator = chapterData.getOrCreatePageNavigator(
      computePageWidth(),
      computePageHeight(),
      settings,
      textScale: textScale,
    );

    return pageLocator.locate(navigator, charOffset);
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

  /// 构建当前阅读进度快照。
  ReaderProgressSnapshot? buildProgressSnapshot({
    double? progressOverride,
    String? chapterId,
    int? charOffset,
  }) {
    final snapshotChapterId = chapterId ?? currentChapterId;
    final snapshotChapterTitle = cachedContent?.title ?? '';

    int effectiveCharOffset;
    if (charOffset != null) {
      effectiveCharOffset = charOffset;
    } else if (modeSwitchAnchor != null) {
      // 模式切换期间：使用冻结的精确锚点，不用页首
      effectiveCharOffset = modeSwitchAnchor!;
    } else if (isPageMode) {
      effectiveCharOffset = computePageCharOffset(pageModePage);
    } else if (!isRestoringProgress &&
        chapterId == null &&
        scrollController.hasClients &&
        scrollController.position.maxScrollExtent > 0) {
      effectiveCharOffset =
          contentLoader?.contentYToCharOffset(
            snapshotChapterId,
            scrollController.offset + viewportAnchorY,
            pageWidth: computePageWidth(),
            settings: settings,
            textScale: MediaQuery.textScalerOf(context).scale(1.0),
          ) ??
          positionTracker.charOffset;
    } else {
      effectiveCharOffset = positionTracker.charOffset;
    }

    final snapshotTotalChars =
        contentLoader?.getByChapterId(snapshotChapterId)?.totalChars ?? 0;
    final double chapterProgress;
    if (progressOverride != null) {
      chapterProgress = progressOverride.clamp(0.0, 1.0);
    } else if (snapshotTotalChars > 0) {
      chapterProgress = (effectiveCharOffset / snapshotTotalChars).clamp(
        0.0,
        1.0,
      );
    } else {
      chapterProgress = scrollProgress.clamp(0.0, 1.0);
    }

    if (kDebugMode) {
      readerDebugLog(
        'ProgressSnapshot SAVE: chapter=$snapshotChapterId, '
        'chapterProgress=$chapterProgress, charOffset=$effectiveCharOffset, '
        'override=$progressOverride, '
        'scrollProgress=$scrollProgress, '
        'hasClients=${scrollController.hasClients}',
      );
    }

    return ReaderProgressSnapshot(
      chapterId: snapshotChapterId,
      charOffset: effectiveCharOffset,
      progress: bookProgress,
      chapterProgress: chapterProgress,
      mode: isPageMode ? 'page' : 'scroll',
      chapterTitle: snapshotChapterTitle,
      updatedAt: DateTime.now(),
    );
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

  DateTime? _lastServerSyncAt;
  double? _lastSyncedProgress;
  String? _lastSyncedChapterId;
  int? _lastSyncedCharOffset;

  /// 服务端同步最小间隔；期间仅在位置显著变化时才上报。
  static const _serverSyncMinInterval = Duration(seconds: 20);

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
                _serverSyncMinInterval ||
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

  /// 合并保存本地阅读进度，避免连续翻页或滚动触发并发写入。
  void scheduleLocalProgressSave({
    required double chapterProgress,
    required int charOffset,
    required String mode,
  }) {
    final snapshot = ReaderProgressSnapshot(
      chapterId: currentChapterId,
      charOffset: charOffset,
      progress: bookProgress,
      chapterProgress: chapterProgress,
      chapterTitle: cachedContent?.title ?? '',
      mode: mode,
      updatedAt: DateTime.now(),
    );
    progressSaveCoordinator.schedule(snapshot);
    noteOwnProgressSave(snapshot);
  }

  /// 从当前页面更新阅读进度。
  void updateProgressFromPage() {
    if (isPageMode) {
      final data = contentLoader?.get(currentChapterId, settings);
      if (data == null) return;
      final slice = contentLoader?.computePage(
        chapterId: currentChapterId,
        settings: settings,
        pageWidth: computePageWidth(),
        pageHeight: computePageHeight(),
        pageIndex: pageModePage,
        textScale: MediaQuery.textScalerOf(context).scale(1.0),
      );
      final charOffset = slice?.startCharOffset ?? 0;
      scrollProgress =
          data.totalChars > 0
              ? (charOffset / data.totalChars).clamp(0.0, 1.0)
              : 0.0;
      // 模式切换期间不覆盖 tracker — 保留冻结的精确锚点
      if (modeSwitchAnchor == null) {
        final chapterIdx =
            contentLoader?.allChapters.indexWhere(
              (c) => c.id == currentChapterId,
            ) ??
            0;
        positionTracker.updateFromPage(
          localPageIndex: pageModePage,
          totalPages: 10000,
          charOffset: charOffset,
          chapterId: currentChapterId,
          totalChapters: contentLoader?.allChapters.length ?? 0,
          currentChapterIndex: chapterIdx,
        );
      }
      return;
    }

    // 滚动模式：使用 flatPages
    final pages = flatPages as List;
    if (pages.isEmpty) return;
    final entry = pages[currentPageIndex.clamp(0, pages.length - 1)];
    final data = contentLoader?.get(entry.chapterId, settings);
    if (data == null) return;
    final chapterTotal = data.slices.length;
    scrollProgress =
        chapterTotal > 1
            ? (entry.localPageIndex / (chapterTotal - 1)).clamp(0.0, 1.0)
            : computeProgress();
    final slice =
        data.slices.isNotEmpty ? data.slices[entry.localPageIndex] : null;
    positionTracker.updateFromPage(
      localPageIndex: entry.localPageIndex,
      totalPages: chapterTotal,
      charOffset: slice?.startCharOffset ?? 0,
      chapterId: entry.chapterId,
      totalChapters: contentLoader?.allChapters.length ?? 0,
      currentChapterIndex: entry.chapterIndex,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 章节切换
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 尝试按偏移量切换章节。
  void tryNavigateChapter(int offset) {
    final chapters = contentLoader?.allChapters ?? [];
    final idx = chapters.indexWhere((c) => c.id == currentChapterId) + offset;
    if (idx < 0 || idx >= chapters.length) {
      final l10n = AppLocalizations.of(context);
      final msg =
          offset < 0
              ? l10n.readerAlreadyFirstChapter
              : l10n.readerAlreadyLastChapter;
      showReaderSnackBar(context, msg);
      return;
    }
    // 回退整章是跳转行为，提供"回到原进度"浮层；顺序前进保持干净
    final intent =
        offset < 0
            ? const ReaderChapterNavigationIntent.end(offerReturn: true)
            : const ReaderChapterNavigationIntent.start();
    unawaited(switchToChapter(chapters[idx].id, intent: intent));
  }

  /// 使用明确的进入位置切换章节。
  Future<void> switchToChapter(
    String chapterId, {
    ReaderChapterNavigationIntent intent =
        const ReaderChapterNavigationIntent.start(),
  }) async {
    if (isSwitchingChapter) return;

    final currentSnapshot = buildProgressSnapshot();
    if (intent.offerReturn && currentSnapshot != null) {
      returnToProgressSnapshot = currentSnapshot;
    }

    if (chapterId == currentChapterId) {
      final chapterData = contentLoader?.get(currentChapterId, settings);
      if (chapterData == null ||
          intent.entryPoint == ReaderChapterEntryPoint.resume) {
        return;
      }
      _applyChapterNavigationIntent(intent, currentChapterId, chapterData);
      if (mounted) setState(() {});
      return;
    }

    // 先锁定状态，再进行任何异步持久化，避免连点创建并发切换。
    isSwitchingChapter = true;
    clearReaderSelection();
    isLoadingChapter = false;
    loadGeneration++;
    chapterLoadCoordinator.cancel();
    pageLocator.cancel();
    chapterNavigationIntent = intent;

    if (isAnimating) {
      isAnimating = false;
    }

    if (currentSnapshot != null) {
      final syncGeneration = ++syncProgressGeneration;
      unawaited(
        syncProgressAsync(
          progressOverride: currentSnapshot.chapterProgress,
          chapterId: currentSnapshot.chapterId,
          charOffset: currentSnapshot.charOffset,
          generation: syncGeneration,
          force: true,
        ),
      );
    }

    final prefetchedContent = contentLoader?.contentFor(chapterId);
    currentChapterId = chapterId;
    cachedContent = prefetchedContent;
    lastLoadedChapterId = prefetchedContent == null ? null : chapterId;
    pendingChapterProgress = null;
    pendingRestoreCharOffset = null;
    pageModePage = 0;
    contentLoader?.setActive(chapterId);
    restore.cancel();
    isRestoringProgress = false;
    chapterLoadingTimer?.cancel();
    showChapterLoadingOverlay = false;
    if (prefetchedContent == null) {
      chapterLoadingTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted || !isSwitchingChapter) return;
        setState(() => showChapterLoadingOverlay = true);
      });
    }
    setState(() {
      scrollProgress = 0;
      isBookmarked = false;
    });
    checkBookmarkState();
  }

  /// 显示"返回原进度"浮动控件。
  void showReturnToProgressSnackBar() {
    if (!mounted) return;
    returnControlTimer?.cancel();
    setState(() => showReturnControl = true);

    returnControlTimer = Timer(const Duration(seconds: 3), () {
      hideReturnControl();
    });
  }

  /// 翻页/滚动时提前隐藏"返回原进度"控件。
  void dismissReturnSnackBar() {
    if (!showReturnControl) return;
    returnControlTimer?.cancel();
    returnControlTimer = null;
    dismissReturnTimer?.cancel();
    dismissReturnTimer = Timer(const Duration(seconds: 1), () {
      dismissReturnTimer = null;
      hideReturnControl();
    });
  }

  /// 隐藏"返回原进度"控件。
  void hideReturnControl() {
    if (!mounted) return;
    if (showReturnControl) {
      setState(() => showReturnControl = false);
    }
  }

  /// 返回切换章节前的原阅读位置。
  void returnToOriginalProgress() {
    final snapshot = returnToProgressSnapshot;
    if (snapshot == null) return;
    returnToProgressSnapshot = null;
    hideReturnControl();
    unawaited(
      switchToChapter(
        snapshot.chapterId,
        intent: ReaderChapterNavigationIntent.offset(snapshot.charOffset),
      ),
    );
  }
}
