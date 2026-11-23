part of 'desktop_photos_page.dart';

mixin _JustifiedPhotosStateMixin<W extends StatefulWidget>
    on State<W>, TickerProviderStateMixin<W> {
  List<PhotoItem> get _photos;
  double get _targetHeight;
  Set<String> get _selection;
  void Function(PhotoItem photo, List<PhotoItem> photos) get _onActivate;
  ValueChanged<PhotoItem> get _onToggleSelect;
  void Function(PhotoItem photo, List<PhotoItem> photos, Offset globalPosition)?
  get _onSecondaryTap;
  void Function(PhotoItem photo, List<PhotoItem> photos)? get _onInspect =>
      null;
  bool get _selectionMode;
  String? get _orderContext;
  _PhotoOrderChanged? get _onOrderChanged;
  bool get _showCaption;
  bool get _showFavorite;
  bool get _showSelectionControls;
  VoidCallback? get _onRowHoverEnter => null;
  VoidCallback? get _onRowHoverExit => null;
  static const double _dragSlop = 8.0;
  static const double _edgeScrollZone = 80.0;

  List<String>? _dragOrder;
  List<String>? _settlingOrder;
  String? _lastSwapTarget;
  DateTime? _lastSwapAt;
  Offset? _lastSwapPointer;
  String? _draggedPhotoId;
  bool _settling = false;
  _PhotoDragPayload? _activeDragPayload;
  ({String contextKey, List<String> order, int movedCount})?
  _pendingCommitOrder;
  late final _PhotoFlipTracker _flipTracker;
  final Map<String, GlobalKey<State<StatefulWidget>>> _tileKeys = {};
  late final Ticker _dragTicker;
  late final AnimationController _settleController;
  Rect? _settleStartRect;
  Rect? _settleTargetRect;
  OverlayEntry? _ghostOverlay;
  final ValueNotifier<_GhostPose?> _ghostPose = ValueNotifier<_GhostPose?>(
    null,
  );

  Offset _dragPointer = Offset.zero;
  Offset _dragPointerSmooth = Offset.zero;
  double _grabCenterK = 0.0;

  Timer? _pressTimer;
  Timer? _holdTimer;
  Timer? _landedTimer;
  Timer? _clickGuardTimer;
  bool _trailingClickGuard = false;
  bool _globalPointerAttached = false;

  int? _pressPointer;
  Offset? _pressOrigin;

  Set<String> _pressingPhotoIds = <String>{};
  Set<String> _landedPhotoIds = <String>{};
  bool get _justDragged => _trailingClickGuard;
  bool get _isDragging => _draggedPhotoId != null && !_settling;

  double _currentScrollOffset() {
    if (!mounted) return 0.0;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.position.hasPixels) return 0.0;
    return scrollable.position.pixels;
  }

  @override
  void initState() {
    super.initState();
    _flipTracker = _PhotoFlipTracker(scrollOffsetOf: _currentScrollOffset);
    _dragTicker = createTicker(_onDragTick);
    _settleController = AnimationController(
      vsync: this,
      duration: DesktopMotion.photoReorderSettle,
    )..addListener(_onSettleTick);
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  void _attachGlobalPointer() {
    if (_globalPointerAttached) return;
    _globalPointerAttached = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  void _detachGlobalPointer() {
    if (!_globalPointerAttached) return;
    _globalPointerAttached = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (!_isDragging || _pressPointer != event.pointer) return;
    if (event is PointerMoveEvent) {
      _dragPointer = event.position;
      _checkSwap();
    } else if (event is PointerUpEvent) {
      _finishDrag(accepted: true);
    } else if (event is PointerCancelEvent) {
      _finishDrag(accepted: false);
    }
  }

  void _startTrailingClickGuard() {
    _clickGuardTimer?.cancel();
    _trailingClickGuard = true;
    _clickGuardTimer = Timer(DesktopMotion.photoReorderClickGuard, () {
      _trailingClickGuard = false;
    });
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        (_draggedPhotoId == null && _pressPointer == null)) {
      return false;
    }
    if (_isDragging) {
      _finishDrag(accepted: false, canceledByEsc: true);
    } else {
      _abortPress();
    }
    return true;
  }

  void _abortPress() {
    _detachGlobalPointer();
    _pressTimer?.cancel();
    _holdTimer?.cancel();
    _pressPointer = null;
    _pressOrigin = null;
    if (_pressingPhotoIds.isNotEmpty && mounted) {
      setState(() => _pressingPhotoIds = <String>{});
    }
  }

  void _cleanupImmediate() {
    _detachGlobalPointer();
    _pressTimer?.cancel();
    _holdTimer?.cancel();
    _landedTimer?.cancel();
    _clickGuardTimer?.cancel();
    _trailingClickGuard = false;
    if (_dragTicker.isActive) _dragTicker.stop();
    if (_settleController.isAnimating) _settleController.stop();
    _removeGhostOverlay();
    _flipTracker.clear();
    _pressPointer = null;
    _pressOrigin = null;
    _settleStartRect = null;
    _settleTargetRect = null;
    _pendingCommitOrder = null;
    if (mounted) {
      setState(() {
        _dragOrder = null;
        _settlingOrder = null;
        _draggedPhotoId = null;
        _settling = false;
        _activeDragPayload = null;
        _lastSwapTarget = null;
        _lastSwapAt = null;
        _lastSwapPointer = null;
        _pressingPhotoIds = <String>{};
        _landedPhotoIds = <String>{};
      });
    }
  }

  List<String> _expandedOrder(
    List<String> collapsed,
    _PhotoDragPayload payload,
  ) => [
    for (final id in collapsed)
      if (id == payload.draggedId) ...payload.movingIds else id,
  ];

  void _onTilePointerDown(
    _PhotoDragPayload payload,
    PointerDownEvent event,
    Offset localPosition,
  ) {
    if (_draggedPhotoId != null || _settling) return;
    if ((event.buttons & kPrimaryButton) == 0) return;

    // 勾选圈是独立点击目标，按住勾选圈不触发长按拖动。
    if (_showSelectionControls &&
        localPosition.dx >= 10 &&
        localPosition.dx <= 36 &&
        localPosition.dy >= 10 &&
        localPosition.dy <= 36) {
      return;
    }
    if (_onInspect != null &&
        payload.feedbackWidth > 0 &&
        localPosition.dx >= payload.feedbackWidth - 36 &&
        localPosition.dy >= 10 &&
        localPosition.dy <= 36) {
      return;
    }
    if (payload.orderIds.length < 2) return;

    _pressTimer?.cancel();
    _holdTimer?.cancel();
    _pressPointer = event.pointer;
    _pressOrigin = event.position;
    _dragPointer = event.position;
    final pointerId = event.pointer;
    _pressTimer = Timer(DesktopMotion.photoReorderPressPreview, () {
      if (!mounted || _pressPointer != pointerId || _draggedPhotoId != null) {
        return;
      }
      setState(() => _pressingPhotoIds = Set<String>.of(payload.movingIds));
    });
    _holdTimer = Timer(DesktopMotion.photoReorderHold, () {
      if (!mounted || _pressPointer != pointerId || _draggedPhotoId != null) {
        return;
      }
      _beginDrag(payload);
    });
  }

  void _onTilePointerMove(PointerMoveEvent event) {
    if (_globalPointerAttached) return;
    if (_pressPointer != event.pointer) return;
    _dragPointer = event.position;
    if (!_isDragging) {
      final origin = _pressOrigin;
      if (origin != null && (event.position - origin).distance > _dragSlop) {
        _abortPress();
      }
      return;
    }
    _checkSwap();
  }

  void _onTilePointerUp(PointerUpEvent event) {
    if (_globalPointerAttached) return;
    if (_pressPointer != event.pointer) return;
    if (_isDragging) {
      _finishDrag(accepted: true);
    } else {
      _abortPress();
    }
  }

  void _onTilePointerCancel(PointerCancelEvent event) {
    if (_globalPointerAttached) return;
    if (_pressPointer != event.pointer) return;
    if (_isDragging) {
      _finishDrag(accepted: false);
    } else {
      _abortPress();
    }
  }

  void _beginDrag(_PhotoDragPayload payload) {
    _pressTimer?.cancel();
    _holdTimer?.cancel();
    final startRects = <String, Rect>{};
    for (final id in payload.movingIds) {
      final rect = _rectFor(id);
      if (rect != null) startRects[id] = rect;
    }
    final originRect =
        startRects[payload.draggedId] ?? _rectFor(payload.draggedId);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || overlayBox is! RenderBox || !overlayBox.hasSize) {
      _abortPress();
      return;
    }

    final fanOffsets = _computeFanOffsets(
      origin: originRect,
      startRects: startRects,
      movingPhotos: payload.movingPhotos,
      feedbackWidth: payload.feedbackWidth,
      feedbackHeight: payload.feedbackHeight,
    );
    final livePayload = _PhotoDragPayload(
      contextKey: payload.contextKey,
      orderIds: payload.orderIds,
      baseOrderIds: payload.baseOrderIds,
      draggedId: payload.draggedId,
      movingIds: payload.movingIds,
      movingPhotos: payload.movingPhotos,
      feedbackWidth: payload.feedbackWidth,
      feedbackHeight: payload.feedbackHeight,
      fanOffsets: fanOffsets,
      grabOffset: payload.grabOffset,
    );

    // 起拖折叠多选前先拍 FLIP 快照，让兄弟卡片平滑补位。
    _flipTracker.skipPhotoId = livePayload.draggedId;
    _flipTracker.snapshot(_tileKeys);

    _dragPointerSmooth = _dragPointer;
    _grabCenterK = 0.0;
    _activeDragPayload = livePayload;
    _pendingCommitOrder = null;
    final localPointer = overlayBox.globalToLocal(_dragPointerSmooth);
    final initialPose = _GhostPose(
      left: localPointer.dx - livePayload.grabOffset.dx,
      top: localPointer.dy - livePayload.grabOffset.dy,
      width: livePayload.feedbackWidth,
      height: livePayload.feedbackHeight,
    );
    _insertGhostOverlay(overlay, livePayload, initialPose);
    _attachGlobalPointer();

    setState(() {
      _pressingPhotoIds = <String>{};
      _draggedPhotoId = livePayload.draggedId;
      _settling = false;
      _settlingOrder = null;
      _dragOrder = livePayload.baseOrderIds;
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _lastSwapPointer = null;
    });

    if (!_dragTicker.isActive) {
      _dragTicker.start();
    }
  }

  void _insertGhostOverlay(
    OverlayState overlay,
    _PhotoDragPayload payload,
    _GhostPose initialPose,
  ) {
    _removeGhostOverlay();
    _ghostPose.value = initialPose;
    final entry = OverlayEntry(
      builder: (overlayContext) {
        // Positioned 必须直贴 Overlay 的 Stack：语义隔离要放在 Positioned 内部，
        // 否则 ExcludeSemantics 的代理 RenderObject 会截走 StackParentData。
        return ValueListenableBuilder<_GhostPose?>(
          valueListenable: _ghostPose,
          builder: (context, pose, _) {
            if (pose == null) return const SizedBox.shrink();
            return Positioned(
              left: pose.left,
              top: pose.top,
              width: pose.width,
              height: pose.height,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: _PhotoDragFeedback(
                    photos: payload.movingPhotos,
                    fanOffsets: payload.fanOffsets,
                    width: pose.width,
                    height: pose.height,
                    dropping: pose.dropping,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _ghostOverlay = entry;
    overlay.insert(entry);
  }

  void _removeGhostOverlay() {
    final entry = _ghostOverlay;
    _ghostOverlay = null;
    _ghostPose.value = null;
    entry?.remove();
    entry?.dispose();
  }

  void _onDragTick(Duration _) {
    final payload = _activeDragPayload;
    if (!mounted || !_isDragging || payload == null) return;

    // 60fps 阻尼跟随（0.22 收敛系数），多选堆抓点平滑缓动至指针中心。
    final delta = _dragPointer - _dragPointerSmooth;
    if (delta.distanceSquared < 0.01) {
      _dragPointerSmooth = _dragPointer;
    } else {
      _dragPointerSmooth += delta * DesktopMotion.photoReorderPointerSmoothing;
    }
    final isMulti = payload.movingPhotos.length > 1;
    if (isMulti && _grabCenterK < 1.0) {
      _grabCenterK = math.min(1.0, _grabCenterK + 0.06);
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlayBox is RenderBox && overlayBox.hasSize) {
      final localPointer = overlayBox.globalToLocal(_dragPointerSmooth);
      final fx =
          payload.grabOffset.dx +
          (payload.feedbackWidth / 2 - payload.grabOffset.dx) * _grabCenterK;
      final fy =
          payload.grabOffset.dy +
          (payload.feedbackHeight / 2 - payload.grabOffset.dy) * _grabCenterK;
      _ghostPose.value = _GhostPose(
        left: localPointer.dx - fx,
        top: localPointer.dy - fy,
        width: payload.feedbackWidth,
        height: payload.feedbackHeight,
      );
    }

    // 持续边缘自动滚屏（80px 热区，1..18px/帧），滚屏后立即复检换位。
    if (_autoScroll(_dragPointer)) {
      _checkSwap();
    }
  }

  bool _autoScroll(Offset pointer) {
    final scrollable = Scrollable.maybeOf(context);
    final renderObject = scrollable?.context.findRenderObject();
    if (scrollable == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return false;
    }
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final bottom = top + renderObject.size.height;
    final distanceFromTop = top + _edgeScrollZone - pointer.dy;
    final distanceFromBottom = pointer.dy - (bottom - _edgeScrollZone);
    final delta =
        distanceFromTop > 0
            ? -((distanceFromTop / 5).ceil().clamp(1, 18))
            : distanceFromBottom > 0
            ? (distanceFromBottom / 5).ceil().clamp(1, 18)
            : 0;
    if (delta == 0) return false;
    final position = scrollable.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return false;
    position.jumpTo(next);
    return true;
  }

  void _checkSwap() {
    final payload = _activeDragPayload;
    if (payload == null || !_isDragging) return;
    final pointer = _dragPointer;
    final now = DateTime.now();
    final lastSwapAt = _lastSwapAt;
    if (lastSwapAt != null &&
        now.difference(lastSwapAt) < DesktopMotion.photoReorderSwapCooldown) {
      return;
    }

    final currentOrder = _dragOrder ?? payload.baseOrderIds;
    String? targetId;
    Rect? targetRect;
    for (final id in currentOrder) {
      if (id == payload.draggedId) continue;
      final rect = _rectFor(id);
      if (rect != null && rect.contains(pointer)) {
        targetId = id;
        targetRect = rect;
        break;
      }
    }
    if (targetId == null || targetRect == null) return;

    // 22% 内缩命中区，避免指针擦边触发换位。
    final marginX = targetRect.width * 0.22;
    final marginY = targetRect.height * 0.22;
    if (pointer.dx < targetRect.left + marginX ||
        pointer.dx > targetRect.right - marginX ||
        pointer.dy < targetRect.top + marginY ||
        pointer.dy > targetRect.bottom - marginY) {
      return;
    }

    // 刚交换的目标需移出 max(36, width*0.35) 才允许回换。
    final lastSwapPointer = _lastSwapPointer;
    if (_lastSwapTarget == targetId &&
        lastSwapPointer != null &&
        (pointer - lastSwapPointer).distance <
            math.max(36.0, targetRect.width * 0.35)) {
      return;
    }

    final nextOrder = movePhotoDisplayOrder(
      order: currentOrder,
      draggedId: payload.draggedId,
      targetId: targetId,
      selectedIds: const <String>{},
    );
    if (_sameOrder(currentOrder, nextOrder)) return;

    // 同步 FLIP 快照：在 setState 之前记录所有卡片的滚动补偿坐标。
    _flipTracker.skipPhotoId = payload.draggedId;
    _flipTracker.snapshot(_tileKeys);

    setState(() {
      _dragOrder = nextOrder;
      _lastSwapTarget = targetId;
      _lastSwapAt = now;
      _lastSwapPointer = pointer;
    });
  }

  void _finishDrag({required bool accepted, bool canceledByEsc = false}) {
    final payload = _activeDragPayload;
    _detachGlobalPointer();
    if (!mounted || payload == null || _settling) {
      _cleanupImmediate();
      return;
    }

    if (_dragTicker.isActive) _dragTicker.stop();
    _pressTimer?.cancel();
    _holdTimer?.cancel();
    _pressPointer = null;
    _pressOrigin = null;

    // Esc 取消也要屏蔽尾随 click：否则真实松手会被当成一次点击打开照片。
    _startTrailingClickGuard();
    final collapsedOrder = _dragOrder ?? payload.baseOrderIds;
    final expandedOrder =
        accepted ? _expandedOrder(collapsedOrder, payload) : payload.orderIds;
    final orderChanged =
        accepted && !_sameOrder(payload.orderIds, expandedOrder);

    // 原地松手与 Esc 取消：先让实体图 0ms 恢复 1.0 不透明，再于下一帧销毁幽灵 Overlay。
    if (!orderChanged) {
      final staleOverlay = _ghostOverlay;
      _ghostOverlay = null;
      _flipTracker.clear();
      _pendingCommitOrder = null;
      if (mounted) {
        setState(() {
          _settling = false;
          _settlingOrder = null;
          _dragOrder = null;
          _draggedPhotoId = null;
          _activeDragPayload = null;
          _pressingPhotoIds = <String>{};
          _landedPhotoIds = <String>{};
          _lastSwapTarget = null;
          _lastSwapAt = null;
          _lastSwapPointer = null;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ghostPose.value = null;
        }
        staleOverlay?.remove();
        staleOverlay?.dispose();
      });
      return;
    }

    // 阶段 1：保持 `_draggedPhotoId` 占位态不清空（零双影），延后提交顺序直至落位完成。
    _flipTracker.skipPhotoId = payload.draggedId;
    _flipTracker.snapshot(_tileKeys);
    _pendingCommitOrder = (
      contextKey: payload.contextKey,
      order: expandedOrder,
      movedCount: payload.movingPhotos.length,
    );

    setState(() {
      _settling = true;
      _dragOrder = null;
      _settlingOrder = expandedOrder;
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _lastSwapPointer = null;
    });

    // 阶段 2：单次 postFrameCallback 直接测量真实目标槽位并飞入，避免双层嵌套造成 ~1s 停顿。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_settling) return;
      _animateGhostSettle(payload: payload, accepted: accepted);
    });
  }

  void _animateGhostSettle({
    required _PhotoDragPayload payload,
    required bool accepted,
    bool retried = false,
  }) {
    final currentPose = _ghostPose.value;
    final targetGlobal = _rectFor(payload.draggedId);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();

    if (targetGlobal == null && !retried) {
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_settling) return;
        _animateGhostSettle(
          payload: payload,
          accepted: accepted,
          retried: true,
        );
      });
      return;
    }

    if (currentPose == null ||
        targetGlobal == null ||
        overlayBox is! RenderBox ||
        !overlayBox.hasSize) {
      _completeSettle(payload: payload, accepted: accepted);
      return;
    }

    final targetLocalTopLeft = overlayBox.globalToLocal(targetGlobal.topLeft);
    _settleStartRect = currentPose.rect;
    _settleTargetRect = targetLocalTopLeft & targetGlobal.size;
    _ghostPose.value = currentPose.copyWith(dropping: true);
    final centerDistance =
        (_settleStartRect!.center - _settleTargetRect!.center).distance;
    final rawDuration =
        centerDistance < 24.0
            ? Duration(
              milliseconds: (220 + (centerDistance / 24.0) * 100).round().clamp(
                220,
                320,
              ),
            )
            : DesktopMotion.photoReorderSettle;
    final duration = DesktopMotion.of(context, rawDuration);
    if (duration == Duration.zero) {
      _completeSettle(payload: payload, accepted: accepted);
      return;
    }
    _settleController.duration = duration;
    _settleController.forward(from: 0.0).whenComplete(() {
      if (!mounted || !_settling) return;
      _completeSettle(payload: payload, accepted: accepted);
    });
  }

  void _onSettleTick() {
    final start = _settleStartRect;
    final target = _settleTargetRect;
    if (start == null || target == null || _ghostOverlay == null) return;
    final t = DesktopMotion.photoReorderSettleCurve.transform(
      _settleController.value.clamp(0.0, 1.0),
    );
    final rect = Rect.lerp(start, target, t)!;
    _ghostPose.value = _GhostPose(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      dropping: true,
    );
  }

  void _completeSettle({
    required _PhotoDragPayload payload,
    required bool accepted,
  }) {
    final staleOverlay = _ghostOverlay;
    _ghostOverlay = null;
    _flipTracker.clear();
    _settleStartRect = null;
    _settleTargetRect = null;
    final pendingCommit = _pendingCommitOrder;
    _pendingCommitOrder = null;
    final companions =
        accepted && payload.movingIds.length > 1
            ? payload.movingIds.where((id) => id != payload.draggedId).toSet()
            : <String>{};

    if (companions.isNotEmpty) {
      _landedTimer?.cancel();
      _landedTimer = Timer(DesktopMotion.photoReorderLanded, () {
        if (mounted) setState(() => _landedPhotoIds = <String>{});
      });
    }

    // 关键修复：先清除 _draggedPhotoId 让实体图以 0ms 瞬时恢复 opacity: 1.0 渲染，
    // 在本帧实体图上屏后的 postFrameCallback 中再销毁幽灵 Overlay，并提交新顺序。
    setState(() {
      _settling = false;
      _draggedPhotoId = null;
      _activeDragPayload = null;
      _landedPhotoIds = companions;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ghostPose.value = null;
      }
      staleOverlay?.remove();
      staleOverlay?.dispose();
      if (mounted && _settlingOrder != null) {
        setState(() => _settlingOrder = null);
      }
    });
    final onOrderChanged = _onOrderChanged;
    if (pendingCommit != null && onOrderChanged != null) {
      unawaited(
        onOrderChanged(
          pendingCommit.contextKey,
          pendingCommit.order,
          pendingCommit.movedCount,
        ),
      );
    }
  }

  Rect? _rectFor(String id) {
    final tileContext = _tileKeys[id]?.currentContext;
    if (tileContext == null || !tileContext.mounted) return null;
    RenderObject? object;
    try {
      object = tileContext.findRenderObject();
    } on FlutterError {
      return null;
    }
    if (object is! RenderBox || !object.hasSize) return null;
    return object.localToGlobal(Offset.zero) & object.size;
  }

  List<_PhotoFlyOffset> _computeFanOffsets({
    required Rect? origin,
    required Map<String, Rect> startRects,
    required List<PhotoItem> movingPhotos,
    required double feedbackWidth,
    required double feedbackHeight,
  }) {
    return movingPhotos
        .map((photo) {
          final source = startRects[photo.id];
          if (origin == null ||
              source == null ||
              feedbackWidth <= 0 ||
              feedbackHeight <= 0) {
            return const _PhotoFlyOffset();
          }
          final originCenterX = origin.left + feedbackWidth / 2;
          final originCenterY = origin.top + feedbackHeight / 2;
          return _PhotoFlyOffset(
            dx: source.center.dx - originCenterX,
            dy: source.center.dy - originCenterY,
            sx: source.width / feedbackWidth,
            sy: source.height / feedbackHeight,
          );
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    _detachGlobalPointer();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _pressTimer?.cancel();
    _holdTimer?.cancel();
    _landedTimer?.cancel();
    _clickGuardTimer?.cancel();
    _removeGhostOverlay();
    _dragTicker.dispose();
    _settleController
      ..removeListener(_onSettleTick)
      ..dispose();
    _ghostPose.dispose();
    super.dispose();
  }
}
