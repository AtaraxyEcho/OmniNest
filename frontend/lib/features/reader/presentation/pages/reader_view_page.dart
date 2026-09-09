import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';
import 'package:omninest/app/appearance/application/font_scale_scope.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
import 'package:omninest/features/reader/application/reader_progress_sync_service.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_progress_save_coordinator.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_skeleton.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_deferred_restore_overlay.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_backup.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_tts_controls.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_bottom_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_indicator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_adaptive_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_find_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcut_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcuts.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_side_tap_zone.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_builders.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_controls_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_library_actions_mixin.dart';
import 'package:omninest/features/reader/application/reader_session_recorder.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_interaction_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_settings_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_top_bar.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_view_page_commands.dart';

class ReaderViewPage extends ConsumerStatefulWidget {
  const ReaderViewPage({
    required this.itemId,
    required this.chapterId,
    this.initialProgressPayload,
    super.key,
  });

  final String itemId;
  final String chapterId;
  final Map<String, dynamic>? initialProgressPayload;

  @override
  ConsumerState<ReaderViewPage> createState() => _ReaderViewPageState();
}

class _FlatPageEntry {
  const _FlatPageEntry({
    required this.chapterId,
    required this.localPageIndex,
    required this.chapterTitle,
    required this.chapterIndex,
  });

  final String chapterId;
  final int localPageIndex;
  final String chapterTitle;
  final int chapterIndex;
}

