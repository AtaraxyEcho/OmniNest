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

part 'reader_view_page_mixin_load.dart';
part 'reader_view_page_mixin_progress.dart';
part 'reader_view_page_mixin_return.dart';

/// reader_view_page.dart 的业务逻辑 mixin。
///
/// 提取所有非 build、非 lifecycle 方法，降低主文件行数。
/// 通过抽象 getter/setter 访问 State 字段，与 ReaderViewPageBuilders 分离。
mixin ReaderViewPageMixin on ConsumerState<ReaderViewPage> {
  /// 扩展方法使用的状态更新入口：mounted 检查后调用 setState。
  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }
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
  ReaderProgressSnapshot? get initialProgress;

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

  void clearReaderSelection();

  /// 将音量键翻页开关同步到平台层。
  void syncVolumeKeyPaging();

  // ── 进度同步节流字段 ──

  DateTime? _lastServerSyncAt;
  double? _lastSyncedProgress;
  String? _lastSyncedChapterId;
  int? _lastSyncedCharOffset;

  /// 服务端同步最小间隔；期间仅在位置显著变化时才上报。
  static const _serverSyncMinInterval = Duration(seconds: 20);

  /// 翻页模式接近章末时预取下章前几页。
  ///
  /// 章末切换走 switchToChapter，下章冷启动需逐页 TextPainter 测量；
  /// 提前把下章前 3 页算入 PageNavigator，切换后首帧即可渲染。
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
    // 未分页完成时总数未知，宁早勿晚；完成后限末 3 页触发。
    if (navigator.isFullyPaginated &&
        pageIndex < navigator.readablePageCount - 3) {
      return;
    }
    final chapters = loader.allChapters;
    final idx = chapters.indexWhere((c) => c.id == currentChapterId);
    if (idx < 0 || idx + 1 >= chapters.length) return;
    final nextId = chapters[idx + 1].id;
    unawaited(() async {
      if (contentLoader?.get(nextId, settings) == null) {
        await prefetchChapter(nextId);
        if (!mounted || contentLoader == null) return;
      }
      for (var page = 0; page < 3; page++) {
        contentLoader!.computePage(
          chapterId: nextId,
          settings: settings,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          pageIndex: page,
          textScale: textScale,
        );
      }
    }());
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

    // 同章回灌守卫：本机刚保存的进度经 provider 回灌会再次自动应用，
    // 恢复编排把用户拉回保存点（实机日志 charOffset=1011 被 767 拉回）。
    // 同章以本机记账为准；开书首载记账为空（chapterId 空串）不受影响。
    if (positionTracker.chapterId == snapshot.chapterId &&
        positionTracker.charOffset > 0) {
      if (kDebugMode) {
        readerDebugLog(
          'ProgressRestore SKIP: same-chapter echo '
          '(tracked=${positionTracker.charOffset}, '
          'snapshot=${snapshot.charOffset})',
        );
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
    // 旧章的恢复目标与模式切换锚点不得泄漏进新章：
    // restoreTargetCharOffset 残留会让新章前段的进度写入被防回退
    // 守卫静默吞掉；modeSwitchAnchor 残留会把旧章偏移记进新章快照。
    restoreTargetCharOffset = 0;
    modeSwitchAnchor = null;
    modeSwitchInProgress = false;
    pageModePage = 0;
    // 旧章记账必须随章节切换失效：tracker 残留旧章偏移会把模式切换
    // 锚点、进度快照回退指到新章错误位置，且恢复落定会把失效值记入新章。
    positionTracker.setCharOffset(0, chapterId);
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
    // 不在此处重置 scrollProgress：进度值由导航意图/进度快照在加载完成后
    // 一次写入，避免先闪 0 再跳目标的中间态。
    setState(() {
      isBookmarked = false;
    });
    checkBookmarkState();
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
