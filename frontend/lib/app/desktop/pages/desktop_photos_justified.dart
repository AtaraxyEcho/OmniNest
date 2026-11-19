part of 'desktop_photos_page.dart';

class _JustifiedPhotos extends StatefulWidget {
  const _JustifiedPhotos({
    required this.photos,
    required this.targetHeight,
    required this.selection,
    required this.onActivate,
    required this.onToggleSelect,
    this.orderContext,
    this.onOrderChanged,
    this.showCaption = true,
    this.showFavorite = true,
    this.showSelectionControls = true,
  });

  final List<PhotoItem> photos;
  final double targetHeight;
  final Set<String> selection;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final String? orderContext;
  final _PhotoOrderChanged? onOrderChanged;
  final bool showCaption;
  final bool showFavorite;
  final bool showSelectionControls;

  @override
  State<_JustifiedPhotos> createState() => _JustifiedPhotosState();
}

class _JustifiedPhotosState extends State<_JustifiedPhotos>
    with SingleTickerProviderStateMixin {
  List<String>? _dragOrder;
  String? _lastSwapTarget;
  DateTime? _lastSwapAt;
  Offset? _lastSwapPointer;
  bool _dragCanceled = false;

  /// Esc 取消时通知仍在 Flutter Overlay 里的拖拽反馈立即收起。
  ///
  /// `LongPressDraggable` 的 feedback 在起拖时就挂进 Overlay，父级重建或换 key
  /// 不会同步替换那份 widget；不显式通知会出现「按了取消，预览还悬在屏幕上」。
  final ValueNotifier<bool> _dragFeedbackDismissed = ValueNotifier<bool>(false);
  final ValueNotifier<Offset> _dragFeedbackOffset = ValueNotifier<Offset>(
    Offset.zero,
  );
  late final Ticker _dragSmoothingTicker;
  Offset _dragPointer = Offset.zero;
  Offset _dragPointerSmooth = Offset.zero;
  bool _dragPointerReady = false;
  String? _draggedPhotoId;
  _PhotoDragPayload? _activeDragPayload;
  Timer? _clickGuardTimer;
  bool _trailingClickGuard = false;
  int _dragGeneration = 0;
  int _flipGeneration = 0;
  final Map<String, GlobalKey<State<StatefulWidget>>> _tileKeys = {};
  Map<String, Offset> _flipOffsets = const {};
  Rect? _dragOriginRect;
  Map<String, Rect> _dragStartRects = <String, Rect>{};
  OverlayEntry? _settleOverlay;
  Timer? _pressTimer;
  Timer? _landedTimer;
  int? _pressPointer;
  Offset? _pressOrigin;
  String? _pressPhotoId;
  String? _blockedReorderPhotoId;
  Set<String> _pressingPhotoIds = <String>{};
  Set<String> _landedPhotoIds = <String>{};

  bool get _justDragged => _trailingClickGuard;

  void _startTrailingClickGuard() {
    _clickGuardTimer?.cancel();
    _trailingClickGuard = true;
    _clickGuardTimer = Timer(DesktopMotion.photoReorderClickGuard, () {
      _trailingClickGuard = false;
    });
  }

  Set<String> _movingIds(_PhotoDragPayload payload) =>
      Set<String>.of(payload.movingIds);

  @override
  void initState() {
    super.initState();
    _dragSmoothingTicker = createTicker((_) {
      if (!_dragPointerReady) return;
      final delta = _dragPointer - _dragPointerSmooth;
      if (delta.distanceSquared < 0.01) {
        _dragPointerSmooth = _dragPointer;
      } else {
        _dragPointerSmooth +=
            delta * DesktopMotion.photoReorderPointerSmoothing;
      }
      _dragFeedbackOffset.value = _dragPointerSmooth - _dragPointer;
    });
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  void _startDragSmoothing() {
    _dragPointerReady = false;
    _dragFeedbackOffset.value = Offset.zero;
    if (!_dragSmoothingTicker.isActive) {
      _dragSmoothingTicker.start();
    }
  }

  void _updateDragPointer(Offset position) {
    if (!_dragPointerReady) {
      _dragPointer = position;
      _dragPointerSmooth = position;
      _dragPointerReady = true;
      _dragFeedbackOffset.value = Offset.zero;
      return;
    }
    _dragPointer = position;
  }

  void _stopDragSmoothing() {
    if (_dragSmoothingTicker.isActive) {
      _dragSmoothingTicker.stop();
    }
    _dragPointerReady = false;
    _dragFeedbackOffset.value = Offset.zero;
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        (_draggedPhotoId == null && _pressPointer == null)) {
      return false;
    }
    _cancelReorder();
    return true;
  }

  void _cancelReorder() {
    if (_draggedPhotoId == null && _pressPointer == null) return;
    _pressTimer?.cancel();
    _landedTimer?.cancel();
    _flipGeneration++;
    _dragGeneration++;
    // Esc 是「显式取消」，不是一次拖放结束；不能启动点击抑制窗口，
    // 否则用户取消后立刻点另一张会被 `_justDragged` 静默吞掉。
    _clickGuardTimer?.cancel();
    _trailingClickGuard = false;
    _dragCanceled = true;
    _dragFeedbackDismissed.value = true;
    _stopDragSmoothing();
    _removeSettleOverlay();
    setState(() {
      _dragOrder = null;
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _lastSwapPointer = null;
      _draggedPhotoId = null;
      _activeDragPayload = null;
      _pressPointer = null;
      _pressOrigin = null;
      _pressPhotoId = null;
      _blockedReorderPhotoId = null;
      _pressingPhotoIds = <String>{};
      _landedPhotoIds = <String>{};
      _flipOffsets = const {};
    });
    _dragOriginRect = null;
    _dragStartRects = <String, Rect>{};
  }

  List<String> _collapsedOrder(_PhotoDragPayload payload) => payload.orderIds
      .where((id) => id == payload.draggedId || !payload.movingIds.contains(id))
      .toList(growable: false);

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
    if ((event.buttons & kPrimaryButton) == 0) return;
    _pressPointer = event.pointer;
    _pressOrigin = event.position;
    _pressPhotoId = payload.draggedId;

    // 样例的勾选按钮是独立点击目标，按住勾选圈不应启动照片拖动。
    if (widget.showSelectionControls &&
        localPosition.dx >= 10 &&
        localPosition.dx <= 36 &&
        localPosition.dy >= 10 &&
        localPosition.dy <= 36) {
      setState(() => _blockedReorderPhotoId = payload.draggedId);
      return;
    }
    if (payload.orderIds.length < 2) return;

    _pressTimer?.cancel();
    _pressTimer = Timer(DesktopMotion.photoReorderPressPreview, () {
      if (!mounted || _pressPointer != event.pointer) return;
      setState(() => _pressingPhotoIds = _movingIds(payload));
    });
  }

  void _onTilePointerMove(PointerMoveEvent event) {
    if (_pressPointer != event.pointer || _pressOrigin == null) return;
    if ((event.position - _pressOrigin!).distance <= 8) return;
    _pressTimer?.cancel();
    setState(() {
      _pressingPhotoIds = <String>{};
      _blockedReorderPhotoId = _pressPhotoId;
    });
  }

  void _onTilePointerEnd(PointerEvent event, {bool canceled = false}) {
    if (_pressPointer != event.pointer) return;
    if (canceled && _draggedPhotoId != null) {
      _cancelReorder();
      return;
    }
    _pressTimer?.cancel();
    if (_pressingPhotoIds.isNotEmpty || _blockedReorderPhotoId != null) {
      setState(() {
        _pressingPhotoIds = <String>{};
        _blockedReorderPhotoId = null;
      });
    }
    _pressPointer = null;
    _pressOrigin = null;
    _pressPhotoId = null;
  }

  void _startDrag(_PhotoDragPayload payload, int generation) {
    if (generation != _dragGeneration) return;
    _dragStartRects = <String, Rect>{};
    for (final id in payload.movingIds) {
      final rect = _rectFor(id);
      if (rect != null) _dragStartRects[id] = rect;
    }
    _dragOriginRect =
        _dragStartRects[payload.draggedId] ?? _rectFor(payload.draggedId);
    _pressTimer?.cancel();
    _draggedPhotoId = payload.draggedId;
    _activeDragPayload = payload;
    _dragCanceled = false;
    _dragFeedbackDismissed.value = false;
    _startDragSmoothing();
    setState(() {
      _pressingPhotoIds = <String>{};
      _blockedReorderPhotoId = null;
      _dragOrder = _collapsedOrder(payload);
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _lastSwapPointer = null;
    });
  }

  void _trackTarget(
    _PhotoDragPayload payload,
    String targetId,
    Offset pointer,
  ) {
    if (targetId == payload.draggedId ||
        payload.contextKey != widget.orderContext) {
      return;
    }
    final targetRect = _rectFor(targetId);
    if (targetRect == null ||
        pointer.dx < targetRect.left + targetRect.width * 0.22 ||
        pointer.dx > targetRect.right - targetRect.width * 0.22 ||
        pointer.dy < targetRect.top + targetRect.height * 0.22 ||
        pointer.dy > targetRect.bottom - targetRect.height * 0.22) {
      return;
    }
    final now = DateTime.now();
    final lastSwapAt = _lastSwapAt;
    if (lastSwapAt != null &&
        now.difference(lastSwapAt) < DesktopMotion.photoReorderSwapCooldown) {
      return;
    }
    final lastSwapPointer = _lastSwapPointer;
    if (_lastSwapTarget == targetId &&
        lastSwapPointer != null &&
        (pointer - lastSwapPointer).distance <
            (targetRect.width * 0.35 > 36 ? targetRect.width * 0.35 : 36)) {
      return;
    }
    final currentOrder = _dragOrder ?? payload.orderIds;
    final oldPositions = _positionsFor(currentOrder);
    final nextOrder = movePhotoDisplayOrder(
      order: currentOrder,
      draggedId: payload.draggedId,
      targetId: targetId,
      selectedIds: const <String>{},
    );
    if (_sameOrder(currentOrder, nextOrder)) return;
    setState(() {
      _dragOrder = nextOrder;
      _lastSwapTarget = targetId;
      _lastSwapAt = now;
      _lastSwapPointer = pointer;
    });
    final generation = ++_flipGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _flipGeneration) return;
      final offsets = <String, Offset>{};
      for (final entry in oldPositions.entries) {
        final newPosition = _positionFor(entry.key);
        if (newPosition == null) continue;
        final offset = entry.value - newPosition;
        if (offset.distance > 1) offsets[entry.key] = offset;
      }
      setState(() => _flipOffsets = offsets);
    });
  }

  String? _photoAt(Offset pointer, _PhotoDragPayload payload) {
    for (final id in _dragOrder ?? payload.orderIds) {
      if (id == payload.draggedId) continue;
      final rect = _rectFor(id);
      if (rect != null && rect.contains(pointer)) return id;
    }
    return null;
  }

  void _autoScroll(Offset pointer) {
    final scrollable = Scrollable.maybeOf(context);
    final renderObject = scrollable?.context.findRenderObject();
    if (scrollable == null || renderObject is! RenderBox) return;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final bottom = top + renderObject.size.height;
    final distanceFromTop = top + 80 - pointer.dy;
    final distanceFromBottom = pointer.dy - (bottom - 80);
    final delta =
        distanceFromTop > 0
            ? -((distanceFromTop / 5).ceil().clamp(1, 18))
            : distanceFromBottom > 0
            ? (distanceFromBottom / 5).ceil().clamp(1, 18)
            : 0;
    if (delta == 0) return;
    final position = scrollable.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next != position.pixels) position.jumpTo(next);
  }

  Map<String, Offset> _positionsFor(List<String> ids) {
    final positions = <String, Offset>{};
    for (final id in ids) {
      final position = _positionFor(id);
      if (position != null) positions[id] = position;
    }
    return positions;
  }

  Offset? _positionFor(String id) {
    return _rectFor(id)?.topLeft;
  }

  Rect? _rectFor(String id) {
    final tileContext = _tileKeys[id]?.currentContext;
    if (tileContext == null || !tileContext.mounted) return null;
    RenderObject? object;
    try {
      object = tileContext.findRenderObject();
    } on FlutterError {
      // GlobalKey 可能在拖动收拢选中项的同一帧仍指向已卸载的旧 tile。
      return null;
    }
    if (object is! RenderBox || !object.hasSize) return null;
    return object.localToGlobal(Offset.zero) & object.size;
  }

  void _settleDragFeedback(
    _PhotoDragPayload payload,
    DraggableDetails details, {
    required bool accepted,
    Offset feedbackOffset = Offset.zero,
  }) {
    final targetRect = accepted ? _rectFor(payload.draggedId) : _dragOriginRect;
    if (targetRect == null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayObject = overlay?.context.findRenderObject();
    if (overlay == null ||
        overlayObject is! RenderBox ||
        !overlayObject.hasSize) {
      return;
    }

    _removeSettleOverlay();
    final targetTopLeft = overlayObject.globalToLocal(targetRect.topLeft);
    final startTopLeft = overlayObject.globalToLocal(
      details.offset + feedbackOffset,
    );
    final target = targetTopLeft & targetRect.size;
    final start = Rect.fromLTWH(
      startTopLeft.dx,
      startTopLeft.dy,
      payload.feedbackWidth,
      payload.feedbackHeight,
    );
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (overlayContext) => TweenAnimationBuilder<Rect>(
            tween: _PhotoRectTween(begin: start, end: target),
            duration: DesktopMotion.of(
              overlayContext,
              DesktopMotion.photoReorderSettle,
            ),
            curve: DesktopMotion.photoReorderSettleCurve,
            onEnd: () {
              if (identical(_settleOverlay, entry)) _removeSettleOverlay();
            },
            builder:
                (context, rect, child) => Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: rect.width,
                      height: rect.height,
                      child: FittedBox(fit: BoxFit.fill, child: child),
                    ),
                  ),
                ),
            child: _PhotoDragFeedback(
              photos: payload.movingPhotos,
              fanOffsets: payload.fanOffsets,
              width: payload.feedbackWidth,
              height: payload.feedbackHeight,
              dropping: true,
            ),
          ),
    );
    _settleOverlay = entry;
    overlay.insert(entry);
  }

  void _removeSettleOverlay() {
    final entry = _settleOverlay;
    _settleOverlay = null;
    entry?.remove();
    entry?.dispose();
  }

  void _finishDrag(
    _PhotoDragPayload payload,
    DraggableDetails details,
    int generation,
  ) {
    if (!mounted || generation != _dragGeneration) return;
    final feedbackOffset = _dragFeedbackOffset.value;
    final activePayload = _activeDragPayload ?? payload;
    final collapsedOrder = _dragOrder ?? activePayload.baseOrderIds;
    final moved = !_sameOrder(activePayload.baseOrderIds, collapsedOrder);
    final accepted = moved && !_dragCanceled;
    final order =
        accepted
            ? _expandedOrder(collapsedOrder, activePayload)
            : activePayload.orderIds;
    // 样例 `reorder.tsx` 在所有已激活的拖拽结束后都记录 justDragged，
    // 包含原地松手。否则 PointerUp 后紧随的合成 click 会把预览误判成
    // 打开查看器；只有 Esc 是明确取消，才允许立即点击另一张照片。
    _startTrailingClickGuard();
    if (moved) {
      // 真发生换位才播「飞回原位」的收束动画；长按后原地松手只是预览，
      // 不能插入 rootOverlay，否则进入查看器后旧图仍浮在最上层。
      _settleDragFeedback(
        activePayload,
        details,
        accepted: accepted,
        feedbackOffset: feedbackOffset,
      );
    } else {
      _dragFeedbackDismissed.value = true;
      _removeSettleOverlay();
    }
    _stopDragSmoothing();
    final onOrderChanged = widget.onOrderChanged;
    if (accepted &&
        !_sameOrder(activePayload.orderIds, order) &&
        onOrderChanged != null) {
      unawaited(
        onOrderChanged(
          activePayload.contextKey,
          order,
          activePayload.movingPhotos.length,
        ),
      );
    }
    if (accepted && activePayload.movingIds.length > 1) {
      _landedTimer?.cancel();
      _landedPhotoIds = Set<String>.of(activePayload.movingIds);
      _landedTimer = Timer(DesktopMotion.photoReorderLanded, () {
        if (mounted) setState(() => _landedPhotoIds = <String>{});
      });
    }
    setState(() {
      _dragOrder = null;
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _lastSwapPointer = null;
      _draggedPhotoId = null;
      _activeDragPayload = null;
    });
    _dragOriginRect = null;
    _dragStartRects = <String, Rect>{};
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _pressTimer?.cancel();
    _landedTimer?.cancel();
    _clickGuardTimer?.cancel();
    _removeSettleOverlay();
    _dragSmoothingTicker.dispose();
    _dragFeedbackDismissed.dispose();
    _dragFeedbackOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos =
        _dragOrder == null
            ? widget.photos
            : applyPhotoDisplayOrder(
              widget.photos
                  .where((photo) => _dragOrder!.contains(photo.id))
                  .toList(growable: false),
              _dragOrder,
            );
    for (final photo in photos) {
      _tileKeys.putIfAbsent(
        photo.id,
        () => GlobalObjectKey<State<StatefulWidget>>('photo-order-${photo.id}'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (photos.length == 1) {
          // 样例 `.justified.solo`：单张照片不再按 flex 铺满整行，
          // 而是保持自身比例，并在右侧（窄窗换行）显示一块拍摄信息。
          return _soloLayout(context, photos.first, width);
        }
        final rows = _layout(width, photos);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        flex: (row[i].ratio * 1000).round(),
                        child: LayoutBuilder(
                          builder: (context, tileConstraints) {
                            final photo = row[i].photo;
                            final card = DesktopStagger(
                              index: i,
                              child: _PhotoTile(
                                key: ValueKey<String>(
                                  'desktop-photo-${photo.id}',
                                ),
                                photo: photo,
                                height: widget.targetHeight,
                                onTap: (selectedPhoto) {
                                  if (_draggedPhotoId != null) {
                                    _cancelReorder();
                                    return;
                                  }
                                  if (_justDragged) return;
                                  widget.onActivate(selectedPhoto, photos);
                                },
                                onToggleSelect: widget.onToggleSelect,
                                selected: widget.selection.contains(photo.id),
                                pressing: _pressingPhotoIds.contains(photo.id),
                                dragging: _draggedPhotoId == photo.id,
                                reordering: _draggedPhotoId != null,
                                landed: _landedPhotoIds.contains(photo.id),
                                selectionActive: widget.selection.isNotEmpty,
                                showCaption: widget.showCaption,
                                showFavorite: widget.showFavorite,
                                showSelectionControls:
                                    widget.showSelectionControls,
                              ),
                            );
                            final orderContext = widget.orderContext;
                            final onOrderChanged = widget.onOrderChanged;
                            if (orderContext == null ||
                                onOrderChanged == null ||
                                photos.length < 2) {
                              return card;
                            }
                            final selectedIds = widget.selection;
                            final movingPhotos =
                                selectedIds.contains(photo.id) &&
                                        selectedIds.length > 1
                                    ? photos
                                        .where(
                                          (item) =>
                                              selectedIds.contains(item.id),
                                        )
                                        .toList(growable: false)
                                    : <PhotoItem>[photo];
                            final movingIds = movingPhotos
                                .map((item) => item.id)
                                .toList(growable: false);
                            final orderIds = photos
                                .map((item) => item.id)
                                .toList(growable: false);
                            final feedbackWidth =
                                movingPhotos.length > 1 &&
                                        tileConstraints.maxWidth > 190
                                    ? 190.0
                                    : tileConstraints.maxWidth;
                            final feedbackHeight =
                                widget.targetHeight *
                                feedbackWidth /
                                tileConstraints.maxWidth;
                            final payload = _PhotoDragPayload(
                              contextKey: orderContext,
                              orderIds: orderIds,
                              baseOrderIds: orderIds
                                  .where(
                                    (id) =>
                                        id == photo.id ||
                                        !movingIds.contains(id),
                                  )
                                  .toList(growable: false),
                              draggedId: photo.id,
                              movingIds: movingIds,
                              movingPhotos: movingPhotos,
                              feedbackWidth: feedbackWidth,
                              feedbackHeight: feedbackHeight,
                              fanOffsets: _fanOffsets(
                                photo.id,
                                movingPhotos,
                                feedbackWidth,
                                feedbackHeight,
                              ),
                            );
                            final tileKey = _tileKeys[photo.id]!;
                            final dragGeneration = _dragGeneration;
                            final draggable = LongPressDraggable<
                              _PhotoDragPayload
                            >(
                              key: ValueKey<String>(
                                'photo-drag-${photo.id}-$dragGeneration',
                              ),
                              data: payload,
                              maxSimultaneousDrags:
                                  _blockedReorderPhotoId == photo.id ? 0 : 1,
                              delay: DesktopMotion.photoReorderHold,
                              dragAnchorStrategy: childDragAnchorStrategy,
                              feedback: ValueListenableBuilder<bool>(
                                valueListenable: _dragFeedbackDismissed,
                                builder: (context, dismissed, _) {
                                  if (dismissed) {
                                    return const SizedBox.shrink();
                                  }
                                  return ValueListenableBuilder<Offset>(
                                    valueListenable: _dragFeedbackOffset,
                                    builder:
                                        (context, offset, _) =>
                                            Transform.translate(
                                              offset: offset,
                                              child: _PhotoDragFeedback(
                                                photos: movingPhotos,
                                                fanOffsets: payload.fanOffsets,
                                                width: feedbackWidth,
                                                height: feedbackHeight,
                                              ),
                                            ),
                                  );
                                },
                              ),
                              onDragStarted:
                                  () => _startDrag(payload, dragGeneration),
                              onDragUpdate: (details) {
                                final pointer = details.globalPosition;
                                _updateDragPointer(pointer);
                                final targetId = _photoAt(pointer, payload);
                                if (targetId != null) {
                                  _trackTarget(payload, targetId, pointer);
                                }
                                _autoScroll(pointer);
                              },
                              onDragEnd:
                                  (details) => _finishDrag(
                                    payload,
                                    details,
                                    dragGeneration,
                                  ),
                              childWhenDragging: card,
                              child: card,
                            );
                            return TweenAnimationBuilder<Offset>(
                              tween: Tween<Offset>(
                                begin: _flipOffsets[photo.id] ?? Offset.zero,
                                end: Offset.zero,
                              ),
                              duration: DesktopMotion.of(
                                context,
                                DesktopMotion.photoReorderFlip,
                              ),
                              curve: DesktopMotion.photoReorderFlipCurve,
                              builder:
                                  (context, offset, child) =>
                                      Transform.translate(
                                        offset: offset,
                                        child: child,
                                      ),
                              child: DragTarget<_PhotoDragPayload>(
                                onWillAcceptWithDetails:
                                    (details) =>
                                        details.data.contextKey ==
                                            orderContext &&
                                        details.data.draggedId != photo.id,
                                key: tileKey,
                                builder:
                                    (context, candidates, rejected) => Listener(
                                      onPointerDown:
                                          (event) => _onTilePointerDown(
                                            payload,
                                            event,
                                            event.localPosition,
                                          ),
                                      onPointerMove: _onTilePointerMove,
                                      onPointerUp: _onTilePointerEnd,
                                      onPointerCancel:
                                          (event) => _onTilePointerEnd(
                                            event,
                                            canceled: true,
                                          ),
                                      child: draggable,
                                    ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  List<_PhotoFlyOffset> _fanOffsets(
    String draggedId,
    List<PhotoItem> movingPhotos,
    double feedbackWidth,
    double feedbackHeight,
  ) {
    final activeDrag = _draggedPhotoId != null;
    final origin =
        _dragStartRects[draggedId] ?? (activeDrag ? null : _rectFor(draggedId));
    return movingPhotos
        .map((photo) {
          final source =
              _dragStartRects[photo.id] ??
              (activeDrag ? null : _rectFor(photo.id));
          if (origin == null ||
              source == null ||
              feedbackWidth <= 0 ||
              feedbackHeight <= 0) {
            return const _PhotoFlyOffset();
          }
          return _PhotoFlyOffset(
            dx: source.center.dx - origin.center.dx,
            dy: source.center.dy - origin.center.dy,
            sx: source.width / feedbackWidth,
            sy: source.height / feedbackHeight,
          );
        })
        .toList(growable: false);
  }

  /// 单张照片：照片按原比例 + `.solo-note` 旁注（polish.css:324-328）。
  Widget _soloLayout(BuildContext context, PhotoItem photo, double width) {
    final ratio = _ratioOf(photo);
    final photoWidth = (widget.targetHeight * ratio).clamp(120.0, width);
    final noteWidth = (width - photoWidth - 20).clamp(220.0, 320.0);
    final tile = SizedBox(
      width: photoWidth,
      height: widget.targetHeight,
      child: _PhotoTile(
        photo: photo,
        height: widget.targetHeight,
        onTap:
            (selectedPhoto) =>
                widget.onActivate(selectedPhoto, <PhotoItem>[photo]),
        onToggleSelect: widget.onToggleSelect,
        selected: widget.selection.contains(photo.id),
        selectionActive: widget.selection.isNotEmpty,
        showCaption: widget.showCaption,
        showFavorite: widget.showFavorite,
        showSelectionControls: widget.showSelectionControls,
      ),
    );
    return Wrap(
      spacing: 20,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        tile,
        SizedBox(width: noteWidth, child: _SoloNote(photo: photo)),
      ],
    );
  }

  List<List<_SizedPhoto>> _layout(double width, List<PhotoItem> photos) {
    final rows = <List<_SizedPhoto>>[];
    var current = <_SizedPhoto>[];
    var ratioSum = 0.0;
    for (final photo in photos) {
      final ratio = _ratioOf(photo);
      current.add(_SizedPhoto(photo: photo, ratio: ratio));
      ratioSum += ratio;
      if (ratioSum * widget.targetHeight >= width) {
        rows.add(current);
        current = <_SizedPhoto>[];
        ratioSum = 0;
      }
    }
    if (current.isNotEmpty) {
      rows.add(current);
    }
    return rows;
  }

  /// 宽高比夹在 0.5–2.2：极端长图会把整行压成一条缝。
  double _ratioOf(PhotoItem photo) {
    final width = photo.width ?? 0;
    final height = photo.height ?? 0;
    if (width <= 0 || height <= 0) {
      return 1.5;
    }
    return (width / height).clamp(0.5, 2.2);
  }

  bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
