import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/reader/application/reader_comic_image_provider.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:omninest/features/reader/application/reader_session_recorder.dart';
import 'package:omninest/features/reader/domain/comic_anchor.dart';
import 'package:omninest/features/reader/domain/comic_layout_index.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_navigation.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_page_image.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_overlays.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_comfort_filter.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcuts.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_tap_detector.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/platform/android/reader_volume_key_service.dart';

part 'comic_reader_view_sections.dart';

/// 漫画阅读模式：支持 Book 3D 仿真翻页、Swipe 水平滑动、Scroll 竖向卷轴。
enum ComicReadingMode {
  /// Book 3D 仿真翻页。
  book,

  /// Swipe 水平滑动翻页。
  page,

  /// Scroll 竖向连续滚动。
  scroll,
}

/// 漫画阅读器视图。
///
/// 支持 Book 3D 翻页、Swipe 滑动、Scroll 卷轴三模式，单/双页跨页、RTL 日漫方向、
/// 每页独立缩放（放大 > 1.02 自动锁翻页拖拽）与漫画书签管理。
class ComicReaderView extends ConsumerStatefulWidget {
  const ComicReaderView({
    required this.itemId,
    required this.manifest,
    required this.onBack,
    this.bookTitle,
    this.initialPageIndex = 0,
    this.initialIntraPageOffset,
    super.key,
  });

  /// 阅读条目 ID。
  final String itemId;

  /// 漫画清单。
  final ComicManifest manifest;

  /// 退出阅读器并返回条目详情页。
  final VoidCallback onBack;

  /// 漫画正式书名（`item.title`）；缺省时从 `readerItemDetailProvider` 或目录回退。
  final String? bookTitle;

  /// 初始页码索引。
  final int initialPageIndex;

  /// 初始页内偏移（滚动模式恢复用，0.0-1.0）。
  final double? initialIntraPageOffset;

  @override
  ConsumerState<ComicReaderView> createState() => ComicReaderViewState();
}