class _ReaderViewPageState extends ConsumerState<ReaderViewPage>
    with
        ReaderViewPageBuilders,
        ReaderViewPageSettingsMixin,
        ReaderViewPageControlsMixin,
        ReaderViewPageLibraryActionsMixin,
        ReaderViewPageMixin,
        ReaderViewPageInteractionMixin {
  // ── 核心组件 ──
  final _positionTracker = ReaderPositionTracker();
  ReaderContentLoader? _contentLoader;
  final ReaderPageTurnController _pageTurnController =
      ReaderPageTurnController();
  final ReaderPanelCoordinator _panelCoordinator = ReaderPanelCoordinator();
  final ReaderCommandGate _readerCommandGate = ReaderCommandGate();
  final ReaderChapterLoadCoordinator _chapterLoadCoordinator =
      ReaderChapterLoadCoordinator();
  final ReaderPageLocator _pageLocator = ReaderPageLocator();
  late final ReaderProgressSaveCoordinator _progressSaveCoordinator;
  late final WindowChromeController _windowChromeController;
  WindowChromeLease? _windowChromeLease;
  double _lastTextScale = 1;

  @override
  WindowChromeController get windowChromeController => _windowChromeController;

  @override
  WindowChromeLease? get windowChromeLease => _windowChromeLease;

  @override
  set windowChromeLease(WindowChromeLease? value) {
    _windowChromeLease = value;
  }

  // ── 渲染状态 ──
  final ScrollController _scrollController = ScrollController();
  final ReaderContinuousScrollController _continuousScrollController =
      ReaderContinuousScrollController();
  List<_FlatPageEntry> _flatPages = [];
  int _currentPageIndex = 0;
  int _pageModePage = 0;

  // ── 进度 ──
  double _scrollProgress = 0;
  DateTime? _lastAppliedProgressAt;
  ReaderProgressSnapshot? _lastOwnProgressSave; // 本机最近一次推送的进度快照
  double? _pendingChapterProgress; // 恢复时的章节进度比例（0-1）
  int? _pendingRestoreCharOffset; // 模式切换时待恢复的字符偏移（用于精确像素定位）
  bool _isRestoringProgress = false; // 正在恢复阅读位置，显示加载遮罩
  bool _modeSwitchInProgress = false; // 模式切换中，首次翻页/滚动后清除
  int? _modeSwitchAnchor; // 模式切换时冻结的 charOffset，跨多次 onPageChanged 保留
  int _restoreTargetCharOffset = 0; // 当前恢复目标 charOffset，用于防回退
  DateTime _restoreSilenceUntil = DateTime.fromMillisecondsSinceEpoch(
    0,
  ); // 恢复后静默窗口
  DateTime _lastPointerDownTime = DateTime.fromMillisecondsSinceEpoch(
    0,
  ); // 最后一次真实触摸
  final _restore = ScrollRestore(); // 滚动位置恢复器（封装帧回调生命周期）

  // ── 章节导航与返回原进度 ──
  ReaderChapterNavigationIntent _chapterNavigationIntent =
      const ReaderChapterNavigationIntent.resume();
  ReaderProgressSnapshot? _returnToProgressSnapshot;
  bool _showReturnControl = false; // 是否显示"返回原进度"控件
  Timer? _returnControlTimer; // 自动隐藏计时器

  // ── 并发控制 ──
  bool _isAnimating = false;
  bool _isSwitchingChapter = false;
  bool _isLoadingChapter = false;
  bool _showChapterLoadingOverlay = false;
  Timer? _chapterLoadingTimer;
  int _loadGeneration = 0;
  ReaderViewSettings? _pendingSettings;

  // ── UI 状态 ──
  ReaderViewSettings _settings = ReaderViewSettings();
  late String _currentChapterId = widget.chapterId;
  ReaderChapterContent? _cachedContent;
  bool _showControls = false;
  bool _showTts = false;
  bool _isHoveringControls = false; // Web 端鼠标是否悬停在控件栏上
  bool _isBookmarked = false;
  bool _isInBookshelf = false;
  bool _bookmarkBusy = false;
  bool _bookshelfBusy = false;
  bool _selectionActive = false;
  bool _exitRequested = false;
  ParsedBook? _parsedBookSnapshot;
  bool _readerBuildWorkScheduled = false;
  ParsedBook? _pendingParsedBook;
  ReaderChapterContent? _pendingReaderContent;
  List<ReaderChapter>? _pendingReaderChapters;
  bool _pendingReaderProviderError = false;

  ReaderAnnotationHandler? _annotationHandler;
  Timer? _hideTimer;
  Timer? _persistTimer;
  Timer? _repaginateTimer;
  Timer? _dismissReturnTimer;
  int _syncProgressGeneration = 0;
  String? _cachedPlainText;
  String? _cachedContentSource;
  Size? _lastViewportSize;
  Size? _pageViewportSize;
  String? _lastLoadedChapterId;

  // ── 阅读会话 ──
  late final DateTime _sessionStart = DateTime.now();

  bool get _isPageMode => supportsPageMode && _settings.readingMode == 'page';

  // ── 抽象成员实现（ReaderViewPageMixin + ReaderViewPageBuilders 共用） ──
  @override
  ReaderPositionTracker get positionTracker => _positionTracker;
  @override
  ReaderPageTurnController get pageTurnController => _pageTurnController;
  @override
  ReaderContentLoader? get contentLoader => _contentLoader;
  @override
  set contentLoader(ReaderContentLoader? v) => _contentLoader = v;
  @override
  ScrollController get scrollController => _scrollController;

  @override
  ReaderContinuousScrollController get continuousScrollController =>
      _continuousScrollController;
  @override
  ScrollRestore get restore => _restore;
  @override
  ReaderViewSettings get settings => _settings;
  @override
  set settings(ReaderViewSettings v) {
    _settings = v;
    _annotationHandler?.updateSettings(v);
  }

  @override
  String get currentChapterId => _currentChapterId;
  @override
  set currentChapterId(String v) {
    _currentChapterId = v;
    _annotationHandler?.updateChapter(v);
  }

  @override
  ReaderChapterContent? get cachedContent => _cachedContent;
  @override
  set cachedContent(ReaderChapterContent? v) => _cachedContent = v;
  @override
  ReaderAnnotationHandler? get annotationHandler => _annotationHandler;
  @override
  dynamic get flatPages => _flatPages;
  @override
  set flatPages(dynamic v) => _flatPages = v;
  @override
  int get currentPageIndex => _currentPageIndex;
  @override
  set currentPageIndex(int v) => _currentPageIndex = v;
  @override
  int get pageModePage => _pageModePage;
  @override
  set pageModePage(int v) => _pageModePage = v;
  @override
  double get scrollProgress => _scrollProgress;
  @override
  set scrollProgress(double v) => _scrollProgress = v;
  @override
  DateTime? get lastAppliedProgressAt => _lastAppliedProgressAt;
  @override
  set lastAppliedProgressAt(DateTime? v) => _lastAppliedProgressAt = v;

  /// 记录本机推送的进度快照，供回声判定使用。
  @override
  void noteOwnProgressSave(ReaderProgressSnapshot snapshot) {
    _lastOwnProgressSave = snapshot;
  }

  /// 判断服务端回灌的进度快照是否为本机刚保存的自身回声。
  ///
  /// 本机保存→服务端落库→详情 provider 刷新会产生一条与本地快照内容
  /// 相同、时间戳略新的记录；不跳过就会把刚保存的位置重新施加回 UI，
  /// 表现为每次滚动/点击后内容回跳"刷新"。跨设备更新时间必然晚于
  /// 本机保存时刻，不受影响。
  bool _isOwnProgressEcho(ReaderProgressSnapshot snapshot, DateTime at) {
    final own = _lastOwnProgressSave;
    final ownAt = own?.updatedAt;
    if (own == null || ownAt == null) {
      return false;
    }
    return own.chapterId == snapshot.chapterId &&
        (own.charOffset - snapshot.charOffset).abs() <= 64 &&
        (own.progress - snapshot.progress).abs() <= 0.002 &&
        at.isBefore(ownAt.add(const Duration(seconds: 30)));
  }

  @override
  double? get pendingChapterProgress => _pendingChapterProgress;
  @override
  set pendingChapterProgress(double? v) => _pendingChapterProgress = v;
  @override
  int? get pendingRestoreCharOffset => _pendingRestoreCharOffset;
  @override
  set pendingRestoreCharOffset(int? v) => _pendingRestoreCharOffset = v;
  @override
  ReaderChapterNavigationIntent get chapterNavigationIntent =>
      _chapterNavigationIntent;
  @override
  set chapterNavigationIntent(ReaderChapterNavigationIntent v) =>
      _chapterNavigationIntent = v;
  @override
  bool get isRestoringProgress => _isRestoringProgress;
  @override
  set isRestoringProgress(bool v) => _isRestoringProgress = v;
  @override
  bool get modeSwitchInProgress => _modeSwitchInProgress;
  @override
  set modeSwitchInProgress(bool v) => _modeSwitchInProgress = v;
  @override
  int? get modeSwitchAnchor => _modeSwitchAnchor;
  @override
  set modeSwitchAnchor(int? v) => _modeSwitchAnchor = v;
  @override
  int get restoreTargetCharOffset => _restoreTargetCharOffset;
  @override
  set restoreTargetCharOffset(int v) => _restoreTargetCharOffset = v;
  @override
  DateTime get restoreSilenceUntil => _restoreSilenceUntil;
  @override
  set restoreSilenceUntil(DateTime v) => _restoreSilenceUntil = v;
  @override
  DateTime get lastPointerDownTime => _lastPointerDownTime;
  @override
  set lastPointerDownTime(DateTime v) => _lastPointerDownTime = v;
  @override
  ReaderProgressSnapshot? get returnToProgressSnapshot =>
      _returnToProgressSnapshot;
  @override
  set returnToProgressSnapshot(ReaderProgressSnapshot? v) =>
      _returnToProgressSnapshot = v;
  @override
  bool get showReturnControl => _showReturnControl;
  @override
  set showReturnControl(bool v) => _showReturnControl = v;
  @override
  Timer? get returnControlTimer => _returnControlTimer;
  @override
  set returnControlTimer(Timer? v) => _returnControlTimer = v;
  @override
  Timer? get dismissReturnTimer => _dismissReturnTimer;
  @override
  set dismissReturnTimer(Timer? v) => _dismissReturnTimer = v;
  @override
  bool get isAnimating => _isAnimating;
  @override
  set isAnimating(bool v) => _isAnimating = v;
  @override
  bool get isSwitchingChapter => _isSwitchingChapter;
  @override
  set isSwitchingChapter(bool v) => _isSwitchingChapter = v;
  @override
  bool get isLoadingChapter => _isLoadingChapter;
  @override
  set isLoadingChapter(bool v) => _isLoadingChapter = v;
  @override
  bool get showChapterLoadingOverlay => _showChapterLoadingOverlay;
  @override
  set showChapterLoadingOverlay(bool v) => _showChapterLoadingOverlay = v;
  @override
  Timer? get chapterLoadingTimer => _chapterLoadingTimer;
  @override
  set chapterLoadingTimer(Timer? v) => _chapterLoadingTimer = v;
  @override
  int get loadGeneration => _loadGeneration;
  @override
  set loadGeneration(int v) => _loadGeneration = v;
  @override
  ReaderViewSettings? get pendingSettings => _pendingSettings;
  @override
  set pendingSettings(ReaderViewSettings? v) => _pendingSettings = v;
  @override
  bool get showControls => _showControls;
  @override
  set showControls(bool v) => _showControls = v;
  @override
  bool get showTts => _showTts;
  @override
  set showTts(bool v) => _showTts = v;
  @override
  bool get isHoveringControls => _isHoveringControls;
  @override
  set isHoveringControls(bool v) => _isHoveringControls = v;
  @override
  bool get isBookmarked => _isBookmarked;
  @override
  set isBookmarked(bool v) => _isBookmarked = v;
  @override
  bool get isInBookshelf => _isInBookshelf;
  @override
  set isInBookshelf(bool v) => _isInBookshelf = v;
  @override
  bool get bookmarkBusy => _bookmarkBusy;
  @override
  set bookmarkBusy(bool v) => _bookmarkBusy = v;
  @override
  bool get bookshelfBusy => _bookshelfBusy;
  @override
  set bookshelfBusy(bool v) => _bookshelfBusy = v;
  @override
  Timer? get hideTimer => _hideTimer;
  @override
  set hideTimer(Timer? v) => _hideTimer = v;
  @override
  Timer? get persistTimer => _persistTimer;
  @override
  set persistTimer(Timer? v) => _persistTimer = v;
  @override
  Timer? get repaginateTimer => _repaginateTimer;
  @override
  set repaginateTimer(Timer? v) => _repaginateTimer = v;
  @override
  ReaderProgressSaveCoordinator get progressSaveCoordinator =>
      _progressSaveCoordinator;
  @override
  int get syncProgressGeneration => _syncProgressGeneration;
  @override
  set syncProgressGeneration(int v) => _syncProgressGeneration = v;
  @override
  String? get cachedPlainText => _cachedPlainText;
  @override
  set cachedPlainText(String? v) => _cachedPlainText = v;
  @override
  String? get cachedContentSource => _cachedContentSource;
  @override
  set cachedContentSource(String? v) => _cachedContentSource = v;
  @override
  Size? get lastViewportSize => _lastViewportSize;
  @override
  set lastViewportSize(Size? v) => _lastViewportSize = v;
  @override
  DateTime get sessionStart => _sessionStart;
  @override
  ReaderChapterLoadCoordinator get chapterLoadCoordinator =>
      _chapterLoadCoordinator;
  @override
  ReaderPageLocator get pageLocator => _pageLocator;
  @override
  String? get lastLoadedChapterId => _lastLoadedChapterId;
  @override
  set lastLoadedChapterId(String? v) => _lastLoadedChapterId = v;
  @override
  bool get isPageMode => _isPageMode;
  @override
  String get currentChapterTitle => _currentChapterTitle;
  @override
  double get bookProgress => _bookProgress;
  @override
  String get itemId => widget.itemId;
  @override
  bool get exitRequested => _exitRequested;
  @override
  set exitRequested(bool value) => _exitRequested = value;
  @override
  Map<String, dynamic>? get initialProgressPayload =>
      widget.initialProgressPayload;
  @override
  Size? get pageViewportSize => _pageViewportSize;
  @override
  set pageViewportSize(Size? value) => _pageViewportSize = value;
  @override
  dynamic buildFlatPages() => _buildFlatPages();

  @override
  void onReaderSelectionActive(bool active) {
    if (_selectionActive == active || !mounted) {
      return;
    }
    setState(() => _selectionActive = active);
  }

  @override
  bool get selectionActive => _selectionActive;

  @override
  void clearReaderSelection() {
    FocusManager.instance.primaryFocus?.unfocus();
    _selectionActive = false;
  }

  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  List<_FlatPageEntry> _buildFlatPages() {
    final result = <_FlatPageEntry>[];
    final chapters = contentLoader!.allChapters;
    for (var ci = 0; ci < chapters.length; ci++) {
      final data = contentLoader!.get(chapters[ci].id, settings);
      if (data == null || data.slices.isEmpty) continue;
      for (var i = 0; i < data.slices.length; i++) {
        result.add(
          _FlatPageEntry(
            chapterId: chapters[ci].id,
            localPageIndex: i,
            chapterTitle: data.content.title,
            chapterIndex: ci,
          ),
        );
      }
    }
    return result;
  }

  /// 当前章节标题，用于加载遮罩显示。
  String get _currentChapterTitle {
    // 优先从已加载的章节内容获取
    if (_cachedContent?.title.isNotEmpty == true) return _cachedContent!.title;
    // 从 contentLoader 获取
    final data = _contentLoader?.getByChapterId(_currentChapterId);
    if (data != null) return data.content.title;
    // 从章节列表获取
    final chapters = _contentLoader?.allChapters ?? [];
    final idx = chapters.indexWhere((c) => c.id == _currentChapterId);
    if (idx >= 0 && chapters[idx].title.isNotEmpty) return chapters[idx].title;
    return '';
  }

  /// 全书进度百分比（0.0-1.0），用于显示和同步。
  double get _bookProgress {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    if (parsedBook == null || parsedBook.chapters.isEmpty) {
      return _scrollProgress.clamp(0.0, 1.0);
    }
    final chapterCharCounts =
        parsedBook.chapters.map((c) => c.charCount).toList();
    // 当前章节使用实际解析的 totalChars（与 parsedBook.charCount 可能因 HTML 标签不同）
    final chapterData = _contentLoader?.getByChapterId(_currentChapterId);
    final currentChapterIdx =
        _contentLoader?.allChapters.indexWhere(
          (c) => c.id == _currentChapterId,
        ) ??
        0;
    if (chapterData != null && currentChapterIdx < chapterCharCounts.length) {
      chapterCharCounts[currentChapterIdx] = chapterData.totalChars;
    }
    final totalBookChars = chapterCharCounts.fold<int>(0, (s, c) => s + c);
    if (totalBookChars <= 0) return _scrollProgress.clamp(0.0, 1.0);

    // 当前章节之前的字符数之和
    int previousChars = 0;
    for (
      var i = 0;
      i < currentChapterIdx && i < chapterCharCounts.length;
      i++
    ) {
      previousChars += chapterCharCounts[i];
    }
    // 当前章节内的字符数：直接用 tracker 的 charOffset，不依赖 _scrollProgress
    final chapterChars = chapterData?.totalChars ?? 0;
    final currentChapterChars = _positionTracker.charOffset.clamp(
      0,
      chapterChars,
    );

    return ((previousChars + currentChapterChars) / totalBookChars).clamp(
      0.0,
      1.0,
    );
  }

  late ReaderProgressSyncService _progressSync;

  @override
  void initState() {
    super.initState();
    _progressSync = ref.read(readerProgressSyncServiceProvider);
    _windowChromeController = ref.read(windowChromeControllerProvider.notifier);
    _progressSaveCoordinator = ReaderProgressSaveCoordinator(
      writer: (snapshot) async {
        ReaderProgressBackupWeb.save(
          itemId: widget.itemId,
          chapterId: snapshot.chapterId,
          charOffset: snapshot.charOffset,
          chapterProgress: snapshot.chapterProgress,
        );
        await ReaderLocalProgress.save(
          itemId: widget.itemId,
          chapterProgress: snapshot.chapterProgress,
          mode: snapshot.mode,
          chapterId: snapshot.chapterId,
          charOffset: snapshot.charOffset,
        );
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          readerDebugLog('ReaderView: local progress save failed: $error');
        }
      },
    );
    if (kIsWeb) BrowserContextMenu.disableContextMenu();
    loadSettings();
    checkBookmarkState();
    scrollController.addListener(onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 分页测量只跟随系统缩放；应用字体档位变化不应触发阅读器重排。
    _lastTextScale = FontScaleScope.systemScalerOf(context).scale(1);
    _annotationHandler ??= ReaderAnnotationHandler(
      itemId: widget.itemId,
      chapterId: widget.chapterId,
      dataManager: ref.read(readerDataManagerProvider),
      settings: _settings,
      onAnnotationsChanged: () {
        if (mounted) setState(() {});
      },
    )..load();
  }

  @override
  void dispose() {
    ReaderSessionRecorder.recordSession(
      itemId: widget.itemId,
      sessionStart: _sessionStart,
    );
    // dispose 时用 localStorage 同步备份（不依赖 ref，不读 scroll controller 位置）。
    // _syncProgressSync 不能在此调用 — ref 已卸载，_bookProgress 会崩溃。
    if (!_restore.shouldSuppressWrites && _scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) {
        final contentY = _scrollController.offset + viewportAnchorY;
        final charOffset =
            _contentLoader?.contentYToCharOffset(
              _currentChapterId,
              contentY,
              pageWidth: computePageWidth(),
              settings: _settings,
              textScale: _lastTextScale,
            ) ??
            0;
        // chapterProgress 从 charOffset 推导
        final totalChars =
            _contentLoader?.getByChapterId(_currentChapterId)?.totalChars ?? 0;
        final progress =
            totalChars > 0 ? (charOffset / totalChars).clamp(0.0, 1.0) : 0.0;
        ReaderProgressBackupWeb.save(
          itemId: widget.itemId,
          chapterId: _currentChapterId,
          charOffset: charOffset,
          chapterProgress: progress,
        );
        // 退出时向服务端强制补报最终位置（节流不适用于离场）
        unawaited(
          _progressSync.sync(
            itemId: widget.itemId,
            charOffset: charOffset,
            progressPercent: progress,
            readingMode: 'scroll',
            chapterId: _currentChapterId,
          ),
        );
      }
    }
    _windowChromeLease?.release();
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    _hideTimer?.cancel();
    _persistTimer?.cancel();
    _repaginateTimer?.cancel();
    _returnControlTimer?.cancel();
    _dismissReturnTimer?.cancel();
    _chapterLoadingTimer?.cancel();
    unawaited(_progressSaveCoordinator.dispose());
    _restore.cancel();
    _chapterLoadCoordinator.cancel();
    _pageLocator.cancel();
    _pageTurnController.dispose();
    _continuousScrollController.dispose();
    _scrollController.dispose();
    // 释放 parsed blocks 缓存（离开阅读页后不再需要）
    _contentLoader?.invalidateAll();
    _contentLoader = null;
    super.dispose();
  }

  void _scheduleReaderBuildWork({
    required ParsedBook? latestParsedBook,
    required ReaderChapterContent? loadedContent,
    required List<ReaderChapter> chapters,
    required bool providerHasError,
  }) {
    if (latestParsedBook != null) {
      _pendingParsedBook = latestParsedBook;
    }
    _pendingReaderContent = loadedContent;
    _pendingReaderChapters = List<ReaderChapter>.of(chapters);
    _pendingReaderProviderError = providerHasError;
    if (_readerBuildWorkScheduled) {
      return;
    }
    _readerBuildWorkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readerBuildWorkScheduled = false;
      if (!mounted) {
        return;
      }

      final parsedBook = _pendingParsedBook;
      final content = _pendingReaderContent;
      final chapters = _pendingReaderChapters ?? const <ReaderChapter>[];
      final providerHasError = _pendingReaderProviderError;
      _pendingParsedBook = null;
      _pendingReaderContent = null;
      _pendingReaderChapters = null;
      _pendingReaderProviderError = false;

      if (parsedBook != null) {
        _parsedBookSnapshot = parsedBook;
        unawaited(loadChapterContentIfNeeded(parsedBook));
      }

      var stateChanged = false;
      if (_isSwitchingChapter && providerHasError && parsedBook == null) {
        _isSwitchingChapter = false;
        _showChapterLoadingOverlay = false;
        stateChanged = true;
      }

      if (content != null) {
        if (_contentLoader == null) {
          initContentLoader(chapters);
          stateChanged = true;
        }
        final chapterData = _contentLoader?.get(_currentChapterId, _settings);
        if (!_isLoadingChapter &&
            (_isSwitchingChapter || chapterData == null)) {
          unawaited(loadCurrentChapter(content));
        }
      }

      if (stateChanged && mounted) {
        setState(() {});
      }
    });
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));
    final bookAsync = ref.watch(parsedBookProvider(widget.itemId));
    if (detailAsync.asData?.value.item.isComic == false) {
      ref.watch(cachedBookHandleProvider(widget.itemId));
      ref.watch(epubParserServiceProvider(widget.itemId));
    }

    // 从已解析的书籍中按需加载当前章节内容
    final latestParsedBook = bookAsync.asData?.value;
    final parsedBook = latestParsedBook ?? _parsedBookSnapshot;
    final loadedContent = _cachedContent;
    final chapters =
        parsedBook?.chapters
            .asMap()
            .entries
            .map(
              (e) => ReaderChapter.fromParsed(
                e.key,
                e.value.title,
                contentPath: e.value.contentPath,
              ),
            )
            .toList() ??
        <ReaderChapter>[];
    _scheduleReaderBuildWork(
      latestParsedBook: latestParsedBook,
      loadedContent: loadedContent,
      chapters: chapters,
      providerHasError: bookAsync.hasError && parsedBook == null,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        clearReaderSelection();
        syncProgressSync();
        safePop();
      },
      child: Scaffold(
        backgroundColor: _settings.surfaceColor,
        body: detailAsync.when(
          data: (detail) {
            if (bookAsync.hasError && parsedBook == null) {
              return AppErrorView(
                message: AppLocalizations.of(context).readerChapterLoadFailed,
                onBack: safePop,
                onRetry: () {
                  ref.invalidate(parsedBookProvider(widget.itemId));
                },
              );
            }
            final content = loadedContent ?? _cachedContent;

            if (kDebugMode) {
              readerDebugLog(
                'ReaderView build: content=${content != null}, _contentLoader=${_contentLoader != null}, _isLoadingChapter=$_isLoadingChapter, chapters=${chapters.length}',
              );
            }
            if (content == null || _contentLoader == null) {
              if (parsedBook != null &&
                  _chapterLoadCoordinator.hasFailed(_currentChapterId)) {
                return AppErrorView(
                  message: AppLocalizations.of(context).readerChapterLoadFailed,
                  onBack: safePop,
                  onRetry: () {
                    _chapterLoadCoordinator.clearFailure(_currentChapterId);
                    setState(() {});
                    unawaited(loadChapterContentIfNeeded(parsedBook));
                  },
                );
              }
              if (kDebugMode) {
                readerDebugLog(
                  'ReaderView: showing skeleton (content=${content != null}, loader=${_contentLoader != null})',
                );
              }
              if (_isSwitchingChapter && !_showChapterLoadingOverlay) {
                return ColoredBox(color: _settings.surfaceColor);
              }
              return _buildReaderSkeleton();
            }

            // Provider 数据更新检测：仅在章节加载完成后检查
            if (!_isLoadingChapter &&
                _contentLoader!.get(_currentChapterId, _settings) != null) {
              final latestSnapshot = ReaderProgressSnapshot.fromServer(
                detailAsync.asData?.value.progress,
              );
              final latestTime = latestSnapshot.updatedAt;
              final shouldApply =
                  latestSnapshot.chapterId == _currentChapterId &&
                  latestTime != null &&
                  (_lastAppliedProgressAt == null ||
                      latestTime.isAfter(_lastAppliedProgressAt!)) &&
                  !_isOwnProgressEcho(latestSnapshot, latestTime);
              if (shouldApply) {
                scheduleProgressSnapshotApply(latestSnapshot);
              }
            }

            return _buildReader(detail, content);
          },
          error:
              (e, _) => AppErrorView(
                message: e.toString(),
                onBack: safePop,
                onRetry:
                    () =>
                        ref.invalidate(readerItemDetailProvider(widget.itemId)),
              ),
          loading: _buildReaderSkeleton,
        ),
      ),
    );
  }

  // ── Build ──

  Widget _buildReaderSkeleton() {
    return Scaffold(
      backgroundColor: _settings.surfaceColor,
      body: SafeArea(child: ReaderContentSkeleton(settings: _settings)),
    );
  }

  Widget _buildReader(ReaderItemDetail detail, ReaderChapterContent content) {
    _annotationHandler?.chapters =
        _contentLoader?.allChapters ?? detail.chapters;

    return Focus(
      autofocus: true,
      onKeyEvent:
          (node, event) => _handleReaderKeyEvent(event, detail, content),
      child: _buildReaderStack(detail, content),
    );
  }

  Widget _buildReaderStack(
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) {
    final viewport = MediaQuery.sizeOf(context);
    final readerLayout = ReaderControlLayout.resolve(
      viewport: viewport,
      fontSize: _settings.fontSize,
      textScale: FontScaleScope.systemScalerOf(context).scale(1),
    );
    final screenWidth = viewport.width;
    final contentWidth = math.min(screenWidth, readerLayout.contentFrameWidth);
    final offset = (screenWidth - contentWidth) / 2;
    final edgeWidth = (contentWidth * 0.12).clamp(44.0, 72.0);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: _settings.immersiveMode,
      isPageMode: _isPageMode,
    );

    return Stack(
      children: [
        // 内容层：剔除应用字体档位仅保留系统缩放，保证自绘分页测量与渲染一致
        Positioned.fill(
          child: FontScaleScope.withSystemScaleOnly(
            context: context,
            child: Padding(
              key: const Key('readerContentViewportPadding'),
              padding: chromeLayout.contentPadding,
              child: _buildContent(content, detail),
            ),
          ),
        ),
        // 进度恢复加载遮罩：定位完成后自动消失
        // 内容未加载时 skeleton 已有加载指示器，不重复显示
        if (_isRestoringProgress && _cachedContent != null)
          Positioned.fill(
            child: ReaderDeferredRestoreOverlay(settings: _settings),
          ),
        // 点击区域（控制栏显示时禁用，翻页模式下由 ReaderPageView 自行处理）
        if (!_showControls && !_isPageMode && !_selectionActive) ...[
          // 左边缘：向上滚动
          Positioned(
            top: 35,
            left: 0,
            width: offset + edgeWidth,
            bottom: 16,
            child: SideTapZone(
              onTap: () => handleSideTap(detail, forward: false),
            ),
          ),
          // 右边缘：向下滚动
          Positioned(
            top: 35,
            left: offset + contentWidth - edgeWidth,
            right: 0,
            bottom: 16,
            child: SideTapZone(
              onTap: () => handleSideTap(detail, forward: true),
            ),
          ),
        ],
        // 控制栏显示时：全屏遮罩（点击任意位置关闭控制栏）
        if (_showControls)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _showControls = false);
              },
              child: const SizedBox.expand(),
            ),
          ),
        // 顶部栏（在遮罩之上，可接收点击）
        _buildTopBar(detail, content),
        // 底部栏（在遮罩之上，可接收点击）
        _buildBottomBar(detail, content),
        if (chromeLayout.showPersistentProgress && !_showControls)
          ReaderProgressIndicator(
            key: const Key('readerPersistentProgress'),
            settings: _settings,
            progress: _bookProgress,
            currentPage: _isPageMode ? _pageModePage : null,
            totalPages: null, // 懒分页不预知总页数
          ),
        ..._buildOverlays(content),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showChapterLoadingOverlay,
            child: AnimatedOpacity(
              opacity: _showChapterLoadingOverlay ? 1.0 : 0.0,
              duration:
                  animationsDisabled
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
              child: ColoredBox(
                color: _settings.surfaceColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _settings.accentColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentChapterTitle,
                        style: TextStyle(
                          color: _settings.onSurfaceVariantColor,
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ..._buildReaderPanels(detail, content, readerLayout),
      ],
    );
  }

  /// 构建章节列表面板（直接在 Stack 内渲染，不使用独立路由）
  Widget _buildChapterPanel(ReaderItemDetail detail) {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    final allChapters =
        parsedBook?.chapters
            .asMap()
            .entries
            .map(
              (e) => ReaderChapter.fromParsed(
                e.key,
                e.value.title,
                contentPath: e.value.contentPath,
                level: e.value.level,
              ),
            )
            .toList() ??
        detail.chapters;

    return ChapterPanel(
      chapters: allChapters,
      currentChapterId: _currentChapterId,
      settings: _settings,
      onChapterTap: (chapterId) {
        _closeReaderPanel();
        onChapterSelected(chapterId);
      },
      onDismiss: _closeReaderPanel,
      embedded: true,
    );
  }

  List<Widget> _buildOverlays(ReaderChapterContent content) => [
    if (_showTts)
      Positioned(
        bottom: _showControls ? 82 : 0,
        left: 0,
        right: 0,
        child: ReaderTtsControls(text: getPlainText(content.content)),
      ),
    if (_showReturnControl) buildReturnToProgressControl(),
  ];

  /// 底部浮动"返回原进度"控件（参考微信读书样式）。
  ///
  /// 底部栏显示时，控件上移到底部栏上方。

  Widget _buildTopBar(ReaderItemDetail detail, ReaderChapterContent content) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration:
            MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !_showControls,
          child: MouseRegion(
            onEnter: (_) => onHoverControls(true),
            onExit: (_) => onHoverControls(false),
            child: ReaderViewTopBar(
              settings: _settings,
              bookTitle: detail.item.title,
              chapterTitle: content.title,
              onBack: () {
                syncProgressSync();
                safePop();
              },
              onSearch: () => _toggleReaderPanel(ReaderPanelType.search),
              onShowShortcuts:
                  () => _toggleReaderPanel(ReaderPanelType.shortcuts),
              onAddBookmark:
                  _bookmarkBusy ? null : () => toggleBookmark(detail, content),
              onToggleBookshelf: () => toggleBookshelf(detail),
              onToggleTts: () {
                _hideTimer?.cancel();
                setState(() {
                  _panelCoordinator.close();
                  _showTts = !_showTts;
                });
              },
              onShowAnnotations:
                  () => _toggleReaderPanel(ReaderPanelType.annotations),
              isBookmarked: _isBookmarked,
              isInBookshelf: _isInBookshelf,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    ReaderItemDetail detail,
    ReaderChapterContent content,
  ) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration:
            MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !_showControls,
          child: MouseRegion(
            onEnter: (_) => onHoverControls(true),
            onExit: (_) => onHoverControls(false),
            child: ReaderViewBottomBar(
              settings: _settings,
              progress: _bookProgress,
              isPageMode: _isPageMode,
              onPrevious: () => _navigateReader(detail, forward: false),
              onNext: () => _navigateReader(detail, forward: true),
              onShowContents:
                  () => _toggleReaderPanel(ReaderPanelType.contents),
              onShowSettings:
                  () => _toggleReaderPanel(ReaderPanelType.settings),
              onToggleImmersive: _toggleReaderImmersive,
              onProgressSeek: (value) => _seekBookProgress(value),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ReaderChapterContent content, ReaderItemDetail detail) {
    if (kDebugMode) {
      readerDebugLog(
        'ReaderView: rendering content — '
        'mode=${_isPageMode ? "page" : "scroll"}, '
        'contentLength=${content.content.length}, '
        'flatPages=${_flatPages.length}',
      );
    }
    if (_isPageMode) return buildPageModeContent(content);
    return buildScrollModeContent(content, detail);
  }
}
