import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/gestures.dart'
    show
        PointerScrollEvent,
        PointerSignalEvent,
        VelocityTracker,
        kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_interaction_gate.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_page_view_turn.dart';
part 'reader_page_view_slide.dart';
part 'reader_page_view_custom.dart';
part 'reader_page_view_render.dart';
part 'reader_page_spread.dart';
part 'reader_page_curl.dart';
part 'reader_page_view_curl.dart';

/// 离屏抓图页首帧绘制就绪通知：漫画等异步解码页面首帧落盘后派发，
/// 供 `ReaderPageView` 背面离屏抓图立即放行，避免截到空白或加载占位。
class ReaderSnapshotFrameReadyNotification extends Notification {
  const ReaderSnapshotFrameReadyNotification();
}

/// 翻页动画模式。
enum PageTurnMode {
  /// 水平滑动：使用原生 PageView。
  slide,

  /// 覆盖：目标页从右侧滑入覆盖当前页。
  cover,

  /// 淡入淡出：交叉渐变。
  fade,
}

/// 翻页状态模型。
class PagedState {
  PagedState({
    required this.chapterId,
    this.pageIndex = 0,
    this.pageCount = 0,
    this.hasMore = true,
    this.isPaginating = false,
    this.charOffset = 0,
    this.hasPreviousChapter = false,
    this.hasNextChapter = false,
  });

  final String chapterId;
  final int pageIndex;
  final int pageCount;
  final bool hasMore;
  final bool isPaginating;
  final int charOffset;
  final bool hasPreviousChapter;
  final bool hasNextChapter;

  bool get isFirstPage => pageIndex == 0;
  bool get isLastPage => !hasMore && pageIndex >= pageCount - 1;
}

/// 翻页回调接口。
abstract class PageTurnCallbacks {
  void onPageChanged(int pageIndex);
  void onPreviousChapter();
  void onNextChapter();
  void onToggleControls();
}

/// 页面外部控制栏和快捷键使用的翻页控制器。
///
/// 纯 UI 翻页命令总线（next/previous），按 AGENTS 允许 ChangeNotifier；
/// 阅读位置与进度同步由 application/ReaderProgress 管理。
class ReaderPageTurnController extends ChangeNotifier {
  int _sequence = 0;
  int _direction = 0;

  int get sequence => _sequence;
  int get direction => _direction;

  void next() => _dispatch(1);

  void previous() => _dispatch(-1);

  void _dispatch(int direction) {
    _direction = direction;
    _sequence++;
    notifyListeners();
  }
}

/// 手势驱动的翻页主控 Widget。
///
/// slide 模式使用原生 [PageView.builder] + 透明交互层。
/// cover/fade 使用自定义动画 + 手势。
class ReaderPageView extends StatefulWidget {
  const ReaderPageView({
    required this.state,
    required this.pageBuilder,
    required this.callbacks,
    required this.surfaceColor,
    this.selectionActive = false,
    this.onClearSelection,
    this.controller,
    this.turnMode = PageTurnMode.slide,
    this.pageCountNotifier,
    this.spread = false,
    this.paperEdgeColor,
    this.snapshotPageBuilder,
    this.crossChapterSnapshotBuilder,
    this.prepareSnapshotPage,
    this.showPaperGrain = true,
    this.contentRevision,
    this.bookmarked = false,
    this.reverse = false,
    this.dragEnabled = true,
    this.allowMouseDrag = false,
    super.key,
  });

  final PagedState state;

  /// 构建指定页码的 Widget。返回 null 表示页面不存在（章节结束）。
  final Widget? Function(int pageIndex) pageBuilder;

  /// 离屏抓图专用的轻量纯展示页构造器（无 SelectionArea / FocusNode）；缺省回退 pageBuilder。
  final Widget? Function(int pageIndex)? snapshotPageBuilder;

  /// 跨章卷页时的邻章快照页构造器（+1 下一章首页，-1 上一章末页）。
  final Widget? Function(int chapterDelta)? crossChapterSnapshotBuilder;

