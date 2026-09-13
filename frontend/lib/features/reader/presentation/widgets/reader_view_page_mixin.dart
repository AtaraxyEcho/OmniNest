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
import 'package:omninest/features/reader/presentation/widgets/reader_cover_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_block_text.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_navigation_token.dart';
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
  ReaderContinuousScrollController get continuousScrollController;
  ScrollRestore get restore;
  ReaderViewSettings get settings;
  set settings(ReaderViewSettings value);
  String get currentChapterId;
  set currentChapterId(String value);
  ReaderChapterContent? get cachedContent;
  set cachedContent(ReaderChapterContent? value);
  ReaderAnnotationHandler? get annotationHandler;

  // ── 渲染状态 ──

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

  /// 章节加载/切换完成后立即重算全书进度一次（切章期间防抖重算被挂起）。
  void refreshBookProgressNow();
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

  /// 最近一次滚动活动时间（滚轮/触控板），供补偿与进度守卫共用。
  DateTime? get lastScrollActivityAt;
  set lastScrollActivityAt(DateTime? value);

  /// 指针是否按住未松开（State 维护，Listener 的 Up/Cancel 复位）。
  bool get pointerDownActive;
  set pointerDownActive(bool value);

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

  /// 当前锚点章纯文本。
  ///
  /// 连续滚动切章后页面持有的 HTML 可能过期或已被 dropHtml，
  /// 优先从已解析 blocks 提取，保证搜索/TTS 与可见正文一致。
  String currentChapterPlainText() {
    final data = contentLoader?.getByChapterId(currentChapterId);
    if (data == null || data.blocks.isEmpty) {
      return '';
    }
    return plainTextFromBlocks(data.blocks);
  }

  double get bookProgress;

  /// 按 [chapterId] + [charOffset] 计算全书加权进度（由 State 实现）。
  double bookProgressFor(String chapterId, int charOffset);

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
  void rebuildContinuousWindow();
  void invalidateContinuousWindowFingerprint();

  // ── 由 State 实现的抽象方法 ──

  /// 由 State 实现的抽象方法。
  void clearReaderSelection();

  // ── 常量 ──

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 内容加载
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 初始化内容加载器（仅首次）。
  void initContentLoader(List<ReaderChapter> chapters) {
    if (contentLoader != null) return;
    final loader = ReaderContentLoader(allChapters: chapters);
    loader.onLayoutInvalidated = _onContinuousLayoutInvalidated;
    contentLoader = loader;
  }

  bool _layoutInvalidationScheduled = false;
  Timer? _layoutInvalidationTimer;

  /// 测高收敛后刷新连续滚动窗口 fingerprint，避免热路径跳过更新。
  ///
  /// 合并到约 100ms 一拍，降低大章分批测高时的整页 setState 频率。
  void _onContinuousLayoutInvalidated() {
    if (!mounted || isPageMode || _layoutInvalidationScheduled) {
      return;
    }
    _layoutInvalidationScheduled = true;
    _layoutInvalidationTimer = Timer(const Duration(milliseconds: 100), () {
      _layoutInvalidationScheduled = false;
      if (!mounted || isPageMode) {
        return;
      }
      invalidateContinuousWindowFingerprint();
      rebuildContinuousWindow();
      setState(() {});
    });
  }

  /// 释放布局失效合并 Timer。
  void disposeLayoutInvalidationTimer() {
    _layoutInvalidationTimer?.cancel();
    _layoutInvalidationTimer = null;
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
      // 页模式全局索引由 ReaderPageFlow 维护；滚动模式进度走 continuous 位置。
      currentPageIndex = 0;

      final snapshot = await progressFuture;
      if (!_isCurrentChapterRequest(requestedChapterId, generation)) return;

      // 跨设备：最新进度在其他章节（resume 语义下），转整章切换而非丢弃。
      // 仅开书首次加载允许（见 loadLocalProgress 的 defer 收紧）。
      if (snapshot != null &&
          snapshot.chapterId.isNotEmpty &&
          snapshot.chapterId != requestedChapterId) {
        _hasCompletedInitialChapterLoad = true;
        chapterNavigationIntent = const ReaderChapterNavigationIntent.resume();
        chapterLoadingTimer?.cancel();
        showChapterLoadingOverlay = false;
        isSwitchingChapter = false;
        isLoadingChapter = false;
        refreshBookProgressNow();
        if (mounted) setState(() {});
        unawaited(
          switchToChapter(
            snapshot.chapterId,
            intent: ReaderChapterNavigationIntent.offset(snapshot.charOffset),
          ),
        );
        return;
      }

      if (navigationIntent.entryPoint == ReaderChapterEntryPoint.resume &&
          snapshot != null &&
          (snapshot.chapterId.isEmpty ||
              snapshot.chapterId == requestedChapterId)) {
        applyProgressSnapshot(snapshot);
      } else {
        _applyChapterNavigationIntent(
          navigationIntent,
          requestedChapterId,
          chapterData,
        );
      }

      _hasCompletedInitialChapterLoad = true;
      chapterNavigationIntent = const ReaderChapterNavigationIntent.resume();
      chapterLoadingTimer?.cancel();
      showChapterLoadingOverlay = false;
      isSwitchingChapter = false;
      isLoadingChapter = false;
      refreshBookProgressNow();
      if (mounted) setState(() {});
      _maybeSkipCoverChapter(chapterData);
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: loadCurrentChapter failed: $e');
      }
      if (_isCurrentChapterRequest(requestedChapterId, generation)) {
        isRestoringProgress = false;
        restore.cancel();
      }
    } finally {
      // 代次未变时必须复位 loading：章节 id 被连续滚动 adopt 改写后
      // 若仍用 _isCurrentChapterRequest 判断会漏清，导致滚动/侧点永久卡死。
      if (mounted && generation == loadGeneration) {
        chapterLoadingTimer?.cancel();
        showChapterLoadingOverlay = false;
        isSwitchingChapter = false;
        isLoadingChapter = false;
        refreshBookProgressNow();
        setState(() {});
      }
    }
  }

  bool _isCurrentChapterRequest(String chapterId, int generation) {
    return mounted &&
        generation == loadGeneration &&
        chapterId == currentChapterId;
  }

  /// 封面/书讯章开书跳过。
  ///
  /// 仅在「resume 且无任何进度快照」的首次开书时启用；
  /// 目录/显式导航进入封面章时必须允许停留。
  void _maybeSkipCoverChapter(ChapterData chapterData) {
    if (!mounted || isLoadingChapter || isSwitchingChapter) {
      return;
    }
    // 有真实恢复位置时不跳过；零进度恢复已提前返回，不会挡到这里。
    if (isRestoringProgress || pendingRestoreCharOffset != null) {
      return;
    }
    // 显式导航（start/end/anchor）不跳过。
    if (chapterNavigationIntent.entryPoint != ReaderChapterEntryPoint.resume) {
      return;
    }
    final chapters = contentLoader?.allChapters ?? const <ReaderChapter>[];
    if (chapters.length < 2) {
      return;
    }
    final idx = chapters.indexWhere((c) => c.id == currentChapterId);
    if (idx < 0 || idx >= chapters.length - 1) {
      return;
    }
    final totalChars = chapterData.totalChars;
    // 空章或封面型短章：顺序开书时自动前进到下一章。
    final isCoverLike =
        totalChars <= 0 ||
        isCoverLikeChapter(totalChars: totalChars, blocks: chapterData.blocks);
    if (!isCoverLike) {
      return;
    }
    if (positionTracker.charOffset > 0 || scrollProgress > 0) {
      return;
    }
    if (kDebugMode) {
      readerDebugLog(
        'ReaderView: skip cover/empty chapter $currentChapterId '
        '(totalChars=$totalChars) → ${chapters[idx + 1].id}',
      );
    }
    unawaited(switchToChapter(chapters[idx + 1].id));
  }

  /// 按导航意图推断显式导航来源。
  ReaderNavigationSource _navigationSourceOf(
    ReaderChapterNavigationIntent intent,
  ) {
    return switch (intent.entryPoint) {
      ReaderChapterEntryPoint.start ||
      ReaderChapterEntryPoint.end => ReaderNavigationSource.chapterStep,
      ReaderChapterEntryPoint.offset => ReaderNavigationSource.progressSeek,
      ReaderChapterEntryPoint.anchor => ReaderNavigationSource.anchorJump,
      ReaderChapterEntryPoint.resume => ReaderNavigationSource.returnToProgress,
    };
  }

  /// 章节身份提交的唯一入口（位置状态收口）。
  ///
  /// 收养解析出的新章在此一次性提交：改写章节身份、释放在途加载、
  /// 预取邻章并同步缓存。调用方负责先完成就绪判定，拒绝收养时不得
  /// 调用本方法。显式跳章的完整提交流程仍由 switchToChapter 状态机执行。
  void commitChapterAdoption(String chapterId) {
    currentChapterId = chapterId;
    // 收养改写章节身份后，在途的旧章内容加载即使完成也不再被消费；
    // 立即释放协调器，避免 isLoading 残留把翻页输入闸门锁死。
    chapterLoadCoordinator.cancel();
    final needFetch = contentLoader?.setActive(chapterId) ?? const [];
    for (final id in needFetch) {
      unawaited(prefetchChapter(id));
    }
    // blocks 与 HTML 均就绪时同步加载标记：避免 build 后
    // loadChapterContentIfNeeded 对锚点章冗余重取正文。
    final content = contentLoader?.contentFor(chapterId);
    if (contentLoader?.getByChapterId(chapterId) != null && content != null) {
      cachedContent = content;
      lastLoadedChapterId = chapterId;
    }
    // 收养可能来自滚动回调或 jumpToPage 的 layout 回调，禁止同步 setState。
    if (mounted) {
      _scheduleAdoptRebuild();
    }
  }

  /// 翻页模式：跨章页流中软收养章节。
  ///
  /// 不走 switchToChapter 硬切、不展示全屏遮罩；正文已就绪时首帧即可续读。
  /// [localPageIndex] 仅用于预热；全局页索引由 builders 在流内换算。
  void adoptPageModeChapter(String chapterId, {int localPageIndex = 0}) {
    if (chapterId == currentChapterId) {
      return;
    }
    if (isLoadingChapter || isSwitchingChapter) {
      final ready = contentLoader?.getByChapterId(chapterId) != null;
      if (!ready) {
        return;
      }
    }
    commitChapterAdoption(chapterId);
    unawaited(checkBookmarkState());
  }

  bool _adoptRebuildScheduled = false;

  /// 开书首次章节加载是否已完成；跨设备跨章 defer 仅允许发生在该加载上。
  bool _hasCompletedInitialChapterLoad = false;

  void _scheduleAdoptRebuild() {
    if (_adoptRebuildScheduled) return;
    _adoptRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adoptRebuildScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
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
      if (isPageMode) {
        // 章首 = 跨章流内锚点章起始全局索引；0 可能是前缀章页面，禁止直写。
        anchorPageModeToChapterStart(chapterId);
        isRestoringProgress = false;
        scrollProgress = 0;
      } else {
        // 连续滚动：章首是窗口坐标（前有前缀章），必须走稳定重试恢复，
        // 且恢复期间抑制位置回调防止锚点被误收养回前章。
        restoreToChapterStart(chapterId);
      }
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

  /// 翻页模式接近章末时预取下章前几页。
  ///
  /// 跨章页流下章冷启动需逐页 TextPainter 测量；
  /// 提前把下章前 5 页算入 PageNavigator，翻到边界时首帧即可渲染。
  void prefetchNextChapterAtBoundary(int pageIndex) {
    final loader = contentLoader;
    if (!isPageMode || loader == null || !mounted) return;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final pageWidth = computePageWidth();
    final pageHeight = computePageHeight();
    final data = loader.get(currentChapterId, settings);
    if (data == null) return;
    final navigator = data.getOrCreatePageNavigator(
      pageWidth,
      pageHeight,
      settings,
      textScale: textScale,
    );
    // 未分页完成时总数未知，宁早勿晚；完成后限末 5 页触发。
    if (navigator.isFullyPaginated &&
        pageIndex < navigator.readablePageCount - 5) {
      return;
    }
    final chapters = loader.allChapters;
    final idx = chapters.indexWhere((c) => c.id == currentChapterId);
    if (idx < 0 || idx + 1 >= chapters.length) return;
    final nextId = chapters[idx + 1].id;
    unawaited(warmChapterPages(nextId, pageCount: 5));
  }

  /// 预取章节正文并预热前 N 页分页，供跨章页流立即渲染。
  Future<void> warmChapterPages(String chapterId, {int pageCount = 5}) async {
    final loader = contentLoader;
    if (!mounted || loader == null) return;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final pageWidth = computePageWidth();
    final pageHeight = computePageHeight();
    if (loader.get(chapterId, settings) == null) {
      await prefetchChapter(chapterId);
      if (!mounted || contentLoader == null) return;
    }
    for (var page = 0; page < pageCount; page++) {
      if (!mounted || contentLoader == null) return;
      contentLoader!.computePage(
        chapterId: chapterId,
        settings: settings,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        pageIndex: page,
        textScale: textScale,
      );
    }
    if (mounted && isPageMode) {
      requestReaderRebuild();
    }
  }

  /// 调度阅读器重建（由 builders 实现）。
  void requestReaderRebuild();

  /// 清空跨章收养待映射页（由 builders 实现）。
  void clearPendingPageLocalIndex();

  /// 翻页流锚定目标章起始（由 builders 实现）：写入待映射章内页 0 并
  /// 在流内直接换算全局索引。
  void anchorPageModeToChapterStart(String chapterId);

  /// 显式导航令牌持有者（由 State 实现）：新导航使旧令牌失效。
  ReaderNavigationTokenHolder get navigationTokens;

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
      } else if (mounted) {
        // 章节已被切走或收养改写：结果不再被消费，必须释放协调器，
        // 否则 _loadingChapterId 残留把 PagedState.isPaginating 永久锁真，
        // 翻页点击热区/底栏/拖动全部无响应。
        chapterLoadCoordinator.releaseIfCurrent(
          requestGeneration,
          requestedChapterId,
        );
        // 正文已在手：按预取语义解析进 loader，不浪费这次 IO——
        // 目标章仍在缓存半径内时，blocks 随后即会被用到。
        if (content != null && _isWithinCacheRadius(requestedChapterId)) {
          unawaited(prefetchChapter(requestedChapterId));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('ReaderView: chapter content load failed: $e');
      }
      if (mounted) {
        if (chapterLoadCoordinator.isCurrent(
              requestGeneration,
              requestedChapterId,
            ) &&
            requestedChapterId == currentChapterId) {
          chapterLoadCoordinator.fail(requestGeneration, requestedChapterId);
          isSwitchingChapter = false;
          isRestoringProgress = false;
        } else {
          chapterLoadCoordinator.releaseIfCurrent(
            requestGeneration,
            requestedChapterId,
          );
        }
        setState(() {});
      }
    }
  }

  /// 章节是否仍在当前活动章的缓存半径内（与 loader 驱逐策略一致）。
  bool _isWithinCacheRadius(String chapterId) {
    final loader = contentLoader;
    if (loader == null) {
      return false;
    }
    final all = loader.allChapters;
    final activeIdx = all.indexWhere((c) => c.id == currentChapterId);
    final idx = all.indexWhere((c) => c.id == chapterId);
    return activeIdx >= 0 &&
        idx >= 0 &&
        (idx - activeIdx).abs() <= kContinuousCacheRadius;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 进度恢复与保存
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 加载本地+服务端+路由进度，返回最新的快照。
  ///
  /// 跨设备语义：先按 updatedAt 取全局最新；若最新进度在其他章节，仍
  /// 返回该快照（调用方据此转整章切换），不得按当前章过滤丢弃。
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

    final globalLatest = ReaderProgressSnapshot.latest(
      ReaderProgressSnapshot.latest(routeSnapshot, localSnapshot),
      serverSnapshot,
    );
    if (globalLatest != null &&
        globalLatest.hasReadableProgress &&
        globalLatest.chapterId.isNotEmpty &&
        globalLatest.chapterId != chapterId) {
      // 跨章 defer 仅限开书首次加载：显式跳章/收养后的 resume 加载不得被
      // 「全局最新在别章」劫持——该最新值可能是切换期产生的脏快照，会把
      // 用户拽离刚到达的目标章（目录高亮与阅读位置错位的根因）。
      if (_hasCompletedInitialChapterLoad) {
        if (kDebugMode) {
          readerDebugLog(
            'ProgressLoad: global latest on other chapter '
            '(${globalLatest.chapterId}) suppressed after initial load',
          );
        }
      } else {
        if (kDebugMode) {
          readerDebugLog(
            'ProgressLoad: global latest on other chapter '
            '(${globalLatest.chapterId}), deferring to chapter switch',
          );
        }
        return globalLatest;
      }
    }

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

    // 零进度快照无需恢复：避免 isRestoringProgress 挡住封面/空章跳过，
    // 也避免 ScrollRestore 在 maxScrollExtent 尚未就绪时超时。
    final isZeroProgress =
        snapshot.charOffset <= 0 &&
        snapshot.chapterProgress <= 0 &&
        snapshot.progress <= 0;
    if (isZeroProgress) {
      if (kDebugMode) {
        readerDebugLog('ProgressRestore SKIP: zero progress snapshot');
      }
      lastAppliedProgressAt = snapshot.updatedAt ?? DateTime.now();
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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 连续滚动窗口坐标换算（统一入口，实现见 ReaderViewPageCoordinateMixin）
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 窗口绝对 contentY（滚动 offset + viewportAnchorY）→ 章内 charOffset。
  int windowContentYToCharOffset(String chapterId, double windowContentY);

  /// 章首在窗口中的滚动 offset（章头贴视口顶）。
  double chapterStartScrollOffset(String chapterId);

  /// 滚动模式：稳定恢复到章首；恢复期抑制位置回调防锚点误收养。
  void restoreToChapterStart(String chapterId);

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
    var snapshotChapterId = chapterId ?? currentChapterId;
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
      final data = contentLoader?.getByChapterId(snapshotChapterId);
      final windowUsable =
          data != null &&
          data.cumulativeHeights.isNotEmpty &&
          continuousScrollController.entryFor(snapshotChapterId) != null;
      if (windowUsable) {
        // 连续滚动：滚动 offset 是窗口绝对坐标，必须走统一换算扣前缀。
        effectiveCharOffset =
            contentLoader == null
                ? positionTracker.charOffset
                : windowContentYToCharOffset(
                  snapshotChapterId,
                  scrollController.offset + viewportAnchorY,
                );
      } else {
        // 章节数据未就绪或不在当前窗口（跳章未落定/收养竞态）：窗口坐标
        // 对该章不可解释。退回 tracker 的自洽位置并同步修正章节身份，
        // 避免把旧章偏移算进新章（totalChars=0 时还会把 chapterProgress
        // 退化成 scrollProgress 兜底值落库，产生脏进度）。
        final trackedChapterId = positionTracker.chapterId;
        if (trackedChapterId.isNotEmpty) {
          snapshotChapterId = trackedChapterId;
        }
        effectiveCharOffset = positionTracker.charOffset;
      }
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
    // 零进度不落盘：封面跳过/开书瞬间的 (0,0) 会污染“全局最新进度”。
    if (charOffset <= 0 && chapterProgress <= 0 && bookProgress <= 0) {
      return;
    }
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
      final chapterId = currentChapterId;
      final data = contentLoader?.get(chapterId, settings);
      if (data == null) return;
      // pageModePage 为跨章流全局索引，computePageCharOffset 内部已解析。
      final charOffset = computePageCharOffset(pageModePage);
      scrollProgress =
          data.totalChars > 0
              ? (charOffset / data.totalChars).clamp(0.0, 1.0)
              : 0.0;
      // 模式切换期间不覆盖 tracker — 保留冻结的精确锚点
      if (modeSwitchAnchor == null) {
        final chapterIdx =
            contentLoader?.allChapters.indexWhere((c) => c.id == chapterId) ??
            0;
        positionTracker.updateFromPage(
          localPageIndex: 0,
          totalPages: 10000,
          charOffset: charOffset,
          chapterId: chapterId,
          totalChapters: contentLoader?.allChapters.length ?? 0,
          currentChapterIndex: chapterIdx,
        );
      }
      return;
    }

    // 滚动模式进度由 continuous 位置回调维护；此处不依赖 flatPages。
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

  /// 离场快照：滚动模式以 tracker 为事实源。
  ///
  /// currentChapterId 可能已被上一次跳章改写而窗口/滚动位置尚未跟上
  /// （滑窗补偿在切换期被抑制），此时按窗口坐标换算会把旧 offset 解释成
  /// 新章的虚假进度并 force 落库；tracker 的章节身份与偏移成对更新，
  /// 以其章节身份为准。翻页模式页流自带章节归属，仍走 buildProgressSnapshot。
  ReaderProgressSnapshot? buildDepartureSnapshot() {
    if (isPageMode) {
      return buildProgressSnapshot();
    }
    final trackedChapterId = positionTracker.chapterId;
    final chapterId =
        trackedChapterId.isEmpty ? currentChapterId : trackedChapterId;
    final charOffset = positionTracker.charOffset;
    final totalChars =
        contentLoader?.getByChapterId(chapterId)?.totalChars ?? 0;
    final chapterProgress =
        totalChars > 0 ? (charOffset / totalChars).clamp(0.0, 1.0) : 0.0;
    final progress = bookProgressFor(chapterId, charOffset);
    if (kDebugMode) {
      readerDebugLog(
        'ProgressSnapshot DEPARTURE: chapter=$chapterId, '
        'charOffset=$charOffset, chapterProgress=$chapterProgress',
      );
    }
    if (charOffset <= 0 && chapterProgress <= 0 && progress <= 0) {
      return null;
    }
    return ReaderProgressSnapshot(
      chapterId: chapterId,
      charOffset: charOffset,
      progress: progress,
      chapterProgress: chapterProgress,
      chapterTitle:
          contentLoader?.getByChapterId(chapterId)?.content.title ??
          cachedContent?.title ??
          '',
      mode: 'scroll',
      updatedAt: DateTime.now(),
    );
  }

  /// 使用明确的进入位置切换章节。
  Future<void> switchToChapter(
    String chapterId, {
    ReaderChapterNavigationIntent intent =
        const ReaderChapterNavigationIntent.start(),
  }) async {
    if (isSwitchingChapter) {
      // 切换未完成时再次触发（目录/上一章下一章连点）：给出反馈而非静默吞掉。
      if (chapterId != currentChapterId && mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerChapterSwitching,
        );
      }
      return;
    }

    // 显式导航开始：创建新令牌并使旧令牌失效；收养与预取不创建令牌。
    navigationTokens.begin(
      source: _navigationSourceOf(intent),
      targetChapterId: chapterId,
    );

    final currentSnapshot = buildDepartureSnapshot();
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

    if (currentSnapshot != null && currentSnapshot.hasReadableProgress) {
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
    final hasBlocks =
        contentLoader?.getByChapterId(chapterId)?.blocks.isNotEmpty ?? false;
    currentChapterId = chapterId;
    cachedContent = prefetchedContent;
    lastLoadedChapterId = prefetchedContent == null ? null : chapterId;
    pendingChapterProgress = null;
    pendingRestoreCharOffset = null;
    if (isPageMode) {
      // 显式跳章：以待映射章内页 0 锚定目标章起始全局索引，禁止旧流
      // 身份重映射（邻章场景重映射会把跳转拉回旧章）。
      anchorPageModeToChapterStart(chapterId);
    } else {
      clearPendingPageLocalIndex();
    }
    contentLoader?.setActive(chapterId);
    restore.cancel();
    isRestoringProgress = false;
    chapterLoadingTimer?.cancel();
    showChapterLoadingOverlay = false;
    // 已有 blocks 时不要全屏遮罩：连续滚动可直接用块渲染。
    if (prefetchedContent == null && !hasBlocks) {
      chapterLoadingTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted || !isSwitchingChapter) return;
        setState(() => showChapterLoadingOverlay = true);
      });
    }
    // 不在此处重置 scrollProgress：进度值由导航意图/进度快照在加载完成后
    // 一次写入，避免先闪 0 再跳目标的中间态。
    setState(() {
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
