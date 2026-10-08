import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/scroll_restore.dart';
import 'package:omninest/app/appearance/application/font_scale_scope.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
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
import 'package:omninest/features/reader/presentation/widgets/reader_image_budget_notice.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_backup.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_tts_controls.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_bottom_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_indicator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_adaptive_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_find_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
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
import 'package:omninest/platform/android/reader_volume_key_service.dart';

part 'reader_view_page_commands.dart';
part 'reader_view_page_layout.dart';
part 'reader_view_page_progress.dart';
part 'reader_view_page_build_work.dart';
part 'reader_view_page_build.dart';

class ReaderViewPage extends ConsumerStatefulWidget {
  const ReaderViewPage({
    required this.itemId,
    required this.chapterId,
    this.entry,
    super.key,
  });

  final String itemId;
  final String chapterId;

  /// 路由进入语义（`chapter`=目录显式选章进章首，其余=续读恢复）。
  final String? entry;

  @override
  ConsumerState<ReaderViewPage> createState() => _ReaderViewPageState();
}

class _ReaderViewPageState extends ConsumerState<ReaderViewPage>
    with
        WidgetsBindingObserver,
        ReaderViewPageBuilders,
        ReaderViewPageSettingsMixin,
        ReaderViewPageControlsMixin,
        ReaderViewPageLibraryActionsMixin,
        ReaderViewPageMixin,
        ReaderViewPageInteractionMixin {
  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  // ── 核心组件 ──
  final _positionTracker = ReaderPositionTracker();
  ReaderContentLoader? _contentLoader;
  final ReaderPageTurnController _pageTurnController =
      ReaderPageTurnController();
  final ReaderPanelCoordinator _panelCoordinator = ReaderPanelCoordinator();
  final ReaderCommandGate _readerCommandGate = ReaderCommandGate();
  VoidCallback? _volumeKeyEventCancel;
  bool _volumeKeyPagingPushed = false;
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

  /// 页模式就绪页数通知器：PageNavigator 预取进度直连 ReaderPageView，
  /// 预取不再触发父级整页重建。
  final ValueNotifier<int> _pageCountNotifier = ValueNotifier<int>(0);
  int _pageModePage = 0;

  // ── 进度 ──
  // 章节内进度通知器：滚动/翻页热路径只更新此值，UI 消费者局部重建。
  final ValueNotifier<double> _scrollProgressNotifier = ValueNotifier<double>(
    0,
  );
  // 全书进度通知器：_bookProgress 计算是 O(章节)，用防抖避免逐帧重算。
  // null 表示清单或本章字符数尚不可用，不得退化成章内比例。
  final ValueNotifier<double?> _bookProgressNotifier = ValueNotifier<double?>(
    null,
  );
  Timer? _bookProgressRecomputeTimer;
  double _lastBookProgressInput = -1;
  DateTime? _lastAppliedProgressAt;
  ReaderProgressSnapshot? _lastOwnProgressSave; // 本机最近一次推送的进度快照
  // 清单版本缓存：dispose 路径不能读 Provider，写入与降级判定都用这份缓存。
  int? _manifestVersionCache;
  double? _pendingChapterProgress; // 恢复时的章节进度比例（0-1）
  int? _pendingRestoreCharOffset; // 模式切换时待恢复的字符偏移（用于精确像素定位）
  bool _isRestoringProgress = false; // 正在恢复阅读位置，显示加载遮罩
  bool _modeSwitchInProgress = false; // 模式切换中，首次翻页/滚动后清除
  int? _modeSwitchAnchor; // 模式切换时冻结的 charOffset，真实翻页或切章后释放
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
  // 被方向性守卫丢弃的同章远端进度，与是否显示其跳转提示。
  ReaderProgressSnapshot? _remoteProgressCandidate;
  bool _showRemoteProgressCue = false;
  Timer? _remoteProgressTimer;
  DateTime? _remoteProgressCueOfferedAt;

  // ── 并发控制 ──
  bool _isSwitchingChapter = false;
  bool _isLoadingChapter = false;
  bool _showChapterLoadingOverlay = false;
  Timer? _chapterLoadingTimer;
  int _loadGeneration = 0;

  // ── UI 状态 ──
  ReaderViewSettings _settings = ReaderViewSettings();
  late String _currentChapterId = widget.chapterId;
  ReaderChapterContent? _cachedContent;
  // 图片降级提示的关闭状态只属于当前这一章：切章后必须重新出现，
  // 否则一次关闭会把后续章节的缺图数一起静音。
  String? _dismissedImageBudgetChapterId;
  bool _showControls = false;
  bool _showTts = false;
  bool _isHoveringControls = false; // Web 端鼠标是否悬停在控件栏上
  bool _isBookmarked = false;
  // null 表示详情尚未加载且用户未切换过书架状态；顶栏按详情初始值派生。
  bool? _bookshelfOverride;
  bool _bookmarkBusy = false;
  bool _bookshelfBusy = false;
  bool _selectionActive = false;
  bool _exitRequested = false;
  ParsedBook? _parsedBookSnapshot;
  // 章节列表缓存：parsedBook 身份不变时复用，避免每次 build O(章节) 重分配。
  ParsedBook? _chaptersCacheSource;
  List<ReaderChapter> _chaptersCache = const [];
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
  double _lastViewPaddingTop = 0;
  String? _lastLoadedChapterId;

  // ── 阅读会话 ──
  // 进入阅读页即计时：late final 会在首次读取（dispose）时才求值，
  // 导致会话时长恒为 0，统计永不入队。
  final DateTime _sessionStart = DateTime.now();

  // 前台活跃阅读时长：切后台/窗口隐藏的挂机时间不计入阅读统计。
  DateTime _lastResumedAt = DateTime.now();
  Duration _accumulatedActive = Duration.zero;
  bool _lifecycleReading = true;

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
  int get pageModePage => _pageModePage;
  @override
  set pageModePage(int v) => _pageModePage = v;
  @override
  ValueNotifier<int> get pageCountNotifier => _pageCountNotifier;
  @override
  double get scrollProgress => _scrollProgressNotifier.value;

  @override
  set scrollProgress(double v) {
    _scrollProgressNotifier.value = v;
    _scheduleBookProgressRecompute();
  }

  @override
  void refreshBookProgressNow() {
    if (!mounted) {
      return;
    }
    _bookProgressRecomputeTimer?.cancel();
    _bookProgressRecomputeTimer = null;
    _lastBookProgressInput = _scrollProgressNotifier.value;
    _bookProgressNotifier.value = _bookProgress;
  }

  @override
  DateTime? get lastAppliedProgressAt => _lastAppliedProgressAt;
  @override
  set lastAppliedProgressAt(DateTime? v) => _lastAppliedProgressAt = v;

  /// 记录本机推送的进度快照，供回声判定使用。
  @override
  void noteOwnProgressSave(ReaderProgressSnapshot snapshot) {
    _lastOwnProgressSave = snapshot;
  }

  @override
  ReaderProgressSnapshot? get lastOwnProgressSave => _lastOwnProgressSave;

  @override
  bool isOwnProgressEcho(ReaderProgressSnapshot snapshot) {
    final at = snapshot.updatedAt;
    if (at == null) {
      return false;
    }
    return _isOwnProgressEcho(snapshot, at);
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
  ReaderProgressSnapshot? get remoteProgressCandidate =>
      _remoteProgressCandidate;
  @override
  set remoteProgressCandidate(ReaderProgressSnapshot? v) =>
      _remoteProgressCandidate = v;
  @override
  bool get showRemoteProgressCue => _showRemoteProgressCue;
  @override
  set showRemoteProgressCue(bool v) => _showRemoteProgressCue = v;
  @override
  Timer? get remoteProgressTimer => _remoteProgressTimer;
  @override
  set remoteProgressTimer(Timer? v) => _remoteProgressTimer = v;
  @override
  DateTime? get remoteProgressCueOfferedAt => _remoteProgressCueOfferedAt;
  @override
  set remoteProgressCueOfferedAt(DateTime? v) =>
      _remoteProgressCueOfferedAt = v;
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
  bool get isInBookshelf => _bookshelfOverride ?? false;
  @override
  set isInBookshelf(bool v) => _bookshelfOverride = v;
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
  double? get bookProgress => _bookProgress;

  /// 通知器保存的是最近一次算出的值，读取不触碰 Provider，
  /// 因此 dispose 之后仍然可用；null 表示全书口径尚不可用。
  @override
  double? get lastKnownBookProgress => _bookProgressNotifier.value;

  @override
  int? get currentManifestVersion {
    if (!mounted) {
      return _manifestVersionCache;
    }
    final version =
        ref
            .read(readerItemDetailProvider(widget.itemId))
            .value
            ?.item
            .manifestVersion;
    if (version != null) {
      _manifestVersionCache = version;
    }
    return _manifestVersionCache;
  }

  @override
  int? get lastKnownManifestVersion => _manifestVersionCache;

  @override
  String get itemId => widget.itemId;
  @override
  bool get exitRequested => _exitRequested;
  @override
  set exitRequested(bool value) => _exitRequested = value;
  @override
  Size? get pageViewportSize => _pageViewportSize;
  @override
  set pageViewportSize(Size? value) => _pageViewportSize = value;

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

  late ReaderProgressSyncService _progressSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapterNavigationIntent =
        ReaderChapterNavigationIntent.intentForRouteEntry(widget.entry);
    _progressSync = ref.read(readerProgressSyncServiceProvider);
    _windowChromeController = ref.read(windowChromeControllerProvider.notifier);
    _progressSaveCoordinator = ReaderProgressSaveCoordinator(
      writer: (snapshot) async {
        ReaderProgressBackupWeb.save(
          itemId: widget.itemId,
          chapterId: snapshot.chapterId,
          charOffset: snapshot.charOffset,
          chapterProgress: snapshot.chapterProgress,
          manifestVersion: snapshot.manifestVersion,
          savedAt: snapshot.updatedAt,
        );
        await ReaderLocalProgress.save(
          itemId: widget.itemId,
          chapterProgress: snapshot.chapterProgress,
          mode: snapshot.mode,
          chapterId: snapshot.chapterId,
          charOffset: snapshot.charOffset,
          manifestVersion: snapshot.manifestVersion,
          updatedAt: snapshot.updatedAt,
        );
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          readerDebugLog('ReaderView: local progress save failed: $error');
        }
      },
    );
    if (kIsWeb) BrowserContextMenu.disableContextMenu();
    _volumeKeyEventCancel = ReaderVolumeKeyService.instance().addListener(
      _handleVolumeKeyEvent,
    );
    unawaited(
      loadSettings().then((_) {
        if (mounted) syncVolumeKeyPaging();
      }),
    );
    checkBookmarkState();
    scrollController.addListener(onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 分页测量只跟随系统缩放；应用字体档位变化不应触发阅读器重排。
    _lastTextScale = FontScaleScope.systemScalerOf(context).scale(1);
    // 活动期捕获视口与插边缓存：dispose 时元素已 defunct，
    // 禁止任何 MediaQuery 祖先查找（退出备份计算使用这份缓存）。
    _lastViewportSize = MediaQuery.sizeOf(context);
    _lastViewPaddingTop = MediaQuery.viewPaddingOf(context).top;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 仅以 paused（窗口隐藏/切后台）作为挂机边界：inactive 在桌面端
    // 弹窗、失焦时也会触发，不计入会造成正常阅读被误伤。
    if (state == AppLifecycleState.paused) {
      if (_lifecycleReading) {
        _accumulatedActive += DateTime.now().difference(_lastResumedAt);
        _lifecycleReading = false;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_lifecycleReading) {
        _lastResumedAt = DateTime.now();
        _lifecycleReading = true;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReaderSessionRecorder.recordSession(
      itemId: widget.itemId,
      sessionStart: _sessionStart,
      activeReading:
          _accumulatedActive +
          (_lifecycleReading
              ? DateTime.now().difference(_lastResumedAt)
              : Duration.zero),
    );
    // dispose 时用 localStorage 同步备份（不依赖 ref，不读 scroll controller 位置）。
    // _syncProgressSync 不能在此调用 — ref 已卸载，_bookProgress 会崩溃。
    // 判据用"是否仍在主动搬动落点"而不是"是否抑制写入"：监控期长达 5 秒，
    // 用它挡退出兜底会把这次会话的位置整个丢掉，而此刻的读数本身是可信的。
    if (!_restore.isActive) {
      final charOffset = _exitBackupCharOffset();
      if (charOffset != null) {
        final totalChars =
            _contentLoader?.getByChapterId(_currentChapterId)?.totalChars ?? 0;
        // chapterProgress 从 charOffset 推导
        final chapterProgress =
            totalChars > 0 ? (charOffset / totalChars).clamp(0.0, 1.0) : 0.0;
        // 上报口径必须是全书进度：章节内比例会在读到任意章尾时被
        // 误判为整本完成。取会话期间维护的防抖全书进度通知器；未知时
        // 跳过上报（本地记账已含 charOffset，恢复定位不依赖百分比）。
        final bookProgress = _bookProgressNotifier.value;
        // 退出快照、本地备份与服务端补报共用同一记录时刻：三处各自打戳会让
        // 同源的三份数据比出不同新旧——补报若用发送时刻，本地那条反而更早，
        // 围栏认不出它们同源；本地行若用写盘时刻，旧读数会被打成"刚刚"。
        final exitReportedAt = DateTime.now();
        ReaderProgressBackupWeb.save(
          itemId: widget.itemId,
          chapterId: _currentChapterId,
          charOffset: charOffset,
          chapterProgress: chapterProgress,
          manifestVersion: _manifestVersionCache,
          savedAt: exitReportedAt,
        );
        // 退出位置必须成为协调器里的最后一条待写进度：此前 pending 里
        // 还是最后一次滚动读数，dispose 的 flush 会用那份旧值再写一遍
        // 本地行与 localStorage 备份（savedAt 更晚），把刚写下的退出
        // 位置覆盖掉。
        _progressSaveCoordinator.schedule(
          ReaderProgressSnapshot(
            chapterId: _currentChapterId,
            charOffset: charOffset,
            bookProgress: bookProgress,
            chapterProgress: chapterProgress,
            mode: _isPageMode ? 'page' : 'scroll',
            manifestVersion: _manifestVersionCache,
            updatedAt: exitReportedAt,
          ),
        );
        if (bookProgress != null) {
          // 退出时向服务端强制补报最终位置（节流不适用于离场）
          unawaited(
            _progressSync.sync(
              itemId: widget.itemId,
              charOffset: charOffset,
              progressPercent: bookProgress,
              readingMode: _isPageMode ? 'page' : 'scroll',
              chapterId: _currentChapterId,
              manifestVersion: _manifestVersionCache,
              clientUpdatedAt: exitReportedAt,
            ),
          );
        }
      }
    }
    _windowChromeLease?.release();
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    _volumeKeyEventCancel?.call();
    if (_volumeKeyPagingPushed) {
      _volumeKeyPagingPushed = false;
      unawaited(
        ReaderVolumeKeyService.instance().setVolumeKeyPagingEnabled(
          enabled: false,
        ),
      );
    }
    _scrollProgressNotifier.dispose();
    _bookProgressNotifier.dispose();
    _pageCountNotifier.dispose();
    _bookProgressRecomputeTimer?.cancel();
    _hideTimer?.cancel();
    _persistTimer?.cancel();
    _repaginateTimer?.cancel();
    _returnControlTimer?.cancel();
    _dismissReturnTimer?.cancel();
    _remoteProgressTimer?.cancel();
    _chapterLoadingTimer?.cancel();
    unawaited(_progressSaveCoordinator.dispose());
    _restore.cancel();
    _chapterLoadCoordinator.cancel();
    _pageLocator.cancel();
    _pageTurnController.dispose();
    _scrollController.dispose();
    // 释放 parsed blocks 缓存（离开阅读页后不再需要）
    _contentLoader?.invalidateAll();
    _contentLoader = null;
    super.dispose();
  }

  /// dispose 兜底备份用的本章字符偏移；无法可信地确定时返回 null。
  ///
  /// 滚动模式用视口缓存换算（元素已 defunct，viewportAnchorY/computePageWidth
  /// 内的 MediaQuery 查找会断言，只能用 didChangeDependencies 捕获的视口）。
  /// 翻页模式按当前页起始字符偏移记入 positionTracker，因此直接取 tracker，
  /// 不能以 `hasClients` 作门——旧实现整块挂在 hasClients 下，页模式下这条
  /// 兜底从未执行过；模式切换后残留的 scroll client 也会拿旧章偏移解释新页。
  int? _exitBackupCharOffset() {
    if (_isPageMode || !_scrollController.hasClients) {
      if (positionTracker.chapterId != _currentChapterId) {
        return null;
      }
      return positionTracker.charOffset;
    }
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      return null;
    }
    final size = _lastViewportSize ?? _pageViewportSize;
    if (size == null || size.width <= 0) {
      return null;
    }
    final chromeLayout = ReaderChromeLayout.resolve(
      immersiveMode: _settings.immersiveMode,
      isPageMode: _isPageMode,
    );
    final topInset = _settings.immersiveMode ? 0.0 : _lastViewPaddingTop;
    final anchorY =
        (size.height - topInset - chromeLayout.viewportVerticalReserve) * 0.25;
    final controlLayout = ReaderControlLayout.resolve(
      viewport: size,
      fontSize: _settings.fontSize,
      textScale: _lastTextScale,
    );
    return _contentLoader?.contentYToCharOffset(
      _currentChapterId,
      _scrollController.offset + anchorY,
      pageWidth: controlLayout.textColumnWidth,
      settings: _settings,
      textScale: _lastTextScale,
    );
  }

  /// 将音量键拦截开关同步到原生层（仅 Android 实际生效）。
  @override
  void syncVolumeKeyPaging() {
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

  // ── Build ──

  @override
  Widget build(BuildContext context) => buildReaderView(context);
}