  /// 离屏抓图前等待目标页异步资源（如漫画图片字节与解码）就绪。
  /// 返回 false 时放弃本轮抓图，彻底杜绝截到 Loading 菊花。
  final Future<bool> Function(int pageIndex)? prepareSnapshotPage;

  /// 是否在跨页书面上叠加纸纹噪点；漫画深色页可置为 false 避免画面发灰。
  final bool showPaperGrain;

  /// 纸叠边缘色（样例 `--paper-edge`）；缺省由 surfaceColor 压暗派生。
  final Color? paperEdgeColor;
  final Object? contentRevision;
  final bool bookmarked;
  final PageTurnCallbacks callbacks;
  final Color surfaceColor;
  final bool selectionActive;
  final VoidCallback? onClearSelection;
  final ReaderPageTurnController? controller;
  final PageTurnMode turnMode;

  /// 预取就绪页数通知器：变化只同步本 State 的 [_ReaderPageViewState._localPageCount]，
  /// 不触发父级整页重建。
  final ValueNotifier<int>? pageCountNotifier;

  /// 双页跨页（样例 `.bookview .spread`）：左右并排两页、中缝 70px。
  /// 只改呈现与翻页步进，页码范围、页数与进度口径都不变。
  final bool spread;

  /// RTL 翻页方向（日漫从右向左读）：翻转左右点击热区、拖拽方向与 3D 翻页映射。
  final bool reverse;

  /// 是否允许手势拖拽翻页；漫画放大态（scale > 1.02）置为 false 防止与平移冲突。
  final bool dragEnabled;

  /// Slide 模式下是否允许鼠标拖拽翻页（默认关闭，把正文区鼠标拖动留给选字；漫画可开启）。
  final bool allowMouseDrag;

  @override
  State<ReaderPageView> createState() => _ReaderPageViewState();
}

