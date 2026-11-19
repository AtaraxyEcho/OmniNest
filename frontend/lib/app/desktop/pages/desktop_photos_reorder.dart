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
}

class _PhotoFlyOffset {
  const _PhotoFlyOffset({this.dx = 0, this.dy = 0, this.sx = 1, this.sy = 1});

  final double dx;
  final double dy;
  final double sx;
  final double sy;
}

class _PhotoRectTween extends Tween<Rect> {
  _PhotoRectTween({required Rect begin, required Rect end})
    : super(begin: begin, end: end);

  @override
  Rect lerp(double t) => Rect.lerp(begin!, end!, t)!;
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
            for (var index = 0; index < visibleCards; index++)
              _PhotoFanCard(
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

class _PhotoFanCard extends StatelessWidget {
  const _PhotoFanCard({
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
  Widget build(BuildContext context) {
    final targetOffset = switch (index) {
      1 => const Offset(-9, 7),
      2 => const Offset(10, 10),
      _ => Offset.zero,
    };
    final targetAngle = switch (index) {
      1 => -0.10472,
      2 => 0.08727,
      _ => 0.0,
    };
    final hidden = stack && index >= 3;
    final duration =
        dropping
            ? (stack
                ? DesktopMotion.photoReorderDrop
                : DesktopMotion.photoReorderSettle)
            : DesktopMotion.photoReorderFan +
                (DesktopMotion.photoReorderFanStagger * index);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: DesktopMotion.ease,
      builder: (context, progress, child) {
        final from = Offset(source.dx, source.dy);
        final fan = hidden ? Offset.zero : targetOffset;
        final position =
            dropping
                ? Offset.lerp(fan, Offset.zero, progress)!
                : Offset.lerp(from, fan, progress)!;
        final targetScale = stack && index == 0 ? 1.04 : (stack ? 1.0 : 1.05);
        final scaleX = dropping ? 1.0 : _mix(source.sx, targetScale, progress);
        final scaleY = dropping ? 1.0 : _mix(source.sy, targetScale, progress);
        final rotation = targetAngle * (dropping ? 1 - progress : progress);
        final opacity = hidden ? (dropping ? 0.0 : 1 - progress) : 1.0;
        final dropScale = dropping && !stack ? 1 + (1 - progress) * 0.05 : 1.0;
        return Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: position,
                child: Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scaleX: scaleX * dropScale,
                    scaleY: scaleY * dropScale,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // 原型 `.ph-card` 在普通、堆叠和 drop 阶段都使用同一组
          // 16/34/-10 阴影与 1.5px 白边。旧实现把单卡换位改成大范围
          // 60px 黑影，松手时会读成一圈黑边，且和多选卡的边缘不一致。
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
          child: DesktopCover(
            url: photo.coverUrl,
            kind: DesktopCoverKind.network,
            fallbackIcon: DesktopIcons.image,
          ),
        ),
      ),
    );
  }

  double _mix(double from, double to, double progress) =>
      from + (to - from) * progress;
}
