import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_interaction_gate.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

part 'reader_page_view_turn.dart';
part 'reader_page_view_slide.dart';
part 'reader_page_view_custom.dart';
part 'reader_page_view_render.dart';

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
    this.controller,
    this.turnMode = PageTurnMode.slide,
    this.pageCountNotifier,
    super.key,
  });

  final PagedState state;

  /// 构建指定页码的 Widget。返回 null 表示页面不存在（章节结束）。
  final Widget? Function(int pageIndex) pageBuilder;
  final PageTurnCallbacks callbacks;
  final Color surfaceColor;
  final bool selectionActive;
  final ReaderPageTurnController? controller;
  final PageTurnMode turnMode;

  /// 预取就绪页数通知器：变化只同步本 State 的 [_ReaderPageViewState._localPageCount]，
  /// 不触发父级整页重建。
  final ValueNotifier<int>? pageCountNotifier;

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
  int _pendingSlideBoundaryDirection = 0;

  // ── 页面缓存 ──
  Widget? _currentPageWidget;
  Widget? _targetPageWidget;

  // ── 本地页数跟踪（slide 模式探测扩展） ──
  int _localPageCount = 0;
  bool _probingNext = false;

  // ── 交互层：点击 vs 拖动判断 ──
  Offset? _pointerDownPosition;
  bool _pointerMoved = false;
  bool _primaryPointerDown = false;
  PointerDeviceKind? _pointerKind;
  static const _tapMoveThreshold = 18.0;

  // ── 热区比例 ──
  static const _leftZoneRatio = 0.25;
  static const _rightZoneRatio = 0.25;

  // ── 配置 ──
  static const _commitThreshold = 0.35;
  static const _flipDurationMs = 260;
  static const _slideTurnDuration = Duration(milliseconds: 180);
  static const _turnCurve = Curves.easeOutQuart;

  // ── 待执行翻页意图（方案 §7-8）──
  // 控制器未挂载时保留意图并按帧重试，最多 4 帧；挂载后按最新
  // widget.state 重新解析目标，不缓存历史 index，超限显式放弃并留痕。
  int? _pendingTurnDirection;
  bool _pendingTurnAttachRetry = false;
  int _pendingTurnFrames = 0;
  static const int _maxPendingTurnFrames = 4;

  Timer? _boundaryResetTimer;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onExternalPageCommand);
    widget.pageCountNotifier?.addListener(_onPageCountChanged);
    _initForMode();
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

    if (oldWidget.turnMode != widget.turnMode) {
      _disposeControllers();
      _initForMode();
    }

    // 跨章页流软切换：chapterId 变化不重挂载控制器，保持翻页手势连续。
    // 仅 turnMode 变化才重建。

    if (oldWidget.state.chapterId != widget.state.chapterId ||
        oldWidget.state.pageIndex != widget.state.pageIndex) {
      if (!_slideScrolling) {
        _transitionInFlight = false;
      }
      _boundaryRequestInFlight = false;
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
    _disposeControllers();
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
}