class _ReaderPageViewState extends State<ReaderPageView>
    with TickerProviderStateMixin {
  /// 扩展方法使用的状态更新入口：mounted 检查后调用 setState。
  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  /// 将视觉卷页方向映射为逻辑前进（true）或后退（false），兼容 RTL。
  bool _isLogicalForward(CurlDirection dir) =>
      widget.reverse ? dir == CurlDirection.prev : dir == CurlDirection.next;

  /// 将逻辑翻页方向映射为视觉卷页方向（next=右向左卷，prev=左向右卷）。
  CurlDirection _curlDirectionFor(bool logicalForward) =>
      widget.reverse
          ? (logicalForward ? CurlDirection.prev : CurlDirection.next)
          : (logicalForward ? CurlDirection.next : CurlDirection.prev);

  // ── PageView (slide 模式) ──
  PageController? _pageController;

  // ── 自定义动画 (cover/fade 模式) ──
  AnimationController? _animController;
  final ValueNotifier<double> _flipProgressNotifier = ValueNotifier<double>(0);
  double get _flipProgress => _flipProgressNotifier.value;
  set _flipProgress(double v) => _flipProgressNotifier.value = v;
  bool _isForward = true;
  bool _isAnimating = false;
  bool _isDragging = false;
  bool _slideScrolling = false;
  bool _transitionInFlight = false;
  bool _boundaryRequestInFlight = false;
  double _totalDeltaX = 0;
  double _dragStartX = 0;
  int _animGeneration = 0;
  CurlDirection? _dragLockedDir;
  Size? _lastCurlLayoutSize;
  int _pendingSlideBoundaryDirection = 0;

  // ── 页面缓存 ──
  Widget? _currentPageWidget;
  Widget? _targetPageWidget;

  // ── 双向卷页状态与双槽快照缓存（同时预热 next 与 prev）──
  final ValueNotifier<CurlFrame> _curlFrameNotifier = ValueNotifier<CurlFrame>(
    CurlFrame.idle,
  );
  CurlGrabConfig _activeCurlConfig = CurlGrabConfig.defaultNext;
  final Map<
    CurlDirection,
    ({ui.Image front, ui.Image back, String chapterId, int pageIndex})
  >
  _curlPairs = {};
  final Set<CurlDirection> _capturingDirs = {};
  bool _awaitingCurlStart = false;
  bool _slideStageHovered = false;
  int _curlToken = 0;
  Timer? _curlWarmupTimer;
  Completer<void>? _backCaptureLock;
  Completer<void>? _backFrameReadyCompleter;
  Timer? _commitResetFallbackTimer;
  Widget? _pendingBackCaptureWidget;
  _SpreadSide _pendingBackCaptureSide = _SpreadSide.left;
  final GlobalKey _liveLeftKey = GlobalKey();
  final GlobalKey _liveRightKey = GlobalKey();
  final GlobalKey _liveSingleKey = GlobalKey();
  final GlobalKey _singleBackCaptureKey = GlobalKey();

  // ── 本地页数跟踪（slide 模式探测扩展） ──
  int _localPageCount = 0;
  bool _probingNext = false;

  // ── 交互层：点击 vs 拖动判断 ──
  Offset? _pointerDownPosition;
  bool _pointerMoved = false;
  bool _primaryPointerDown = false;
  PointerDeviceKind? _pointerKind;

  /// 甩动识别：Listener 不经过手势竞技场，速度必须自行采样，
  /// 否则松手时只能拿到硬编码零速度，快速轻扫无法翻页。
  VelocityTracker? _velocityTracker;
  static const _tapMoveThreshold = 6.0;

  // ── 热区比例 ──
  static const _leftZoneRatio = 0.25;
  static const _rightZoneRatio = 0.25;

  // ── 配置 ──
  static const _commitThreshold = 0.35;

  /// 样例 `.bookview .sw-track`：`transform .36s cubic-bezier(.22,.8,.24,1)`。
  static const _slideTurnDuration = DesktopMotion.readerSlide;
  static const _turnCurve = DesktopMotion.ease;

  /// 样例 leaf：`820ms cubic-bezier(.5,.05,.3,1)`（`DesktopMotion.pageFlip`）。
  static int get _flipDurationMs => DesktopMotion.pageFlip.inMilliseconds;

  static const Duration _wheelThrottle = Duration(milliseconds: 320);

  // ── 待执行翻页意图（方案 §7-8）──
  // 控制器未挂载时保留意图并按帧重试，最多 4 帧；挂载后按最新
  // widget.state 重新解析目标，不缓存历史 index，超限显式放弃并留痕。
  int? _pendingTurnDirection;
  bool _pendingTurnAttachRetry = false;
  int _pendingTurnFrames = 0;
  static const int _maxPendingTurnFrames = 4;

  Timer? _boundaryResetTimer;

  /// 滚轮翻页节流：520ms 内只认一次，避免触控板惯性连翻。
  DateTime? _lastWheelAt;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onExternalPageCommand);
    widget.pageCountNotifier?.addListener(_onPageCountChanged);
    _initForMode();
    if (widget.turnMode == PageTurnMode.cover && widget.showPaperGrain) {
      unawaited(PaperGrainCache.ensureLoaded());
    }
    _scheduleIdleNextCurlWarmup();
  }

  /// 预取就绪页数直连：仅更新本地计数（事件时读点），不重建页面。
  void _onPageCountChanged() {
    final value = widget.pageCountNotifier?.value ?? _localPageCount;
    if (!mounted || value == _localPageCount) {
      return;
    }
    setState(() {
      _localPageCount = value;
    });
    _reconcilePagePositionIfIdle();
  }

  @override
  void didUpdateWidget(ReaderPageView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onExternalPageCommand);
      widget.controller?.addListener(_onExternalPageCommand);
    }
    if (oldWidget.pageCountNotifier != widget.pageCountNotifier) {
      oldWidget.pageCountNotifier?.removeListener(_onPageCountChanged);
      widget.pageCountNotifier?.addListener(_onPageCountChanged);
      if (widget.pageCountNotifier != null) {
        _localPageCount = widget.pageCountNotifier!.value;
      }
    }

    if (oldWidget.dragEnabled && !widget.dragEnabled && _isDragging) {
      _isDragging = false;
      _cancelFlip();
    }

    if (oldWidget.turnMode != widget.turnMode ||
        oldWidget.spread != widget.spread) {
      _curlFrameNotifier.value = CurlFrame.idle;
      _clearCurlImages();
      _disposeControllers();
      _initForMode();
      if (widget.turnMode == PageTurnMode.cover && widget.showPaperGrain) {
        unawaited(PaperGrainCache.ensureLoaded());
      }
      _scheduleIdleNextCurlWarmup();
    }

    // 跨章页流软切换：chapterId 变化不重挂载控制器，保持翻页手势连续。
    // 仅 turnMode 变化才重建。
    final pageOrThemeChanged =
        oldWidget.state.chapterId != widget.state.chapterId ||
        oldWidget.state.pageIndex != widget.state.pageIndex ||
        oldWidget.surfaceColor != widget.surfaceColor ||
        oldWidget.paperEdgeColor != widget.paperEdgeColor ||
        oldWidget.showPaperGrain != widget.showPaperGrain ||
        oldWidget.contentRevision != widget.contentRevision ||
        oldWidget.reverse != widget.reverse;

    if (pageOrThemeChanged) {
      _commitResetFallbackTimer?.cancel();
      _commitResetFallbackTimer = null;
      if (!_slideScrolling) {
        _transitionInFlight = false;
      }
      _animGeneration++;
      _awaitingCurlStart = false;
      _dragLockedDir = null;
      _isDragging = false;
      _isAnimating = false;
      _flipProgress = 0;
      _targetPageWidget = null;
      _boundaryRequestInFlight = false;
      _curlFrameNotifier.value = CurlFrame.idle;
      _clearCurlImages();
      _scheduleIdleNextCurlWarmup();
      if (_pendingTurnDirection != null && !_pendingTurnAttachRetry) {
        _scheduleTransitionRelease();
      }
    }

    if (widget.turnMode == PageTurnMode.slide &&
        oldWidget.state.pageIndex != widget.state.pageIndex) {
      _syncPageView();
    } else if (widget.turnMode == PageTurnMode.slide) {
      _reconcilePagePositionIfIdle();
    }

    if (widget.turnMode != PageTurnMode.slide) {
      _cacheCurrentPage();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onExternalPageCommand);
    widget.pageCountNotifier?.removeListener(_onPageCountChanged);
    _boundaryResetTimer?.cancel();
    _commitResetFallbackTimer?.cancel();
    _disposeControllers();
    _disposeCurlImages();
    _curlFrameNotifier.dispose();
    _flipProgressNotifier.dispose();
    super.dispose();
  }

  // ── 渲染 ──

  @override
  Widget build(BuildContext context) {
    return widget.turnMode == PageTurnMode.slide
        ? _buildSlideMode()
        : _buildCustomMode();
  }

  /// 一次翻页跨过的页数：跨页模式两张一起走。
  int get pageStep => widget.spread ? 2 : 1;

  /// 取指定页码的呈现单元：跨页模式把左页与右页并排成一个单元，兼容 RTL 日漫右先左后。
  /// 越界（章节页数为奇数）时留一张空白纸，不借用下一章的内容。
  Widget? pageAt(int index) {
    if (!widget.spread) {
      return widget.pageBuilder(index);
    }
    final first = widget.pageBuilder(index);
    if (first == null) {
      return null;
    }
    final second = widget.pageBuilder(index + 1);
    final left = widget.reverse ? (second ?? const SizedBox.expand()) : first;
    final right = widget.reverse ? first : second;
    final last = widget.state.pageCount <= 1 ? 1 : widget.state.pageCount - 1;
    final rawProgress = (index / last).clamp(0.0, 1.0);
    return ReaderPageSpread(
      left: left,
      right: right,
      surfaceColor: widget.surfaceColor,
      paperEdgeColor: widget.paperEdgeColor,
      showPaperGrain: widget.showPaperGrain,
      progress: widget.reverse ? (1.0 - rawProgress) : rawProgress,
    );
  }
}
