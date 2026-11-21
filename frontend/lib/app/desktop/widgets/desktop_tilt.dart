import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';

/// 样例 `.tilt`：卡片跟随指针做透视倾斜（350ms 缓动过渡与平滑复位），
/// 悬停时对内部子图施加 1.06× 缩放，不叠加多余强调色外框（对齐 desktop.css:260-261）。
class DesktopTilt extends StatefulWidget {
  const DesktopTilt({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.maxDegrees = 7,
    this.radius = 16,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double maxDegrees;
  final double radius;

  @override
  State<DesktopTilt> createState() => _DesktopTiltState();
}

class _DesktopTiltState extends State<DesktopTilt> {
  Offset _fraction = const Offset(0.5, 0.5);
  bool _hovered = false;

  void _update(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    setState(() {
      _fraction = Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final nx = (_fraction.dx - 0.5) * 2;
    final ny = (_fraction.dy - 0.5) * 2;
    final maxRadians = widget.maxDegrees * 3.1415926535 / 180;
    final targetTilt =
        _hovered && !reduced
            ? Offset(-ny * maxRadians, nx * maxRadians)
            : Offset.zero;
    final duration = DesktopMotion.of(
      context,
      const Duration(milliseconds: 350),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _fraction = const Offset(0.5, 0.5);
        });
      },
      onHover: (event) {
        final box = context.findRenderObject();
        if (box is RenderBox) {
          _update(event.localPosition, box.size);
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: RepaintBoundary(
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(end: targetTilt),
            duration: duration,
            curve: DesktopMotion.ease,
            builder: (context, tilt, child) {
              final matrix =
                  Matrix4.identity()
                    ..setEntry(3, 2, 0.0014)
                    ..rotateX(tilt.dx)
                    ..rotateY(tilt.dy);
              return Transform(
                alignment: Alignment.center,
                transform: matrix,
                child: child,
              );
            },
            child: AnimatedContainer(
              duration: duration,
              curve: DesktopMotion.ease,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                boxShadow:
                    _hovered
                        ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                            spreadRadius: -18,
                          ),
                        ]
                        : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.radius),
                child: AnimatedScale(
                  scale: _hovered && !reduced ? 1.06 : 1.0,
                  duration: duration,
                  curve: DesktopMotion.ease,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
