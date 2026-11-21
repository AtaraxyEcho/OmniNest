part of 'desktop_photos_page.dart';

class _PhotoDragPayload {
  _PhotoDragPayload({
    required this.contextKey,
    required this.orderIds,
    required this.baseOrderIds,
    required this.draggedId,
    required this.movingIds,
    required this.movingPhotos,
    required this.feedbackWidth,
    required this.feedbackHeight,
    required this.fanOffsets,
    required this.grabOffset,
  });

  final String contextKey;
  final List<String> orderIds;
  final List<String> baseOrderIds;
  final String draggedId;
  final List<String> movingIds;
  final List<PhotoItem> movingPhotos;
  final double feedbackWidth;
  final double feedbackHeight;
  final List<_PhotoFlyOffset> fanOffsets;
  final Offset grabOffset;
}

class _PhotoFlyOffset {
  const _PhotoFlyOffset({this.dx = 0, this.dy = 0, this.sx = 1, this.sy = 1});

  final double dx;
  final double dy;
  final double sx;
  final double sy;
}

@immutable
class _GhostPose {
  const _GhostPose({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.dropping = false,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final bool dropping;

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  _GhostPose copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
    bool? dropping,
  }) {
    return _GhostPose(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
      dropping: dropping ?? this.dropping,
    );
  }
}

/// 跨卡片共享的 FLIP 快照追踪器：在 `setState` 变更顺序前一次性记录
/// 所有卡片带滚动偏移补偿的视觉坐标，在下一帧 `paint` 前同步起播补间，
/// 彻底杜绝 1 帧瞬移闪烁。
class _PhotoFlipTracker {
  _PhotoFlipTracker({required this.scrollOffsetOf});

  final double Function() scrollOffsetOf;
  int epoch = 0;
  String? skipPhotoId;
  final Map<String, Offset> previousPositions = <String, Offset>{};
  final Map<String, Offset> activeVisualOffsets = <String, Offset>{};

  void snapshot(Map<String, GlobalKey<State<StatefulWidget>>> tileKeys) {
    previousPositions.clear();
    final scrollOffset = scrollOffsetOf();
    for (final entry in tileKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null || !ctx.mounted) continue;
      RenderObject? renderObject;
      try {
        renderObject = ctx.findRenderObject();
      } on FlutterError {
        continue;
      }
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final visualOffset = activeVisualOffsets[entry.key] ?? Offset.zero;
      final globalTopLeft = renderObject.localToGlobal(Offset.zero);
      previousPositions[entry.key] = Offset(
        globalTopLeft.dx + visualOffset.dx,
        globalTopLeft.dy + scrollOffset + visualOffset.dy,
      );
    }
    epoch++;
  }

  void clear() {
    previousPositions.clear();
    activeVisualOffsets.clear();
    skipPhotoId = null;
  }
}

/// 零闪烁同步 FLIP 容器：使用显式 `AnimationController(460ms)` 与自定义
/// `RenderProxyBox`，在新布局首帧 `paint` 前即时计算带 `scrollOffset` 补偿的
/// 位移差并绘制在旧坐标，随后由控制器平滑归零。
class _FlipPhotoTile extends StatefulWidget {
  const _FlipPhotoTile({
    super.key,
    required this.photoId,
    required this.tracker,
    required this.epoch,
    required this.child,
  });

  final String photoId;
  final _PhotoFlipTracker tracker;
  final int epoch;
  final Widget child;

  @override
  State<_FlipPhotoTile> createState() => _FlipPhotoTileState();
}

