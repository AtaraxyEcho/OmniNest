import 'package:flutter/material.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 样例 `.tilt` + `.shine`：卡片跟随指针做透视倾斜，同时一束柔光在
/// 指针处扫过。
///
/// 倾斜角度按样例的 `max`（海报 7°，专辑 5°）换算到 −max..max；柔光是
/// 以指针为圆心的径向渐变，`soft-light` 混合在 Flutter 里没有等价物，
/// 用低不透明度的白色叠加逼近（样例本身也只是 0.22 的白）。
class DesktopTilt extends StatefulWidget {
  const DesktopTilt({
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.maxDegrees = 7,
    this.radius = 16,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
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
    final skin = DesktopSkin.of(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final nx = (_fraction.dx - 0.5) * 2;
    final ny = (_fraction.dy - 0.5) * 2;
    final maxRadians = widget.maxDegrees * 3.1415926535 / 180;
    final matrix =
        Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateX(_hovered && !reduced ? -ny * maxRadians : 0)
          ..rotateY(_hovered && !reduced ? nx * maxRadians : 0);

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
        child: AnimatedContainer(
          duration: DesktopMotion.of(
            context,
            const Duration(milliseconds: 350),
          ),
          curve: DesktopMotion.ease,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow:
                _hovered
                    ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 60,
                        offset: const Offset(0, 30),
                        spreadRadius: -20,
                      ),
                    ]
                    : null,
          ),
          child: AnimatedSlide(
            duration: DesktopMotion.of(
              context,
              const Duration(milliseconds: 350),
            ),
            curve: DesktopMotion.ease,
            offset: Offset.zero,
            child: Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.radius),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    widget.child,
                    // `.shine`：指针处的柔光，只在悬停时出现。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: DesktopMotion.of(
                            context,
                            const Duration(milliseconds: 300),
                          ),
                          opacity: _hovered ? 1 : 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(
                                  _fraction.dx * 2 - 1,
                                  _fraction.dy * 2 - 1,
                                ),
                                radius: 0.9,
                                colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
                                stops: [0.0, 0.55],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.radius,
                              ),
                              border: Border.all(color: skin.line2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
