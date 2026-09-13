import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_interaction_gate.dart';

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

  @override
  State<ReaderPageView> createState() => _ReaderPageViewState();
}

class _ReaderPageViewState extends State<ReaderPageView>
    with TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onExternalPageCommand);
    _initForMode();
  }

  @override
  void didUpdateWidget(ReaderPageView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onExternalPageCommand);
      widget.controller?.addListener(_onExternalPageCommand);
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

    // 允许窗口滑动导致页数增减；缩小时钳制当前页。
    if (widget.state.pageCount != _localPageCount) {
      _localPageCount = widget.state.pageCount;
      if (_localPageCount > 0 &&
          widget.state.pageIndex >=
              _localPageCount + (widget.state.hasMore ? 1 : 0)) {
        // 交给父级 onPageChanged / _syncPageView 纠正。
      }
    }

    if (widget.turnMode == PageTurnMode.slide &&
        oldWidget.state.pageIndex != widget.state.pageIndex) {
      _syncPageView();
    }

    _cacheCurrentPage();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onExternalPageCommand);
    _boundaryResetTimer?.cancel();
    _disposeControllers();
    _flipProgressNotifier.dispose();
    super.dispose();
  }

  void _onExternalPageCommand() {
    // 底栏/快捷键是显式翻页意图，不能被上一次手势残留的滚动状态吞掉；
    // 重复触发仍由闸门内的动画与边界请求原因挡住。
    if (ReaderInteractionGate.blocksTapTurn(_blockReason)) return;
    final direction = widget.controller?.direction ?? 0;
    if (direction > 0) {
      _goNextPage(tapTurn: true);
    } else if (direction < 0) {
      _goPreviousPage(tapTurn: true);
    }
  }

  void _initForMode() {
    _localPageCount = widget.state.pageCount;
    _probingNext = false;
    _slideScrolling = false;
    _transitionInFlight = false;
    _boundaryRequestInFlight = false;
    _pendingSlideBoundaryDirection = 0;
    if (widget.turnMode == PageTurnMode.slide) {
      _pageController = PageController(initialPage: widget.state.pageIndex);
    } else {
      _animController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: _flipDurationMs),
      );
    }
    _cacheCurrentPage();
  }

  void _disposeControllers() {
    _pageController?.dispose();
    _pageController = null;
    _animController?.removeStatusListener(_onAutoFlipStatus);
    _animController?.dispose();
    _animController = null;
  }

  void _syncPageView() {
    final ctrl = _pageController;
    if (ctrl == null || !ctrl.hasClients) return;
    final target = widget.state.pageIndex;
    if ((ctrl.page ?? target).round() == target) {
      return;
    }
    // LayoutBuilder 重建期间 didUpdateWidget 可能发生在 layout 回调内；
    // 同步 jumpToPage 会立刻派发 ScrollNotification / onPageChanged，
    // 上游若在回调里 setState 会触发 build 期标记脏树。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      if ((controller.page ?? target).round() != target) {
        controller.jumpToPage(target);
      }
    });
  }

  void _cacheCurrentPage() {
    _currentPageWidget = widget.pageBuilder(widget.state.pageIndex);
  }

  Widget _buildPageOrEmpty(int index) {
    final page = widget.pageBuilder(index);
    if (page == null) {
      return SizedBox.expand(child: ColoredBox(color: widget.surfaceColor));
    }
    return SizedBox.expand(
      child: ColoredBox(color: widget.surfaceColor, child: page),
    );
  }

  // ══════════════════════════════════════════
  // 统一翻页命令
  // ══════════════════════════════════════════

  /// 当前输入闸门原因：加载 > 边界 > 动画 > 过渡 > 放行。
  ReaderInteractionBlockReason get _blockReason =>
      ReaderInteractionGate.resolve(
        isPaginating: widget.state.isPaginating,
        boundaryRequestInFlight: _boundaryRequestInFlight,
        pageAnimationActive: _isAnimating,
        pageTransitionInFlight: _transitionInFlight,
      );

  /// 统一：下一页。
  void _goNextPage({bool tapTurn = false}) {
    final reason = _blockReason;
    if (tapTurn
        ? ReaderInteractionGate.blocksTapTurn(reason)
        : ReaderInteractionGate.blocksInput(reason)) {
      return;
    }

    final nextIndex = widget.state.pageIndex + 1;
    final atBoundary = nextIndex >= _localPageCount && !widget.state.hasMore;

    if (atBoundary) {
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
      return;
    }

    if (widget.turnMode == PageTurnMode.slide) {
      final ctrl = _pageController;
      if (ctrl != null && ctrl.hasClients) {
        _transitionInFlight = true;
        unawaited(_animateSlideTo(ctrl, nextIndex));
      } else {
        // 控制器尚未挂载：下一帧重试，避免点击右侧/底栏无响应。
        _scheduleSlideRetry();
      }
    } else {
      _transitionInFlight = true;
      _isForward = true;
      _flipProgress = 0.01;
      _startAutoFlip();
    }
  }

  bool _slideRetryScheduled = false;

  void _scheduleSlideRetry() {
    if (_slideRetryScheduled) return;
    _slideRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _slideRetryScheduled = false;
      if (!mounted || ReaderInteractionGate.blocksTapTurn(_blockReason)) {
        return;
      }
      final ctrl = _pageController;
      if (ctrl != null && ctrl.hasClients) {
        final nextIndex = widget.state.pageIndex + 1;
        final atBoundary =
            nextIndex >= _localPageCount && !widget.state.hasMore;
        if (atBoundary) return;
        _transitionInFlight = true;
        unawaited(_animateSlideTo(ctrl, nextIndex));
      }
    });
  }

  /// 统一：上一页。
  void _goPreviousPage({bool tapTurn = false}) {
    final reason = _blockReason;
    if (tapTurn
        ? ReaderInteractionGate.blocksTapTurn(reason)
        : ReaderInteractionGate.blocksInput(reason)) {
      return;
    }

    final atBoundary = widget.state.pageIndex == 0;

    if (atBoundary) {
      _dispatchBoundaryRequest(
        widget.callbacks.onPreviousChapter,
        hasNeighbor: widget.state.hasPreviousChapter,
      );
      return;
    }

    if (widget.turnMode == PageTurnMode.slide) {
      final ctrl = _pageController;
      if (ctrl != null && ctrl.hasClients) {
        _transitionInFlight = true;
        unawaited(_animateSlideTo(ctrl, widget.state.pageIndex - 1));
      } else {
        _scheduleSlideRetry();
      }
    } else {
      _transitionInFlight = true;
      _isForward = false;
      _flipProgress = 0.01;
      _startAutoFlip();
    }
  }

  Future<void> _animateSlideTo(PageController controller, int pageIndex) async {
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpToPage(pageIndex);
      } else {
        await controller.animateToPage(
          pageIndex,
          duration: _slideTurnDuration,
          curve: _turnCurve,
        );
      }
    } finally {
      // 动画/jump 结束后必须解锁输入：父级 pageIndex 更新有帧延迟，
      // 不能只在目标页未到达时清理，否则 _transitionInFlight 会卡死翻页。
      if (mounted) {
        _scheduleTransitionRelease();
      }
    }
  }

  void _scheduleTransitionRelease() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _slideScrolling ||
          _boundaryRequestInFlight ||
          _probingNext) {
        return;
      }
      if (_transitionInFlight) {
        setState(() => _transitionInFlight = false);
      }
    });
  }

  Timer? _boundaryResetTimer;

  void _dispatchBoundaryRequest(
    VoidCallback callback, {
    required bool hasNeighbor,
  }) {
    _boundaryResetTimer?.cancel();
    _boundaryRequestInFlight = true;
    _transitionInFlight = true;
    callback();
    // 无论是否有邻章，都设置超时复位：切章失败/被吞时防止输入永久锁死。
    final delay =
        hasNeighbor
            ? const Duration(milliseconds: 1200)
            : const Duration(milliseconds: 250);
    _boundaryResetTimer = Timer(delay, () {
      if (!mounted) return;
      if (!_boundaryRequestInFlight && !_transitionInFlight) {
        return;
      }
      setState(() {
        _boundaryRequestInFlight = false;
        _transitionInFlight = false;
      });
    });
  }

  // ══════════════════════════════════════════
  // Slide 模式：PageView + 交互层
  // ══════════════════════════════════════════

  Widget _buildSlideMode() {
    final state = widget.state;
    final effectiveCount =
        _localPageCount > 0
            ? (state.hasMore ? _localPageCount + 1 : _localPageCount)
            : 1;

    return Stack(
      children: [
        // 底层：PageView 处理横向拖动翻页
        NotificationListener<ScrollNotification>(
          onNotification: _onSlideScrollNotification,
          child: PageView.builder(
            controller: _pageController,
            itemCount: effectiveCount,
            physics:
                ReaderInteractionGate.locksScroll(_blockReason)
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
            onPageChanged: _onSlidePageChanged,
            itemBuilder: (context, index) => _buildPageOrEmpty(index),
          ),
        ),
        // 顶层：透明交互层处理点击热区
        // 用 Listener 而非 GestureDetector，避免与 PageView 的拖动手势竞争
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
          ),
        ),
      ],
    );
  }

  bool _onSlideScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _slideScrolling = true;
      _transitionInFlight = true;
    } else if (notification is ScrollEndNotification) {
      _slideScrolling = false;
      final boundaryDirection = _pendingSlideBoundaryDirection;
      _pendingSlideBoundaryDirection = 0;
      if (!_boundaryRequestInFlight && !_probingNext) {
        _transitionInFlight = false;
      }
      if (boundaryDirection != 0) {
        scheduleMicrotask(() => _dispatchSlideBoundary(boundaryDirection));
      }
    }
    return false;
  }

  void _onSlidePageChanged(int index) {
    if (ReaderInteractionGate.locksScroll(_blockReason)) return;
    _transitionInFlight = true;

    if (index >= _localPageCount && widget.state.hasMore) {
      _handleProbePage(index);
      return;
    }

    widget.callbacks.onPageChanged(index);
    // 翻页可能由 jumpToPage 触发（无 ScrollEnd 复位机会），统一补一次解锁。
    _scheduleTransitionRelease();
  }

  // ── 交互层：点击热区 ──

  void _onPointerDown(PointerDownEvent event) {
    _primaryPointerDown = event.buttons == kPrimaryButton;
    if (!_primaryPointerDown) return;
    _pointerKind = event.kind;
    _pointerDownPosition = event.localPosition;
    _pointerMoved = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition == null) return;
    final delta = event.localPosition - _pointerDownPosition!;
    if (delta.distance > _tapMoveThreshold) {
      _pointerMoved = true;
    }
    if (widget.turnMode != PageTurnMode.slide &&
        _pointerKind == PointerDeviceKind.touch &&
        !widget.selectionActive &&
        delta.dx.abs() > _tapMoveThreshold &&
        delta.dx.abs() > delta.dy.abs()) {
      if (!_isDragging) {
        _onDragStart(DragStartDetails(localPosition: event.localPosition));
      }
      _onDragUpdate(
        DragUpdateDetails(
          delta: event.delta,
          primaryDelta: event.delta.dx,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_primaryPointerDown || _pointerDownPosition == null) return;
    _primaryPointerDown = false;
    final startPos = _pointerDownPosition!;
    _pointerDownPosition = null;
    _pointerKind = null;

    if (_isDragging) {
      _onDragEnd(DragEndDetails(velocity: Velocity.zero));
      return;
    }

    // 拖动过长则不算点击，交给 PageView 处理
    if (_pointerMoved) {
      final deltaX = event.localPosition.dx - startPos.dx;
      if (deltaX.abs() >= 48) {
        if (deltaX < 0 &&
            widget.state.isLastPage &&
            !widget.state.hasMore &&
            widget.state.hasNextChapter) {
          _pendingSlideBoundaryDirection = 1;
        } else if (deltaX > 0 &&
            widget.state.isFirstPage &&
            widget.state.hasPreviousChapter) {
          _pendingSlideBoundaryDirection = -1;
        }
        if (_pendingSlideBoundaryDirection != 0 && !_slideScrolling) {
          final direction = _pendingSlideBoundaryDirection;
          _pendingSlideBoundaryDirection = 0;
          scheduleMicrotask(() => _dispatchSlideBoundary(direction));
        }
      }
      return;
    }

    if (widget.selectionActive) return;

    final w = context.size?.width ?? 1;
    final x = startPos.dx;
    final leftBound = w * _leftZoneRatio;
    final rightBound = w * (1 - _rightZoneRatio);

    if (x < leftBound) {
      _goPreviousPage(tapTurn: true);
    } else if (x > rightBound) {
      _goNextPage(tapTurn: true);
    } else {
      widget.callbacks.onToggleControls();
    }
  }

  void _dispatchSlideBoundary(int direction) {
    if (!mounted || _boundaryRequestInFlight) {
      return;
    }
    if (direction > 0) {
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
    } else {
      _dispatchBoundaryRequest(
        widget.callbacks.onPreviousChapter,
        hasNeighbor: widget.state.hasPreviousChapter,
      );
    }
  }

  // ── 探测页 ──

  void _handleProbePage(int probeIndex) {
    if (_probingNext) return;
    _probingNext = true;

    final probeContent = widget.pageBuilder(probeIndex);
    // pageBuilder 返回 null 表示页面不存在
    final hasContent = probeContent != null;

    if (hasContent && mounted) {
      setState(() {
        _localPageCount = probeIndex + 1;
        _probingNext = false;
      });
      widget.callbacks.onPageChanged(probeIndex);
      // 探测页由 jumpToPage 到达时没有 ScrollEnd 复位输入锁，补一次解锁。
      _scheduleTransitionRelease();
    } else {
      _probingNext = false;
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
    }
  }

  // ══════════════════════════════════════════
  // Cover / Fade 模式：自定义手势 + 动画
  // ══════════════════════════════════════════

  Widget _buildCustomMode() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: _buildAnimationContent(),
    );
  }

  void _onDragStart(DragStartDetails details) {
    if (ReaderInteractionGate.blocksInput(_blockReason)) return;
    _isDragging = true;
    _totalDeltaX = 0;
    _isForward = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || ReaderInteractionGate.blocksInput(_blockReason)) {
      return;
    }
    _totalDeltaX += details.delta.dx;

    final w = context.size?.width ?? 1;

    if (_totalDeltaX < 0) {
      // 向前拖动：检查是否已在最后一页
      if (widget.state.isLastPage &&
          !widget.state.hasMore &&
          !widget.state.hasNextChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = true;
      _flipProgress = (-_totalDeltaX / w).clamp(0.0, 1.0);
    } else if (_totalDeltaX > 0) {
      // 向后拖动：检查是否已在第一页
      if (widget.state.isFirstPage && !widget.state.hasPreviousChapter) {
        _flipProgress = 0;
        return;
      }
      _isForward = false;
      _flipProgress = (_totalDeltaX / w).clamp(0.0, 1.0);
    }

    // 拖动超过阈值时预构建目标页（仅首次需要 setState 让 AnimatedBuilder 生效）
    if (_flipProgress > 0.05 && _targetPageWidget == null) {
      final targetIndex =
          _isForward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;
      if (targetIndex >= 0) {
        _targetPageWidget = widget.pageBuilder(targetIndex);
        if (mounted) setState(() {});
      }
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging || ReaderInteractionGate.blocksInput(_blockReason)) {
      return;
    }
    _isDragging = false;

    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldFlip = _flipProgress > _commitThreshold || velocity.abs() > 300;

    if (shouldFlip) {
      _startAutoFlip();
    } else {
      _cancelFlip();
    }
  }

  // ── 自定义动画 ──

  void _startAutoFlip() {
    _transitionInFlight = true;
    // 确保目标页已构建
    if (_targetPageWidget == null) {
      final targetIndex =
          _isForward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;
      if (targetIndex >= 0) {
        _targetPageWidget = widget.pageBuilder(targetIndex);
      }
    }

    _isAnimating = true;
    final ctrl = _animController!;
    ctrl.duration = Duration(
      milliseconds: (_flipDurationMs * (1 - _flipProgress)).round().clamp(
        100,
        _flipDurationMs,
      ),
    );

    ctrl.value = _flipProgress;
    // 动画启动时触发一次 build 进入 AnimatedBuilder 分支；
    // 后续每帧由 AnimatedBuilder 直接驱动，不再经过 setState。
    if (mounted) setState(() {});
    ctrl.animateTo(1, duration: ctrl.duration, curve: _turnCurve);
    ctrl.addStatusListener(_onAutoFlipStatus);
  }

  void _onAutoFlipStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animController?.removeStatusListener(_onAutoFlipStatus);
      _commitFlip();
    }
  }

  void _commitFlip() {
    final newPage =
        _isForward ? widget.state.pageIndex + 1 : widget.state.pageIndex - 1;

    if (newPage < 0) {
      _resetFlip();
      _dispatchBoundaryRequest(
        widget.callbacks.onPreviousChapter,
        hasNeighbor: widget.state.hasPreviousChapter,
      );
      return;
    }
    if (newPage >= _localPageCount && !widget.state.hasMore) {
      _resetFlip();
      _dispatchBoundaryRequest(
        widget.callbacks.onNextChapter,
        hasNeighbor: widget.state.hasNextChapter,
      );
      return;
    }

    _resetFlip();
    widget.callbacks.onPageChanged(newPage);
  }

  void _cancelFlip() {
    _isAnimating = true;
    _animController!.reverse(from: _flipProgress).then((_) {
      if (mounted) {
        setState(() {
          _flipProgress = 0;
          _isAnimating = false;
        });
      }
    });
  }

  void _resetFlip() {
    _flipProgress = 0;
    _isAnimating = false;
    _targetPageWidget = null;
    if (mounted) setState(() {});
  }

  // ── 渲染 ──

  @override
  Widget build(BuildContext context) {
    return widget.turnMode == PageTurnMode.slide
        ? _buildSlideMode()
        : _buildCustomMode();
  }

  Widget _buildAnimationContent() {
    final current =
        _currentPageWidget ?? widget.pageBuilder(widget.state.pageIndex);

    if (_flipProgress <= 0 && !_isAnimating) {
      return _constrainPage(current);
    }

    final target = _targetPageWidget;
    if (target == null) {
      return _constrainPage(current);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        return SizedBox.expand(
          child: AnimatedBuilder(
            animation: _animController!,
            builder: (context, _) {
              final t = _animController!.value;
              return switch (widget.turnMode) {
                PageTurnMode.cover => _buildCover(current, target, t, width),
                PageTurnMode.fade => _buildFade(current, target, t),
                PageTurnMode.slide => const SizedBox.shrink(),
              };
            },
          ),
        );
      },
    );
  }

  Widget _constrainPage(Widget? page) {
    return SizedBox.expand(
      child: ColoredBox(color: widget.surfaceColor, child: page),
    );
  }

  Widget _buildCover(Widget? current, Widget? target, double t, double width) {
    final targetOffset = _isForward ? (1 - t) * width : (t - 1) * width;

    return Stack(
      children: [
        _constrainPage(current),
        Transform.translate(
          offset: Offset(targetOffset, 0),
          child: _constrainPage(target),
        ),
      ],
    );
  }

  Widget _buildFade(Widget? current, Widget? target, double t) {
    return Stack(
      children: [
        Opacity(opacity: 1 - t, child: _constrainPage(current)),
        Opacity(opacity: t, child: _constrainPage(target)),
      ],
    );
  }
}