class _FlipPhotoTileState extends State<_FlipPhotoTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset _flipDelta = Offset.zero;
  Offset _currentOffset = Offset.zero;
  int _handledEpoch = 0;

  @override
  void initState() {
    super.initState();
    _handledEpoch = widget.epoch;
    _controller = AnimationController(
      vsync: this,
      duration: DesktopMotion.photoReorderFlip,
    )..addListener(_onTick);
  }

  @override
  void didUpdateWidget(_FlipPhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoId != widget.photoId) {
      oldWidget.tracker.activeVisualOffsets.remove(oldWidget.photoId);
      _flipDelta = Offset.zero;
      _currentOffset = Offset.zero;
      _controller.stop();
      _handledEpoch = widget.epoch;
    }
  }

  void _onTick() {
    final eased = DesktopMotion.photoReorderFlipCurve.transform(
      _controller.value.clamp(0.0, 1.0),
    );
    final next = _flipDelta * (1.0 - eased);
    _currentOffset = next.distanceSquared < 0.04 ? Offset.zero : next;
    if (_currentOffset == Offset.zero) {
      widget.tracker.activeVisualOffsets.remove(widget.photoId);
    } else {
      widget.tracker.activeVisualOffsets[widget.photoId] = _currentOffset;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is _RenderFlipPhotoTile) {
      renderObject.paintOffset = _currentOffset;
    }
  }

  Offset _consumePendingFlip(Offset newCompensatedPosition) {
    if (widget.epoch == _handledEpoch) {
      return _currentOffset;
    }
    _handledEpoch = widget.epoch;
    if (widget.photoId == widget.tracker.skipPhotoId) {
      _flipDelta = Offset.zero;
      _currentOffset = Offset.zero;
      widget.tracker.activeVisualOffsets.remove(widget.photoId);
      return Offset.zero;
    }
    final oldPos = widget.tracker.previousPositions[widget.photoId];
    if (oldPos == null) {
      return _currentOffset;
    }
    final delta = oldPos - newCompensatedPosition;
    if (delta.distance <= 1.0) {
      return _currentOffset;
    }
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _flipDelta = Offset.zero;
      _currentOffset = Offset.zero;
      widget.tracker.activeVisualOffsets.remove(widget.photoId);
      return Offset.zero;
    }
    _flipDelta = delta;
    _currentOffset = delta;
    widget.tracker.activeVisualOffsets[widget.photoId] = delta;
    scheduleMicrotask(() {
      if (!mounted) return;
      _controller.duration = DesktopMotion.of(
        context,
        DesktopMotion.photoReorderFlip,
      );
      _controller.forward(from: 0.0);
    });
    return delta;
  }

  @override
  void dispose() {
    widget.tracker.activeVisualOffsets.remove(widget.photoId);
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FlipPhotoRenderWidget(
      epoch: widget.epoch,
      scrollOffsetOf: widget.tracker.scrollOffsetOf,
      onResolveFlip: _consumePendingFlip,
      initialOffset: _currentOffset,
      child: widget.child,
    );
  }
}

class _FlipPhotoRenderWidget extends SingleChildRenderObjectWidget {
  const _FlipPhotoRenderWidget({
    required this.epoch,
    required this.scrollOffsetOf,
    required this.onResolveFlip,
    required this.initialOffset,
    super.child,
  });

  final int epoch;
  final double Function() scrollOffsetOf;
  final Offset Function(Offset compensatedPosition) onResolveFlip;
  final Offset initialOffset;

  @override
  _RenderFlipPhotoTile createRenderObject(BuildContext context) {
    return _RenderFlipPhotoTile(
      epoch: epoch,
      scrollOffsetOf: scrollOffsetOf,
      onResolveFlip: onResolveFlip,
      paintOffset: initialOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFlipPhotoTile renderObject,
  ) {
    renderObject
      ..scrollOffsetOf = scrollOffsetOf
      ..onResolveFlip = onResolveFlip
      ..epoch = epoch;
  }
}

class _RenderFlipPhotoTile extends RenderProxyBox {
  _RenderFlipPhotoTile({
    required int epoch,
    required this.scrollOffsetOf,
    required this.onResolveFlip,
    required Offset paintOffset,
  }) : _epoch = epoch,
       _paintOffset = paintOffset;

  double Function() scrollOffsetOf;
  Offset Function(Offset compensatedPosition) onResolveFlip;

  int _epoch;
  bool _pendingResolve = false;
  Offset _paintOffset;

  set epoch(int value) {
    if (_epoch == value) return;
    _epoch = value;
    _pendingResolve = true;
    markNeedsPaint();
  }

  set paintOffset(Offset value) {
    if (_paintOffset == value) return;
    _paintOffset = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_pendingResolve) {
      _pendingResolve = false;
      final globalTopLeft = localToGlobal(Offset.zero);
      final compensated = Offset(
        globalTopLeft.dx,
        globalTopLeft.dy + scrollOffsetOf(),
      );
      _paintOffset = onResolveFlip(compensated);
    }
    if (_paintOffset == Offset.zero) {
      super.paint(context, offset);
      return;
    }
    context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(_paintOffset.dx, _paintOffset.dy, 0),
      super.paint,
    );
  }
}

class _PhotoDragFeedback extends StatelessWidget {
  const _PhotoDragFeedback({
    required this.photos,
    required this.fanOffsets,
    required this.width,
    required this.height,
    this.dropping = false,
  });

  final List<PhotoItem> photos;
  final List<_PhotoFlyOffset> fanOffsets;
  final double width;
  final double height;
  final bool dropping;

