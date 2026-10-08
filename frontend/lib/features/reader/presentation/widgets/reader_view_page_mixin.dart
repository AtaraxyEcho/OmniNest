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

  /// 本机最近一次推送的进度快照，供同章方向性守卫比较。
  ReaderProgressSnapshot? get lastOwnProgressSave;

  /// 当前章节清单版本，写入进度时随行落库。
  ///
  /// 服务端重解析会改变章节边界，版本号是唯一能证明旧偏移仍可比对的信号。
  int? get currentManifestVersion;

  /// 不依赖 ref 的清单版本缓存，dispose 路径构造快照时使用。
  int? get lastKnownManifestVersion;

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

  // ── 跨设备进度跳转提示 ──

  /// 被方向性守卫丢弃的同章远端进度，等待用户决定是否跳转。
  ReaderProgressSnapshot? get remoteProgressCandidate;
  set remoteProgressCandidate(ReaderProgressSnapshot? value);
  bool get showRemoteProgressCue;
  set showRemoteProgressCue(bool value);
  Timer? get remoteProgressTimer;
  set remoteProgressTimer(Timer? value);

  /// 已挂出过提示的候选进度时间戳，避免详情 provider 重建反复弹回。
  DateTime? get remoteProgressCueOfferedAt;
  set remoteProgressCueOfferedAt(DateTime? value);

  /// 判断回灌快照是否是本机刚写入进度的回声。
  bool isOwnProgressEcho(ReaderProgressSnapshot snapshot);

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

  /// 全书进度；null 表示清单或本章字符数尚不可用。
  double? get bookProgress;

  /// 最近一次已算出的全书进度，读取不依赖 ref。
  ///
  /// dispose 之后仍需要构造进度快照时使用：`bookProgress` 需要读
  /// parsedBookProvider，Element 已卸载时不可用。
  double? get lastKnownBookProgress;

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
  ///
  /// [force] 用于用户显式点按跳转提示：跳过回声与同章方向性守卫，
  /// 其余校验（章节归属、清单版本、数据就绪）仍然生效。
  void applyProgressSnapshot(
    ReaderProgressSnapshot snapshot, {
    bool force = false,
  }) {
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

    // 清单版本变化说明服务端重解析过章节：旧字符偏移落在新文本上是另一个
    // 位置，直接定位会跳到无关段落。降级为章首恢复，章节归属仍然有效。
    if (isProgressOffsetVersionMismatch(
      snapshotVersion: snapshot.manifestVersion,
      currentVersion: currentManifestVersion,
    )) {
      if (kDebugMode) {
        readerDebugLog(
          'ProgressRestore DEGRADE: manifest version '
          '${snapshot.manifestVersion} -> $currentManifestVersion, '
          'restore chapter start only',
        );
      }
      snapshot = snapshot.degradeToChapterStart();
    }

    // 同章方向性守卫：本机刚保存的进度经 provider 回灌会再次自动应用，
    // 恢复编排把用户拉回保存点（实机日志 charOffset=1011 被 767 拉回）。
    // 只丢弃不超前于本机已知位置的快照；跨设备更靠前的同章进度必须放行，
    // 否则续读只能靠章切换生效。
    final ownSaved = lastOwnProgressSave;
    if (!force &&
        isStaleSameChapterSnapshot(
          snapshotChapterId: snapshot.chapterId,
          snapshotCharOffset: snapshot.charOffset,
          trackedChapterId: positionTracker.chapterId,
          trackedCharOffset: positionTracker.charOffset,
          ownSavedChapterId: ownSaved?.chapterId,
          ownSavedCharOffset: ownSaved?.charOffset ?? 0,
        )) {
      // 丢弃是保守一侧，手动通道补回来：非自身回声且确实带位置的，
      // 给一次点按跳转的提示，由用户决定是否让本机回退。
      if (shouldOfferProgressJumpCue(
        isOwnEcho: isOwnProgressEcho(snapshot),
        snapshotCharOffset: snapshot.charOffset,
      )) {
        offerProgressJumpCue(snapshot);
      }
      if (kDebugMode) {
        readerDebugLog(
          'ProgressRestore SKIP: same-chapter stale snapshot '
          '(tracked=${positionTracker.charOffset}, '
          'saved=${ownSaved?.charOffset ?? 0}, '
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
      bookProgress: bookProgress,
      chapterProgress: chapterProgress,
      mode: isPageMode ? 'page' : 'scroll',
      chapterTitle: snapshotChapterTitle,
      manifestVersion: currentManifestVersion,
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
      bookProgress: bookProgress,
      chapterProgress: chapterProgress,
      chapterTitle: cachedContent?.title ?? '',
      mode: mode,
      manifestVersion: currentManifestVersion,
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
          // 懒分页不预知总页数：字符偏移口径与滚动模式一致
          //（此前调用方被要求传占位值 10000，进度恒等于 0）。
          charOffset: charOffset,
          chapterId: currentChapterId,
          totalChars: data.totalChars,
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
    // 跳转提示只对候选快照所属章节有效，切章后点按会跳错位置。
    hideProgressJumpCue();

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

  /// 挂出"其他设备停在本章 X%"的一次性跳转提示。
  ///
  /// 方向性守卫只会丢弃靠后的同章进度，其中非本机回声的部分确实来自
  /// 其它设备；不静默回跳，但也不能让用户无路可走。
  void offerProgressJumpCue(ReaderProgressSnapshot snapshot) {
    if (!mounted) return;
    if (showReturnControl) {
      // 两个控件共用同一条底部轨道，返回原进度优先占位。
      return;
    }
    final offeredAt = snapshot.updatedAt;
    if (offeredAt != null && offeredAt == remoteProgressCueOfferedAt) {
      // 同一份回灌在超时收起后不再挂出：详情 provider 每次重建都会重新
      // 走到这里，否则切换书架或刷新详情都会让提示重新出现。
      return;
    }
    remoteProgressTimer?.cancel();
    _updateState(() {
      remoteProgressCandidate = snapshot;
      showRemoteProgressCue = true;
      remoteProgressCueOfferedAt = offeredAt;
    });
    remoteProgressTimer = Timer(const Duration(seconds: 8), () {
      hideProgressJumpCue();
    });
  }

  /// 收起跳转提示。候选快照保留到点按或切章，避免同一份回灌反复挂出。
  void hideProgressJumpCue() {
    remoteProgressTimer?.cancel();
    remoteProgressTimer = null;
    if (!mounted) return;
    if (showRemoteProgressCue) {
      _updateState(() => showRemoteProgressCue = false);
    }
  }

  /// 用户点按提示：把被守卫丢弃的远端进度强制施加到本机。
  void jumpToRemoteProgress() {
    final candidate = remoteProgressCandidate;
    remoteProgressCandidate = null;
    hideProgressJumpCue();
    if (candidate == null) return;
    applyProgressSnapshot(candidate, force: true);
  }
}

/// 判定同章进度回灌是否为自身回声或旧副本。
///
/// 回声容差：服务端落库后回灌的 charOffset 与本机写入值一致或极接近，
/// 位置差在 64 字符内视为同一点。
const int progressEchoCharTolerance = 64;

/// 同章进度快照是否不超前于本机已知位置（因而应丢弃）。
///
/// 已知位置取「当前章的追踪值」与「本机最近写入的同章值」的较大者；
/// 两者都不属于快照所在章节时视为无记账，首载进度照常施加。
bool isStaleSameChapterSnapshot({
  required String snapshotChapterId,
  required int snapshotCharOffset,
  required String trackedChapterId,
  required int trackedCharOffset,
  required String? ownSavedChapterId,
  required int ownSavedCharOffset,
}) {
  var knownFloor = 0;
  if (trackedChapterId == snapshotChapterId && trackedCharOffset > knownFloor) {
    knownFloor = trackedCharOffset;
  }
  if (ownSavedChapterId == snapshotChapterId &&
      ownSavedCharOffset > knownFloor) {
    knownFloor = ownSavedCharOffset;
  }
  if (knownFloor <= 0) {
    return false;
  }
  return snapshotCharOffset <= knownFloor + progressEchoCharTolerance;
}

/// 进度快照的字符偏移是否已因清单重解析而失去口径。
///
/// 任一版本未知时不降级：历史进度行没有版本列，把 null 当成不一致会让
/// 全部老用户的精确定位一次性失效，只剩章首恢复。
bool isProgressOffsetVersionMismatch({
  required int? snapshotVersion,
  required int? currentVersion,
}) {
  if (snapshotVersion == null || currentVersion == null) {
    return false;
  }
  return snapshotVersion != currentVersion;
}

/// 同章靠后进度被丢弃后，是否挂出手动跳转提示。
///
/// 自身回声不能提示：那是本机刚写入的位置，文案会谎称其他设备，且每轮
/// 滚动都可能重新弹出。章首降级副本没有可跳转的偏移，同样不提示。
bool shouldOfferProgressJumpCue({
  required bool isOwnEcho,
  required int snapshotCharOffset,
}) {
  return !isOwnEcho && snapshotCharOffset > 0;
}