class ComicReaderViewState extends ConsumerState<ComicReaderView>
    with WidgetsBindingObserver {
  final ReaderPageTurnController _pageTurnController =
      ReaderPageTurnController();
  late ScrollController _scrollController;
  late ComicLayoutIndex _layoutIndex;

  /// 每页/每对页独立缩放控制器：离屏自动复位 1.0x，彻底消除缩放串页。
  final Map<int, TransformationController> _slotTransformControllers = {};
  Offset? _lastDoubleTapLocalPosition;
  double _currentZoomScale = 1.0;

  double get currentZoomScale => _currentZoomScale;

  void zoomIn() => _zoomByStep(0.25);

  void zoomOut() => _zoomByStep(-0.25);

  void resetZoom() => _resetCurrentSlotZoom();

  /// 当前阅读锚点（统一真相源）。
  ComicAnchor _anchor = const ComicAnchor(pageId: '', pageIndex: 0);

  bool _showControls = true;
  late ComicReadingMode _readingMode;
  late ComicReaderDisplaySettings _displaySettings;
  ReaderViewSettings _settings = ReaderViewSettings();
  Timer? _hideControlsTimer;
  Timer? _scrollSaveTimer;
  Timer? _displaySettingsSaveTimer;
  ComicReaderDisplaySettings? _pendingDisplaySettings;
  bool _pendingInitialScrollRestore = false;
  int _initialScrollRestoreAttempts = 0;
  DateTime? _initialRestoreDeadline;
  bool _suppressScrollProgress = false;
  ComicAnchor? _pendingScrollRestoreAnchor;
  bool _scrollRestoreScheduled = false;
  bool _exitRequested = false;
  bool _progressFlushedForExit = false;
  late ReaderProgressSyncService _progressSync;
  final ReaderPanelCoordinator _panelCoordinator = ReaderPanelCoordinator();
  final ReaderCommandGate _commandGate = ReaderCommandGate();
  VoidCallback? _volumeKeyEventCancel;
  bool _volumeKeyPagingPushed = false;

  /// 会话记账：只累计前台活跃时长，切后台挂机不计入阅读统计。
  final DateTime _sessionStart = DateTime.now();
  Duration _accumulatedActive = Duration.zero;
  DateTime? _lastResumedAt;
  bool _sessionRecorded = false;

  ComicManifest get _manifest => widget.manifest;
  List<ComicPage> get _pages => _manifest.pages;
  int get _totalPages => _pages.length;
  bool get _isRtl =>
      _displaySettings.rtlOverride ??
      (_manifest.readingDirection?.toLowerCase() == 'rtl');
  bool get _isPagedMode => _readingMode != ComicReadingMode.scroll;
  bool get _imageZoomed =>
      _readingMode == ComicReadingMode.page && _currentZoomScale > 1.02;

  /// 统一桌面阅读器视觉设置：不再强制纯黑，根据当前模式同步 Book 书桌色或主题纸面色。
  ReaderViewSettings get _controlSettings => _settings.copyWith(
    readingMode: _readingMode == ComicReadingMode.scroll ? 'scroll' : 'page',
    pageTurnMode: _readingMode == ComicReadingMode.book ? 'cover' : 'slide',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastResumedAt = DateTime.now();
    _progressSync = ref.read(readerProgressSyncServiceProvider);
    final defaultMode = kIsWeb ? 'scroll' : 'page';
    _displaySettings = ComicReaderDisplaySettings(readingMode: defaultMode);
    _readingMode = _modeFromName(defaultMode);
    _layoutIndex = ComicLayoutIndex(_pages, contentWidth: 800.0);
    final initialPage =
        _totalPages <= 0
            ? 0
            : widget.initialPageIndex.clamp(0, _totalPages - 1).toInt();
    _anchor = ComicAnchor(
      pageId: initialPage < _pages.length ? _pages[initialPage].id : '',
      pageIndex: initialPage,
      pageFingerprint:
          initialPage < _pages.length ? _pages[initialPage].fingerprint : null,
      sourceId:
          initialPage < _pages.length ? _pages[initialPage].sourceId : null,
      sourcePageIndex:
          initialPage < _pages.length
              ? _pages[initialPage].sourcePageIndex
              : null,
      catalogKey:
          initialPage < _pages.length ? _pages[initialPage].catalogKey : null,
      intraPageOffset: widget.initialIntraPageOffset ?? 0.0,
      manifestVersion: _manifest.manifestVersion,
    );
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _volumeKeyEventCancel = ReaderVolumeKeyService.instance().addListener(
      _handleVolumeKeyEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _preloadAdjacent();
      }
    });
    unawaited(
      _loadSettings().then((_) {
        if (mounted) _syncVolumeKeyPaging();
      }),
    );
  }

  /// 退出前等待进度落库与服务端同步完成，彻底消除详情页刷新竞态。
  Future<void> flushReadingProgress() async {
    if (_progressFlushedForExit) {
      return;
    }
    _progressFlushedForExit = true;
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = null;
    await _persistProgress(force: true);
  }

  @override
  void deactivate() {
    _displaySettingsSaveTimer?.cancel();
    _displaySettingsSaveTimer = null;
    final pending = _pendingDisplaySettings;
    if (pending != null) {
      _pendingDisplaySettings = null;
      unawaited(_saveDisplaySettings(pending));
    }
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastResumedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.paused) {
      return;
    }
    final resumedAt = _lastResumedAt;
    if (resumedAt != null) {
      _accumulatedActive += DateTime.now().difference(resumedAt);
      _lastResumedAt = null;
    }
  }

  void _recordSession() {
    if (_sessionRecorded) {
      return;
    }
    _sessionRecorded = true;
    final resumedAt = _lastResumedAt;
    ReaderSessionRecorder.recordSession(
      itemId: widget.itemId,
      sessionStart: _sessionStart,
      activeReading:
          resumedAt == null
              ? _accumulatedActive
              : _accumulatedActive + DateTime.now().difference(resumedAt),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordSession();
    if (!_progressFlushedForExit) {
      unawaited(_persistProgress(force: true));
    }
    _pageTurnController.dispose();
    _scrollController.dispose();
    for (final ctrl in _slotTransformControllers.values) {
      ctrl.dispose();
    }
    _slotTransformControllers.clear();
    _hideControlsTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _displaySettingsSaveTimer?.cancel();
    _volumeKeyEventCancel?.call();
    if (_volumeKeyPagingPushed) {
      _volumeKeyPagingPushed = false;
      unawaited(
        ReaderVolumeKeyService.instance().setVolumeKeyPagingEnabled(
          enabled: false,
        ),
      );
    }
    super.dispose();
  }

  void _syncVolumeKeyPaging() {
    final shouldEnable = isAndroidPlatform && _settings.volumeKeyPaging;
    if (_volumeKeyPagingPushed == shouldEnable) {
      return;
    }
    _volumeKeyPagingPushed = shouldEnable;
    unawaited(
      ReaderVolumeKeyService.instance().setVolumeKeyPagingEnabled(
        enabled: shouldEnable,
      ),
    );
  }

  void _handleVolumeKeyEvent(ReaderVolumeKeyDirection direction) {
    if (!mounted) {
      return;
    }
    final forward = direction == ReaderVolumeKeyDirection.down;
    if (_isPagedMode) {
      final delta = forward ? 1 : -1;
      final command =
          delta > 0 ? ReaderCommand.nextPage : ReaderCommand.previousPage;
      if (_requiresCommandGate(command) && !_commandGate.accept()) {
        return;
      }
      _turnSlotByDelta(delta);
      return;
    }
    _scrollByPage(forward ? 1 : -1);
  }

  void _updateVolumeKeyPaging(bool value) {
    setState(() {
      _settings = _settings.copyWith(volumeKeyPaging: value);
    });
    _syncVolumeKeyPaging();
    unawaited(_saveMergedPreferences({'volumeKeyPaging': value}));
  }

  Future<void> _saveMergedPreferences(Map<String, dynamic> patch) async {
    final current = await ref.read(readerPreferencesProvider.future);
    if (!mounted) {
      return;
    }
    await ref
        .read(readerPreferencesProvider.notifier)
        .save(
          mergeComicReaderPreferences(
            current: current,
            pendingDisplaySettings: _pendingDisplaySettings,
            appliedDisplaySettings: _displaySettings,
            patch: patch,
            itemId: widget.itemId,
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = MediaQuery.sizeOf(context);
    final contentWidth = _resolveLayout(viewport).contentWidth;
    if (_layoutIndex.updateContentWidth(contentWidth)) {
      if (_readingMode == ComicReadingMode.scroll &&
          _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final max = _scrollController.position.maxScrollExtent;
          if (max <= 0) return;
          final vpHeight = _scrollController.position.viewportDimension;
          final target = _layoutIndex.scrollTo(
            _anchor.pageIndex,
            _anchor.intraPageOffset,
            vpHeight,
          );
          _scrollController.jumpTo(target.clamp(0.0, max));
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final values = await ref.read(readerPreferencesProvider.future);
    final loaded =
        values.isEmpty
            ? ReaderViewSettings()
            : ReaderViewSettings.fromJson(values);
    if (!mounted) return;
    final displaySettings = ComicReaderDisplaySettings.fromPreferences(
      values,
      defaultReadingMode: kIsWeb ? 'scroll' : 'page',
      itemId: widget.itemId,
    );
    final contentWidth =
        _resolveLayout(
          MediaQuery.sizeOf(context),
          settings: displaySettings,
        ).contentWidth;
    _layoutIndex.updateContentWidth(contentWidth);

    setState(() {
      _settings = loaded;
      _displaySettings = displaySettings;
      _readingMode = _modeFromName(displaySettings.readingMode);
    });

    if (_readingMode == ComicReadingMode.scroll &&
        (_anchor.pageIndex > 0 || _anchor.intraPageOffset > 0)) {
      _pendingInitialScrollRestore = true;
      _suppressScrollProgress = true;
      _initialRestoreDeadline = DateTime.now().add(const Duration(seconds: 4));
      _restoreInitialScrollAnchor();
    }
  }

  void _onPageLayout(int index, double height) {
    _layoutIndex.updateHeight(index, height);
    if (_pendingInitialScrollRestore && index <= _anchor.pageIndex) {
      _restoreInitialScrollAnchor();
    }
    final pendingAnchor = _pendingScrollRestoreAnchor;
    if (pendingAnchor != null && index <= pendingAnchor.pageIndex) {
      _scheduleScrollRestore();
    }
  }

  void _restoreInitialScrollAnchor() {
    if (!_pendingInitialScrollRestore || !mounted) {
      if (mounted) _suppressScrollProgress = false;
      return;
    }
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreInitialScrollAnchor();
      });
      return;
    }
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      return;
    }
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = _layoutIndex.scrollTo(
      _anchor.pageIndex,
      _anchor.intraPageOffset,
      viewportHeight,
    );
    _scrollController.jumpTo(targetOffset.clamp(0.0, max));
    _initialScrollRestoreAttempts++;
    if (_isScrollRestoreStable(_anchor)) {
      _pendingInitialScrollRestore = false;
      _suppressScrollProgress = false;
      return;
    }
    final deadline = _initialRestoreDeadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      _pendingInitialScrollRestore = false;
      _suppressScrollProgress = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingInitialScrollRestore) {
        _restoreInitialScrollAnchor();
      }
    });
  }

  void _startScrollRestore(ComicAnchor anchor) {
    _pendingScrollRestoreAnchor = anchor;
    _suppressScrollProgress = true;
    _scrollRestoreScheduled = false;
    _initialScrollRestoreAttempts = 0;
    _initialRestoreDeadline = null;
    _restoreScrollAnchorWhenReady();
  }

  void _restoreScrollAnchorWhenReady() {
    final anchor = _pendingScrollRestoreAnchor;
    if (anchor == null || !mounted) {
      _suppressScrollProgress = false;
      return;
    }
    if (_readingMode != ComicReadingMode.scroll) {
      _pendingScrollRestoreAnchor = null;
      _suppressScrollProgress = false;
      return;
    }
    if (!_scrollController.hasClients) {
      _scheduleScrollRestore();
      return;
    }

    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      _initialScrollRestoreAttempts++;
      if (_initialScrollRestoreAttempts <= 8) {
        _scheduleScrollRestore();
        return;
      }
      _pendingScrollRestoreAnchor = null;
      _suppressScrollProgress = false;
      return;
    }

    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = _layoutIndex.scrollTo(
      anchor.pageIndex,
      anchor.intraPageOffset,
      viewportHeight,
    );
    _scrollController.jumpTo(targetOffset.clamp(0.0, max));
    _initialScrollRestoreAttempts++;

    if (_isScrollRestoreStable(anchor) || _initialScrollRestoreAttempts >= 8) {
      setState(() => _anchor = anchor);
      _pendingScrollRestoreAnchor = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _suppressScrollProgress = false;
        _saveProgress();
      });
      return;
    }

    _scheduleScrollRestore();
  }

  void _scheduleScrollRestore() {
    if (_scrollRestoreScheduled) {
      return;
    }
    _scrollRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollRestoreScheduled = false;
      _restoreScrollAnchorWhenReady();
    });
  }

  bool _isScrollRestoreStable(ComicAnchor anchor) {
    if (!_scrollController.hasClients) {
      return false;
    }
    final viewportHeight = _scrollController.position.viewportDimension;
    final (pageIndex, intraOffset) = _layoutIndex.hitTest(
      _scrollController.offset,
      viewportHeight,
    );
    return pageIndex == anchor.pageIndex &&
        (intraOffset - anchor.intraPageOffset).abs() <= 0.02;
  }

  void _onScroll() {
    if (_readingMode != ComicReadingMode.scroll) return;
    if (!_scrollController.hasClients) return;
    if (_totalPages <= 0) return;
    if (_suppressScrollProgress) return;

    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;

    final offset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;
    final (newPage, intraOffset) = _layoutIndex.hitTest(offset, viewportHeight);

    if (newPage != _anchor.pageIndex ||
        (intraOffset - _anchor.intraPageOffset).abs() > 0.005) {
      final pageId =
          newPage < _pages.length ? _pages[newPage].id : _anchor.pageId;
      setState(() {
        _anchor = ComicAnchor(
          pageId: pageId,
          pageIndex: newPage,
          pageFingerprint:
              newPage < _pages.length ? _pages[newPage].fingerprint : null,
          sourceId: newPage < _pages.length ? _pages[newPage].sourceId : null,
          sourcePageIndex:
              newPage < _pages.length ? _pages[newPage].sourcePageIndex : null,
          catalogKey:
              newPage < _pages.length ? _pages[newPage].catalogKey : null,
          intraPageOffset: intraOffset,
          manifestVersion: _manifest.manifestVersion,
        );
      });
    }

    _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _saveProgress();
    });
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _totalPages) return;
    if (_anchor.pageIndex == index) return;
    final page = _pages[index];
    setState(() {
      _anchor = ComicAnchor(
        pageId: page.id,
        pageIndex: index,
        pageFingerprint: page.fingerprint,
        sourceId: page.sourceId,
        sourcePageIndex: page.sourcePageIndex,
        catalogKey: page.catalogKey,
        intraPageOffset: 0.0,
        manifestVersion: _manifest.manifestVersion,
      );
    });
    _preloadAdjacent();
    _scheduleProgressSave();
  }

  void _saveProgress() {
    unawaited(_persistProgress());
    _preloadAdjacent();
  }

  DateTime? _lastServerSyncAt;
  double? _lastSyncedProgress;
  int? _lastSyncedPageIndex;

  static const _serverSyncMinInterval = Duration(seconds: 20);

  /// 将当前锚点写入本地与服务端，返回 Future 以便退出前 `await` 落库完成。
  Future<void> _persistProgress({bool force = false}) async {
    if (_pages.isEmpty || _anchor.pageIndex >= _pages.length) return;
    final progress =
        _totalPages > 0
            ? ((_anchor.pageIndex + 1) / _totalPages).clamp(0.0, 1.0)
            : 0.0;
    final mode = _readingMode == ComicReadingMode.scroll ? 'scroll' : 'page';
    final chapterId =
        _anchor.pageIndex < _pages.length
            ? _pages[_anchor.pageIndex].catalogNodeId ?? ''
            : '';
    final intraPageOffset =
        _readingMode == ComicReadingMode.scroll
            ? _anchor.intraPageOffset
            : null;

    await ReaderLocalProgress.save(
      itemId: widget.itemId,
      chapterProgress: progress,
      mode: mode,
      chapterId: chapterId,
      charOffset: _anchor.pageIndex,
      pageId: _anchor.pageId,
      pageIndex: _anchor.pageIndex,
      pageFingerprint: _anchor.pageFingerprint,
      sourceId: _anchor.sourceId,
      sourcePageIndex: _anchor.sourcePageIndex,
      catalogKey: _anchor.catalogKey,
      manifestVersion: _manifest.manifestVersion,
      intraPageOffset: intraPageOffset,
    );

    final now = DateTime.now();
    final moved =
        _anchor.pageIndex != (_lastSyncedPageIndex ?? -1) ||
        (progress - (_lastSyncedProgress ?? -1)).abs() >= 0.002;
    final withinInterval =
        _lastServerSyncAt != null &&
        now.difference(_lastServerSyncAt!) < _serverSyncMinInterval;
    if (!force && (!moved || withinInterval)) {
      return;
    }
    _lastServerSyncAt = now;
    _lastSyncedProgress = progress;
    _lastSyncedPageIndex = _anchor.pageIndex;
    await _progressSync.sync(
      itemId: widget.itemId,
      charOffset: _anchor.pageIndex,
      progressPercent: progress,
      readingMode: mode,
      chapterId: chapterId,
      pageId: _anchor.pageId,
      pageIndex: _anchor.pageIndex,
      pageFingerprint: _anchor.pageFingerprint,
      sourceId: _anchor.sourceId,
      sourcePageIndex: _anchor.sourcePageIndex,
      catalogKey: _anchor.catalogKey,
      manifestVersion: _manifest.manifestVersion,
      intraPageOffset: intraPageOffset,
      clientUpdatedAt: now,
    );

    if (kDebugMode) {
      readerDebugLog(
        'ComicReader: saved $_anchor progress=${(progress * 100).toStringAsFixed(1)}%',
      );
    }
  }

  void _update(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(comicImageLoaderProvider);
    final bookmarksAsync = ref.watch(
      readerItemBookmarksProvider(widget.itemId),
    );
    final bookmarks = bookmarksAsync.asData?.value ?? const <ReaderBookmark>[];
    final detailTitle =
        ref
            .watch(readerItemDetailProvider(widget.itemId))
            .asData
            ?.value
            .item
            .title;
    final resolvedBookTitle =
        (widget.bookTitle?.trim().isNotEmpty == true)
            ? widget.bookTitle!.trim()
            : (detailTitle?.trim().isNotEmpty == true)
            ? detailTitle!.trim()
            : (_manifest.catalog.isNotEmpty
                ? _manifest.catalog.first.title
                : '');

    final controlSettings = _controlSettings;
    final viewport = MediaQuery.sizeOf(context);
    final layout = ReaderControlLayout.resolve(
      viewport: viewport,
      fontSize: AppTypography.titleMedium,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    final isBookMode = _readingMode == ComicReadingMode.book;
    final isBookSpread = isBookMode && viewport.width >= 720;
    final slots = _buildSpreadSlots(viewport.width);
    final activeSlotIndex = _slotIndexForPage(slots, _anchor.pageIndex);
    final activeSlot =
        (activeSlotIndex >= 0 && activeSlotIndex < slots.length)
            ? slots[activeSlotIndex]
            : null;

    final int visibleStartPageIndex;
    final int visibleEndPageIndex;
    final bool isDualSpreadActive;
    if (isBookSpread && _totalPages > 0) {
      visibleStartPageIndex = _anchor.pageIndex - (_anchor.pageIndex % 2);
      visibleEndPageIndex = math.min(
        _totalPages - 1,
        visibleStartPageIndex + 1,
      );
      isDualSpreadActive = visibleEndPageIndex > visibleStartPageIndex;
    } else if (_isPagedMode && activeSlot != null) {
      visibleStartPageIndex = activeSlot.startPageIndex;
      visibleEndPageIndex = activeSlot.endPageIndex;
      isDualSpreadActive = activeSlot.pageIndices.length > 1;
    } else {
      visibleStartPageIndex = _anchor.pageIndex;
      visibleEndPageIndex = _anchor.pageIndex;
      isDualSpreadActive = false;
    }

    final l10n = AppLocalizations.of(context);
    final pageSubtitle =
        _totalPages <= 0
            ? null
            : (isDualSpreadActive
                ? l10n.readerPageRange(
                  visibleStartPageIndex + 1,
                  math.min(_totalPages, visibleEndPageIndex + 1),
                  _totalPages,
                )
                : l10n.readerPageOf(_anchor.pageIndex + 1, _totalPages));
    final currentBookmark = _findBookmarkForPage(bookmarks, _anchor.pageIndex);
    final isBookmarked = currentBookmark != null;
    ref.listen<AsyncValue<Map<String, dynamic>>>(readerPreferencesProvider, (
      _,
      next,
    ) {
      final values = next.asData?.value;
      if (values == null || values.isEmpty || !mounted) {
        return;
      }
      final updated = ReaderViewSettings.fromJson(values);
      if (updated.paletteId != _settings.paletteId ||
          updated.brightness != _settings.brightness ||
          updated.warmth != _settings.warmth ||
          updated.autoNight != _settings.autoNight) {
        setState(() {
          _settings = _settings.copyWith(
            paletteId: updated.paletteId,
            brightness: updated.brightness,
            warmth: updated.warmth,
            autoNight: updated.autoNight,
          );
        });
      }
    });

    final deskBg = controlSettings.bookDeskColor;
    final pageSurfaceBg = controlSettings.surfaceColor;
    final stageBg = isBookMode ? deskBg : pageSurfaceBg;
    final topBarVisible = _showControls || _panelCoordinator.isOpen;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: stageBg,
        body: Stack(
          children: [
            Positioned.fill(
              child: ReaderComfortFilter(
                brightness: _settings.brightness,
                warmth: _settings.warmth,
                child: AnimatedContainer(
                  duration:
                      animationsDisabled
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  decoration:
                      isBookMode
                          ? BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.2),
                              radius: 1.1,
                              colors: [
                                Color.lerp(deskBg, Colors.white, 0.12)!,
                                deskBg,
                              ],
                              stops: const [0.0, 0.70],
                            ),
                          )
                          : BoxDecoration(color: pageSurfaceBg),
                  child: _buildContent(
                    slots: slots,
                    activeSlotIndex: activeSlotIndex,
                    isBookmarked: isBookmarked,
                    pageSurfaceBg: pageSurfaceBg,
                  ),
                ),
              ),
            ),
            // Book 模式宽屏（>= 960）左右 48×48 悬浮翻页箭头，与正文阅读器一致。
            if (isBookMode && viewport.width >= 960 && _totalPages > 0) ...[
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ComicBookFloatingArrow(
                    icon: Icons.chevron_left_rounded,
                    tooltip:
                        _isRtl ? l10n.readerNextPage : l10n.readerPreviousPage,
                    onTap: () => _turnSlotByDelta(_isRtl ? 1 : -1),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ComicBookFloatingArrow(
                    icon: Icons.chevron_right_rounded,
                    tooltip:
                        _isRtl ? l10n.readerPreviousPage : l10n.readerNextPage,
                    onTap: () => _turnSlotByDelta(_isRtl ? -1 : 1),
                  ),
                ),
              ),
            ],
            ComicReaderBottomBar(
              visible: _showControls && !_panelCoordinator.isOpen,
              currentPageIndex: _anchor.pageIndex,
              totalPages: _totalPages,
              isPageMode: _isPagedMode,
              settings: controlSettings,
              isRtl: _isRtl,
              isDualPage: isDualSpreadActive,
              visibleEndPageIndex: visibleEndPageIndex,
              zoomScale: isBookMode ? 1.0 : _currentZoomScale,
              onResetZoom: _imageZoomed ? _resetCurrentSlotZoom : null,
              onPrevious:
                  visibleStartPageIndex > 0 ? () => _turnSlotByDelta(-1) : null,
              onNext:
                  visibleEndPageIndex < _totalPages - 1
                      ? () => _turnSlotByDelta(1)
                      : null,
              onSeek: _jumpToPage,
              onShowContents: () => _togglePanel(ReaderPanelType.contents),
              onSwitchReadingMode: supportsPageMode ? _switchReadingMode : null,
            ),
            ComicPageIndicator(
              visible: !topBarVisible,
              currentPageIndex: _anchor.pageIndex,
              totalPages: _totalPages,
              visibleEndPageIndex: visibleEndPageIndex,
            ),
            if (_panelCoordinator.active != null)
              Positioned.fill(
                child: ComicReaderPanelOverlay(
                  active: _panelCoordinator.active!,
                  layout: layout,
                  settings: controlSettings,
                  manifest: _manifest,
                  currentPageIndex: _anchor.pageIndex,
                  displaySettings: _displaySettings,
                  volumeKeyPaging: _settings.volumeKeyPaging,
                  bookmarks: bookmarks,
                  effectiveRtl: _isRtl,
                  onClose: _closePanel,
                  onCatalogNodeTap: (node) {
                    _closePanel();
                    _jumpToCatalogNode(node);
                  },
                  onBookmarkTap: (bm) {
                    _closePanel();
                    _jumpToPage(bm.charOffset);
                  },
                  onBookmarkDelete: (bm) => _deleteBookmark(bm),
                  onDisplaySettingsChanged: _applyDisplaySettings,
                  onVolumeKeyPagingChanged: _updateVolumeKeyPaging,
                ),
              ),
            // 顶栏置于抽屉浮层之上，展开右侧磨砂抽屉时顶栏保持可见且支持一键切换面板。
            ComicReaderTopBar(
              visible: topBarVisible,
              catalogTitle:
                  _manifest.catalog.isNotEmpty
                      ? _manifest.catalog.first.title
                      : '',
              bookTitle: resolvedBookTitle,
              pageSubtitle: pageSubtitle,
              readingMode: _modeName(_readingMode),
              isPageMode: _isPagedMode,
              settings: controlSettings,
              isBookmarked: isBookmarked,
              bookmarkCount: bookmarks.length,
              activePanel: _panelCoordinator.active,
              onBack: _requestExit,
              onShowContents: () => _togglePanel(ReaderPanelType.contents),
              onToggleBookmark: () => _toggleCurrentPageBookmark(bookmarks),
              onShowBookmarks: () => _togglePanel(ReaderPanelType.annotations),
              onShowSettings: () => _togglePanel(ReaderPanelType.settings),
              onShowShortcuts: () => _togglePanel(ReaderPanelType.shortcuts),
              onSelectReadingMode: supportsPageMode ? _selectReadingMode : null,
              onSwitchReadingMode: supportsPageMode ? _switchReadingMode : null,
            ),
          ],
        ),
      ),
    );
  }
}