  @override
  Widget build(BuildContext context) {
    final stack = photos.length > 1;
    final visibleCards = photos.length.clamp(1, 9).toInt();
    final skin = DesktopSkin.of(context);
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = visibleCards - 1; index >= 0; index--)
              _PhotoFanCard(
                key: ValueKey<String>('fan-card-${photos[index].id}'),
                photo: photos[index],
                source:
                    index < fanOffsets.length
                        ? fanOffsets[index]
                        : const _PhotoFlyOffset(),
                index: index,
                stack: stack,
                dropping: dropping,
              ),
            if (stack)
              Positioned(
                top: -10,
                right: -10,
                child: AnimatedOpacity(
                  opacity: dropping ? 0 : 1,
                  duration: DesktopMotion.photoReorderFastFade,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.accent,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          offset: const Offset(0, 6),
                          blurRadius: 16,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Text(
                      '${photos.length}',
                      style: DesktopType.caption(skin.accentInk),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 幽灵扇形卡片：使用稳定 `ValueKey('fan-card-${id}')` + 显式控制器，
/// 松手收束时在 `didUpdateWidget` 平滑插值，绝不重建封面图。
class _PhotoFanCard extends StatefulWidget {
  const _PhotoFanCard({
    super.key,
    required this.photo,
    required this.source,
    required this.index,
    required this.stack,
    required this.dropping,
  });

  final PhotoItem photo;
  final _PhotoFlyOffset source;
  final int index;
  final bool stack;
  final bool dropping;

  @override
  State<_PhotoFanCard> createState() => _PhotoFanCardState();
}

class _PhotoFanCardState extends State<_PhotoFanCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isDropPhase = false;

  Offset _fromOffset = Offset.zero;
  double _fromAngle = 0.0;
  double _fromScaleX = 1.0;
  double _fromScaleY = 1.0;
  double _fromOpacity = 1.0;

  Offset get _fanOffset => switch (widget.index) {
    1 => const Offset(-9, 7),
    2 => const Offset(10, 10),
    _ => Offset.zero,
  };

  double get _fanAngle => switch (widget.index) {
    1 => -0.10472,
    2 => 0.08727,
    _ => 0.0,
  };

  bool get _hidden => widget.stack && widget.index >= 3;

  double get _fanScale =>
      widget.stack && widget.index == 0 ? 1.04 : (widget.stack ? 1.0 : 1.05);

  @override
  void initState() {
    super.initState();
    _isDropPhase = widget.dropping;
    _controller = AnimationController(
      vsync: this,
      duration: _phaseDuration(dropping: _isDropPhase),
    );
    if (_isDropPhase) {
      _fromOffset = _hidden ? Offset.zero : _fanOffset;
      _fromAngle = _fanAngle;
      _fromScaleX = _fanScale;
      _fromScaleY = _fanScale;
      _fromOpacity = _hidden ? 0.0 : 1.0;
    }
    _controller.forward(from: 0.0);
  }

  Duration _phaseDuration({required bool dropping}) {
    if (dropping) {
      return widget.stack
          ? DesktopMotion.photoReorderDrop
          : DesktopMotion.photoReorderSettle;
    }
    return DesktopMotion.photoReorderFan +
        (DesktopMotion.photoReorderFanStagger * widget.index);
  }

  ({Offset offset, double angle, double scaleX, double scaleY, double opacity})
  _evaluatePose(double rawValue) {
    final progress = DesktopMotion.ease.transform(rawValue.clamp(0.0, 1.0));
    if (_isDropPhase) {
      return (
        offset: Offset.lerp(_fromOffset, Offset.zero, progress)!,
        angle: _mix(_fromAngle, 0.0, progress),
        scaleX: _mix(_fromScaleX, 1.0, progress),
        scaleY: _mix(_fromScaleY, 1.0, progress),
        opacity: _mix(_fromOpacity, _hidden ? 0.0 : 1.0, progress),
      );
    }
    final startOffset = Offset(widget.source.dx, widget.source.dy);
    final targetOffset = _hidden ? Offset.zero : _fanOffset;
    return (
      offset: Offset.lerp(startOffset, targetOffset, progress)!,
      angle: _fanAngle * progress,
      scaleX: _mix(widget.source.sx, _fanScale, progress),
      scaleY: _mix(widget.source.sy, _fanScale, progress),
      opacity: _hidden ? (1.0 - progress).clamp(0.0, 1.0) : 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant _PhotoFanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.dropping && widget.dropping) {
      final snapshot = _evaluatePose(_controller.value);
      _fromOffset = snapshot.offset;
      _fromAngle = snapshot.angle;
      _fromScaleX = snapshot.scaleX;
      _fromScaleY = snapshot.scaleY;
      _fromOpacity = snapshot.opacity;
      _isDropPhase = true;
      _controller.duration = _phaseDuration(dropping: true);
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coverChild = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            offset: const Offset(0, 16),
            blurRadius: 34,
            spreadRadius: -10,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.4),
            blurRadius: 0,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: DesktopCover(
            url: widget.photo.coverUrl,
            kind: DesktopCoverKind.network,
            fit: BoxFit.cover,
            fallbackIcon: DesktopIcons.image,
            cacheKey: 'desktop-photo-${widget.photo.id}',
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          child: coverChild,
          builder: (context, child) {
            final pose = _evaluatePose(_controller.value);
            return Opacity(
              opacity: pose.opacity,
              child: Transform.translate(
                offset: pose.offset,
                child: Transform.rotate(
                  angle: pose.angle,
                  child: Transform.scale(
                    scaleX: pose.scaleX,
                    scaleY: pose.scaleY,
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _mix(double from, double to, double progress) =>
      from + (to - from) * progress;
}
