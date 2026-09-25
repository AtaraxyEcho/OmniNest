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
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcuts.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_tap_detector.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:omninest/platform/android/reader_volume_key_service.dart';

part 'comic_reader_view_sections.dart';

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
  bool _imageZoomed = false;
  bool _exitRequested = false;
  late ReaderProgressSyncService _progressSync;
  final ReaderPanelCoordinator _panelCoordinator = ReaderPanelCoordinator();
  final ReaderCommandGate _commandGate = ReaderCommandGate();
  VoidCallback? _volumeKeyEventCancel;
  bool _volumeKeyPagingPushed = false;

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
    _volumeKeyEventCancel = ReaderVolumeKeyService.instance().addListener(
      _handleVolumeKeyEvent,
    );
    unawaited(
      _loadSettings().then((_) {
        if (mounted) _syncVolumeKeyPaging();
      }),
    );
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

  /// 将音量键拦截开关同步到原生层（仅 Android 实际生效）。
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

  /// 音量键事件映射为阅读命令：下键向后翻，上键向前翻（页模式随阅读方向）。
  void _handleVolumeKeyEvent(ReaderVolumeKeyDirection direction) {
    if (!mounted) {
      return;
    }
    final forward = direction == ReaderVolumeKeyDirection.down;
    if (_readingMode == ComicReadingMode.page) {
      final delta = forward ? (_isRtl ? -1 : 1) : (_isRtl ? 1 : -1);
      final command =
          delta > 0 ? ReaderCommand.nextPage : ReaderCommand.previousPage;
      if (_requiresCommandGate(command) && !_commandGate.accept()) {
        return;
      }
      _goToRelativePage(delta);
      return;
    }
    _scrollByPage(forward ? 1 : -1);
  }

  /// 设置面板切换音量键翻页：更新本地设置、推送平台态并落库。
  void _updateVolumeKeyPaging(bool value) {
    setState(() {
      _settings = _settings.copyWith(volumeKeyPaging: value);
    });
    _syncVolumeKeyPaging();
    unawaited(
      ref.read(readerPreferencesProvider.notifier).save({
        'volumeKeyPaging': value,
      }),
    );
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

  /// 将状态变更封装为回调，供扩展中的方法触发重建。
  void _update(VoidCallback fn) {
    setState(fn);
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
            // 控件条与页码常驻挂载，仅切换可见性：条件挂载会让父 Stack
            // 存续期间整棵摘除/加回语义子树，触发 Windows 辅助功能桥
            // "will not be in the tree" 更新失败。
            ComicReaderTopBar(
              visible: _showControls,
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
              visible: _showControls,
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
            ComicPageIndicator(
              visible: !_showControls,
              currentPageIndex: _anchor.pageIndex,
              totalPages: _totalPages,
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
                  onClose: _closePanel,
                  onCatalogNodeTap: (node) {
                    _closePanel();
                    _jumpToCatalogNode(node);
                  },
                  onDisplaySettingsChanged: _applyDisplaySettings,
                  onVolumeKeyPagingChanged: _updateVolumeKeyPaging,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
