import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/reader/application/reader_comic_image_provider.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:omninest/features/reader/domain/comic_anchor.dart';
import 'package:omninest/features/reader/domain/comic_layout_index.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_page_image.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_overlays.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_settings_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_adaptive_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcut_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcuts.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 漫画阅读模式。
enum ComicReadingMode {
  /// 单页翻页（水平滑动）。
  page,

  /// 竖向连续滚动。
  scroll,
}

/// 漫画阅读器视图。
///
/// 支持单页翻页和竖向连续滚动两种模式。
/// 图片通过后端 page API 按需读取，阅读态不直接解析漫画源文件。
class ComicReaderView extends ConsumerStatefulWidget {
  const ComicReaderView({
    required this.itemId,
    required this.manifest,
    required this.onBack,
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

  /// 初始页码索引。
  final int initialPageIndex;

  /// 初始页内偏移（滚动模式恢复用，0.0-1.0）。
  final double? initialIntraPageOffset;

  @override
  ConsumerState<ComicReaderView> createState() => _ComicReaderViewState();
}

class _ComicReaderViewState extends ConsumerState<ComicReaderView> {
  late PageController _pageController;
  late ScrollController _scrollController;
  late ComicLayoutIndex _layoutIndex;
  final TransformationController _transformationController =
      TransformationController();

  /// 当前阅读锚点（统一真相源）。
  ComicAnchor _anchor = const ComicAnchor(pageId: '', pageIndex: 0);

  bool _showControls = false;
  late ComicReadingMode _readingMode;
  late ComicReaderDisplaySettings _displaySettings;
  ReaderViewSettings _settings = ReaderViewSettings();
  Timer? _hideControlsTimer;
  Timer? _scrollSaveTimer;
  Timer? _displaySettingsSaveTimer;
  // 防抖中尚未落盘的最新设置：dispose 只 cancel 会丢最后一次调整，
  // 在 deactivate（ref 仍可用）补一次落盘。
  ComicReaderDisplaySettings? _pendingDisplaySettings;
  bool _pendingInitialScrollRestore = false;
  int _initialScrollRestoreAttempts = 0;
  // 初始恢复的时间兜底：超过后放弃视觉恢复，保持意图锚点不再重试。
  DateTime? _initialRestoreDeadline;
  bool _suppressScrollProgress = false;
  ComicAnchor? _pendingScrollRestoreAnchor;
  bool _scrollRestoreScheduled = false;
  Offset? _tapStartPosition;
  DateTime? _tapStartAt;
  bool _imageZoomed = false;
  bool _exitRequested = false;
  late ReaderProgressSyncService _progressSync;
  final ReaderPanelCoordinator _panelCoordinator = ReaderPanelCoordinator();
  final ReaderCommandGate _commandGate = ReaderCommandGate();

  ComicManifest get _manifest => widget.manifest;
  List<ComicPage> get _pages => _manifest.pages;
  int get _totalPages => _pages.length;
  bool get _isRtl => _manifest.readingDirection?.toLowerCase() == 'rtl';
  ReaderViewSettings get _controlSettings =>
      _settings.copyWith(paletteId: ReaderReadingPalette.dark.id);

  @override
  void initState() {
    super.initState();
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
    _pageController = PageController(initialPage: initialPage);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadSettings();
  }

  @override
  void deactivate() {
    // 防抖中的设置变更在离开树前落盘（dispose 中 ref 不可用）。
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
  void dispose() {
    // 退出前补一次最终落库：滚动进度走 500ms 防抖，直接 cancel 会丢
    // 最近一次未落盘的位置；持久化不依赖 ref，可在 dispose 中执行。
    _persistProgress(force: true);
    _pageController.dispose();
    _scrollController.dispose();
    _transformationController.dispose();
    _hideControlsTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _displaySettingsSaveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = MediaQuery.sizeOf(context);
    final contentWidth = _resolveLayout(viewport).contentWidth;
    if (_layoutIndex.updateContentWidth(contentWidth)) {
      // 旋转/resize 后重新定位当前锚点
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

  /// 加载阅读器设置。
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

    // 滚动模式：首帧后跳转到初始锚点位置。
    // 抑制滚动回调：图片未加载、maxScrollExtent 未收敛时 jumpTo 会被
    // clamp 到错误位置，未抑制的 _onScroll 会用 hitTest 覆写 _anchor，
    // 错误随后被落库。
    if (_readingMode == ComicReadingMode.scroll &&
        (_anchor.pageIndex > 0 || _anchor.intraPageOffset > 0)) {
      _pendingInitialScrollRestore = true;
      _suppressScrollProgress = true;
      _initialRestoreDeadline = DateTime.now().add(const Duration(seconds: 4));
      _restoreInitialScrollAnchor();
    }
  }

  /// 页面布局回调：更新布局索引中的真实高度。
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
      // 布局尚未产出：等待 _onPageLayout 回报真实高度后由事件驱动重试。
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
      // 高度迟迟未回报：放弃视觉恢复，但 _anchor 保持意图值
      // （suppress 已防污染），已存进度不被 clamp 位置覆盖。
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

  /// 滚动事件监听（竖向滚动模式）。
  ///
  /// 使用 ComicLayoutIndex 精确定位当前页。
  /// 滚动停止后节流保存进度（500ms）。
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

    // 滚动节流保存：500ms 后触发
    _scheduleProgressSave();
  }

  /// 进度落库节流：翻页与滚动共用 500ms 防抖，快速连翻/连续滚动合并为
  /// 一次本地写入与服务端同步；dispose 的最终持久化兜底防丢。
  void _scheduleProgressSave() {
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _saveProgress();
    });
  }

  /// 页面切换回调（翻页模式）。
  void _onPageChanged(int index) {
    if (index < 0 || index >= _totalPages) return;
    if (_anchor.pageIndex == index) return;
    final page = _pages[index];
    _resetImageTransform();
    setState(() {
      _anchor = ComicAnchor(
        pageId: page.id,
        pageIndex: index,
        pageFingerprint: page.fingerprint,
        sourceId: page.sourceId,
        sourcePageIndex: page.sourcePageIndex,
        catalogKey: page.catalogKey,
        intraPageOffset: 0.0, // 翻页模式无页内偏移
        manifestVersion: _manifest.manifestVersion,
      );
    });
    // 预加载立即执行，持久化走防抖合并
    _preloadAdjacent();
    _scheduleProgressSave();
  }

  /// 保存阅读进度到本地和服务器。
  void _saveProgress() {
    _persistProgress();

    // 预加载前后页
    _preloadAdjacent();
  }

  DateTime? _lastServerSyncAt;
  double? _lastSyncedProgress;
  int? _lastSyncedPageIndex;

  /// 服务端同步最小间隔，与文本阅读器保持同一节流策略。
  static const _serverSyncMinInterval = Duration(seconds: 20);

  /// 将当前锚点写入本地与服务端；不依赖 ref，dispose 时也可安全调用。
  ///
  /// 本地写入保持每次执行；服务端上报仅在 force（离场补报）或
  /// 「距上次超过最小间隔且页码确有变化」时执行。
  void _persistProgress({bool force = false}) {
    if (_pages.isEmpty || _anchor.pageIndex >= _pages.length) return;
    final progress =
        _totalPages > 0
            ? ((_anchor.pageIndex + 1) / _totalPages).clamp(0.0, 1.0)
            : 0.0;
    final mode = _readingMode == ComicReadingMode.page ? 'page' : 'scroll';
    final chapterId =
        _anchor.pageIndex < _pages.length
            ? _pages[_anchor.pageIndex].catalogNodeId ?? ''
            : '';
    final intraPageOffset =
        _readingMode == ComicReadingMode.scroll
            ? _anchor.intraPageOffset
            : null;

    // 本地保存
    unawaited(
      ReaderLocalProgress.save(
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
        manifestVersion: _anchor.manifestVersion,
        intraPageOffset: intraPageOffset,
      ),
    );

    // 服务端同步（漫画锚点）：节流判定与文本阅读器一致
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
    unawaited(
      _progressSync.sync(
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
        manifestVersion: _anchor.manifestVersion,
        intraPageOffset: intraPageOffset,
      ),
    );

    if (kDebugMode) {
      readerDebugLog(
        'ComicReader: saved $_anchor progress=${(progress * 100).toStringAsFixed(1)}%',
      );
    }
  }

  /// 预加载当前页前后的图片。
  void _preloadAdjacent() {
    if (_totalPages <= 0) {
      return;
    }
    final loader = ref.read(comicImageLoaderProvider);
    final start = (_anchor.pageIndex - 2).clamp(0, _totalPages - 1).toInt();
    final end = (_anchor.pageIndex + 3).clamp(0, _totalPages - 1).toInt();
    final pagesToLoad = <ComicPage>[];
    for (var i = start; i <= end; i++) {
      pagesToLoad.add(_pages[i]);
    }
    unawaited(loader.preloadImages(widget.itemId, pagesToLoad));
  }

  ComicReadingMode _modeFromName(String mode) {
    return mode == 'page' ? ComicReadingMode.page : ComicReadingMode.scroll;
  }

  ComicReaderLayout _resolveLayout(
    Size viewport, {
    ComicReaderDisplaySettings? settings,
  }) {
    final resolved = settings ?? _displaySettings;
    return ComicReaderLayout.resolve(
      viewport: viewport,
      preferredContentWidth: resolved.contentWidth,
      fullWidth: resolved.fullWidth,
    );
  }

  /// 切换阅读模式（翻页与连续滚动），保持当前阅读锚点。
  void _switchReadingMode() {
    final nextMode =
        _readingMode == ComicReadingMode.page
            ? ComicReadingMode.scroll
            : ComicReadingMode.page;
    _applyDisplaySettings(
      _displaySettings.copyWith(
        readingMode: nextMode == ComicReadingMode.page ? 'page' : 'scroll',
      ),
    );
  }

  void _applyDisplaySettings(ComicReaderDisplaySettings settings) {
    final previousMode = _readingMode;
    final nextMode = _modeFromName(settings.readingMode);
    final frozenAnchor = _anchor;

    setState(() {
      _displaySettings = settings;
      _readingMode = nextMode;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _layoutIndex.updateContentWidth(
        _resolveLayout(MediaQuery.sizeOf(context)).contentWidth,
      );
      if (previousMode == ComicReadingMode.page &&
          nextMode == ComicReadingMode.scroll) {
        _startScrollRestore(frozenAnchor);
      } else if (previousMode == ComicReadingMode.scroll &&
          nextMode == ComicReadingMode.page) {
        _pageController.jumpToPage(frozenAnchor.pageIndex);
        _saveProgress();
      } else if (nextMode == ComicReadingMode.scroll) {
        _startScrollRestore(frozenAnchor);
      }
      setState(() {
        _anchor = frozenAnchor;
      });
    });

    _displaySettingsSaveTimer?.cancel();
    _pendingDisplaySettings = settings;
    _displaySettingsSaveTimer = Timer(const Duration(milliseconds: 320), () {
      _pendingDisplaySettings = null;
      unawaited(_saveDisplaySettings(settings));
    });
  }

  Future<void> _saveDisplaySettings(ComicReaderDisplaySettings settings) async {
    final current = await ref.read(readerPreferencesProvider.future);
    if (!mounted) return;
    await ref.read(readerPreferencesProvider.notifier).save({
      ...current,
      ...settings.toPreferences(),
    });
  }

  /// 切换控件显示/隐藏。
  void _toggleControls() {
    if (_panelCoordinator.close()) {
      setState(() {});
      return;
    }
    setState(() => _showControls = !_showControls);
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _togglePanel(ReaderPanelType panel) {
    _hideControlsTimer?.cancel();
    setState(() {
      _panelCoordinator.toggle(panel);
      _showControls = false;
    });
  }

  void _closePanel() {
    if (_panelCoordinator.close()) {
      setState(() {});
    }
  }

  /// 跳转到指定目录节点的起始页。
  void _jumpToCatalogNode(ComicCatalogNode node) {
    final targetIndex = _pages.indexWhere((p) => p.catalogNodeId == node.id);
    if (targetIndex < 0) {
      return;
    }
    _jumpToPage(targetIndex);
  }

  void _jumpToPage(int index) {
    if (_totalPages <= 0) {
      return;
    }
    final targetIndex = index.clamp(0, _totalPages - 1).toInt();
    if (targetIndex == _anchor.pageIndex) {
      return;
    }

    _resetImageTransform();
    final page = _pages[targetIndex];
    setState(() {
      _anchor = ComicAnchor(
        pageId: page.id,
        pageIndex: targetIndex,
        pageFingerprint: page.fingerprint,
        sourceId: page.sourceId,
        sourcePageIndex: page.sourcePageIndex,
        catalogKey: page.catalogKey,
        manifestVersion: _manifest.manifestVersion,
      );
    });

    if (_readingMode == ComicReadingMode.page) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (_scrollController.hasClients) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final targetOffset = _layoutIndex.scrollTo(
        targetIndex,
        0.0,
        viewportHeight,
      );
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, max),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    _saveProgress();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(comicImageLoaderProvider);
    final controlSettings = _controlSettings;
    final layout = ReaderControlLayout.resolve(
      viewport: MediaQuery.sizeOf(context),
      fontSize: AppTypography.titleMedium,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildContent(),
            if (_showControls) ...[
              ComicReaderTopBar(
                catalogTitle:
                    _manifest.catalog.isNotEmpty
                        ? _manifest.catalog.first.title
                        : '',
                isPageMode: _readingMode == ComicReadingMode.page,
                settings: controlSettings,
                onBack: _requestExit,
                onShowContents: () => _togglePanel(ReaderPanelType.contents),
                onShowSettings: () => _togglePanel(ReaderPanelType.settings),
                onShowShortcuts: () => _togglePanel(ReaderPanelType.shortcuts),
                onSwitchReadingMode: _switchReadingMode,
              ),
              ComicReaderBottomBar(
                currentPageIndex: _anchor.pageIndex,
                totalPages: _totalPages,
                isPageMode: _readingMode == ComicReadingMode.page,
                settings: controlSettings,
                onPrevious:
                    _anchor.pageIndex > 0 ? () => _goToRelativePage(-1) : null,
                onNext:
                    _anchor.pageIndex < _totalPages - 1
                        ? () => _goToRelativePage(1)
                        : null,
                onSeek: _jumpToPage,
                onShowContents: () => _togglePanel(ReaderPanelType.contents),
                onSwitchReadingMode: _switchReadingMode,
              ),
            ] else
              ComicPageIndicator(
                currentPageIndex: _anchor.pageIndex,
                totalPages: _totalPages,
              ),
            if (_panelCoordinator.active != null)
              Positioned.fill(
                child: _buildPanelOverlay(layout, controlSettings),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelOverlay(
    ReaderControlLayout layout,
    ReaderViewSettings controlSettings,
  ) {
    final l10n = AppLocalizations.of(context);
    final active = _panelCoordinator.active;
    final title = switch (active) {
      ReaderPanelType.contents => l10n.readerTableOfContents,
      ReaderPanelType.settings => l10n.readerSettingsTitle,
      _ => l10n.readerShortcutsTitle,
    };
    final child = switch (active) {
      ReaderPanelType.contents => ComicCatalogPanel(
        manifest: _manifest,
        currentPageIndex: _anchor.pageIndex,
        settings: controlSettings,
        onNodeTap: (node) {
          _closePanel();
          _jumpToCatalogNode(node);
        },
      ),
      ReaderPanelType.settings => ComicReaderSettingsPanel(
        displaySettings: _displaySettings,
        themeSettings: controlSettings,
        onChanged: _applyDisplaySettings,
      ),
      _ => ReaderShortcutPanel(settings: controlSettings, isComic: true),
    };
    return ReaderAdaptivePanelOverlay(
      title: title,
      settings: controlSettings,
      layout: layout,
      onClose: _closePanel,
      child: child,
    );
  }

  void _handleContentTap(Offset position) {
    if (_imageZoomed) {
      _toggleControls();
      return;
    }
    if (_readingMode != ComicReadingMode.page || _totalPages <= 0) {
      _toggleControls();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final x = position.dx;
    if (x < width * 0.32) {
      _goToRelativePage(_isRtl ? 1 : -1);
    } else if (x > width * 0.68) {
      _goToRelativePage(_isRtl ? -1 : 1);
    } else {
      _toggleControls();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final textInputFocused =
        focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    final command = const ReaderShortcutResolver().resolve(
      key: event.logicalKey,
      mode:
          _readingMode == ComicReadingMode.page
              ? ReaderShortcutMode.comicPage
              : ReaderShortcutMode.comicScroll,
      shiftPressed: hardware.isShiftPressed,
      controlPressed: hardware.isControlPressed || hardware.isMetaPressed,
      isRtl: _isRtl,
      textInputFocused: textInputFocused,
      imageZoomed: _imageZoomed,
      isWeb: kIsWeb,
    );
    if (command == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && !_isRepeatableCommand(command)) {
      return KeyEventResult.handled;
    }
    if (_requiresCommandGate(command) && !_commandGate.accept()) {
      return KeyEventResult.handled;
    }
    _executeCommand(command);
    return KeyEventResult.handled;
  }

  bool _isRepeatableCommand(ReaderCommand command) {
    return command == ReaderCommand.nextViewport ||
        command == ReaderCommand.previousViewport ||
        command == ReaderCommand.scrollForward ||
        command == ReaderCommand.scrollBackward;
  }

  bool _requiresCommandGate(ReaderCommand command) {
    return command == ReaderCommand.nextPage ||
        command == ReaderCommand.previousPage ||
        command == ReaderCommand.toggleReadingMode;
  }

  void _executeCommand(ReaderCommand command) {
    switch (command) {
      case ReaderCommand.closeLayer:
        _closeLayer();
        return;
      case ReaderCommand.toggleContents:
        _togglePanel(ReaderPanelType.contents);
        return;
      case ReaderCommand.toggleImmersive:
        _toggleControls();
        return;
      case ReaderCommand.toggleFullscreen:
        _toggleFullscreen();
        return;
      case ReaderCommand.showShortcuts:
        _togglePanel(ReaderPanelType.shortcuts);
        return;
      case ReaderCommand.nextPage:
        _goToRelativePage(1);
        return;
      case ReaderCommand.previousPage:
        _goToRelativePage(-1);
        return;
      case ReaderCommand.nextViewport:
        _scrollByPage(1);
        return;
      case ReaderCommand.previousViewport:
        _scrollByPage(-1);
        return;
      case ReaderCommand.scrollForward:
        _scrollByPage(1, viewportFactor: 0.16);
        return;
      case ReaderCommand.scrollBackward:
        _scrollByPage(-1, viewportFactor: 0.16);
        return;
      case ReaderCommand.chapterStart:
        _jumpToPage(0);
        return;
      case ReaderCommand.chapterEnd:
        _jumpToPage(_totalPages - 1);
        return;
      case ReaderCommand.toggleReadingMode:
        _switchReadingMode();
        return;
      case ReaderCommand.toggleBookmark:
      case ReaderCommand.openSearch:
      case ReaderCommand.openAnnotations:
      case ReaderCommand.increaseFont:
      case ReaderCommand.decreaseFont:
      case ReaderCommand.resetTypography:
      case ReaderCommand.nextChapter:
      case ReaderCommand.previousChapter:
        return;
    }
  }

  void _closeLayer() {
    if (_panelCoordinator.close()) {
      setState(() {});
      return;
    }
    if (_showControls) {
      _hideControlsTimer?.cancel();
      setState(() => _showControls = false);
      return;
    }
    _requestExit();
  }

  void _requestExit() {
    if (_exitRequested || !mounted) {
      return;
    }
    _exitRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onBack();
      }
    });
  }

  void _toggleFullscreen() {
    if (isDesktopPlatform) {
      unawaited(
        ref.read(windowChromeControllerProvider.notifier).toggleFullscreen(),
      );
      return;
    }
    if (!kIsWeb) {
      fs.toggleFullscreen();
    }
  }

  void _resetImageTransform() {
    _transformationController.value = Matrix4.identity();
    _imageZoomed = false;
  }

  void _updateImageZoomState() {
    _imageZoomed = _transformationController.value.getMaxScaleOnAxis() > 1.01;
  }

  void _goToRelativePage(int delta) {
    _jumpToPage(_anchor.pageIndex + delta);
  }

  void _scrollByPage(int direction, {double viewportFactor = 0.88}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target =
        _scrollController.offset +
        position.viewportDimension * viewportFactor * direction;
    _scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// 构建漫画内容。
  Widget _buildContent() {
    if (_totalPages <= 0) {
      return Center(
        child: Text(
          AppLocalizations.of(context).readerNoContent,
          style: TextStyle(color: _settings.onSurfaceVariantColor),
        ),
      );
    }
    if (_readingMode == ComicReadingMode.scroll) {
      return _buildTapAwareContent(_buildScrollMode());
    }
    return _buildTapAwareContent(_buildPageMode());
  }

  Widget _buildTapAwareContent(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapStartPosition = event.localPosition;
        _tapStartAt = DateTime.now();
      },
      onPointerUp: (event) {
        final start = _tapStartPosition;
        final startedAt = _tapStartAt;
        _tapStartPosition = null;
        _tapStartAt = null;
        if (start == null || startedAt == null) {
          return;
        }
        final duration = DateTime.now().difference(startedAt);
        final distance = (event.localPosition - start).distance;
        if (duration <= const Duration(milliseconds: 260) && distance <= 12) {
          _handleContentTap(event.localPosition);
        }
      },
      onPointerCancel: (_) {
        _tapStartPosition = null;
        _tapStartAt = null;
      },
      child: child,
    );
  }

  /// 竖向连续滚动模式。
  Widget _buildScrollMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final layout = _resolveLayout(viewport);
        _layoutIndex.updateContentWidth(layout.contentWidth);
        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
            vertical: _displaySettings.pageGap,
          ),
          itemCount: _totalPages,
          itemBuilder: (context, index) {
            return Center(
              child: SizedBox(
                width: layout.contentWidth,
                child: Padding(
                  padding: EdgeInsets.only(bottom: _displaySettings.pageGap),
                  child: ComicPageImage(
                    page: _pages[index],
                    itemId: widget.itemId,
                    surfaceColor: Colors.black,
                    layout: ComicPageImageLayout.continuous,
                    onLayout:
                        (pageIndex, height) => _onPageLayout(
                          pageIndex,
                          height + _displaySettings.pageGap,
                        ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 单页翻页模式。
  Widget _buildPageMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _resolveLayout(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return PageView.builder(
          controller: _pageController,
          itemCount: _totalPages,
          reverse: _isRtl,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            return Padding(
              padding: layout.pagedPadding,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 4.0,
                onInteractionUpdate: (_) => _updateImageZoomState(),
                onInteractionEnd: (_) => _updateImageZoomState(),
                child: ComicPageImage(
                  page: _pages[index],
                  itemId: widget.itemId,
                  surfaceColor: Colors.black,
                  layout: ComicPageImageLayout.paged,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
