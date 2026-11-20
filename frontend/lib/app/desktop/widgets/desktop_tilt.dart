import 'package:flutter/material.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 样例 `.tilt`：卡片跟随指针做透视倾斜。
///
/// 倾斜角度按样例的 `max`（海报 7°，专辑 5°）换算到 −max..max。
/// 最终样例 CSS 隐藏了 `.shine`，所以这里不再叠加指针追踪光晕；否则
/// Movies 海报会比样例多一层彩色/白色高光，悬停时的视觉重量也会变重。
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
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final nx = (_fraction.dx - 0.5) * 2;
    final ny = (_fraction.dy - 0.5) * 2;
    final maxRadians = widget.maxDegrees * 3.1415926535 / 180;
    final matrix =
        Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateX(_hovered && !reduced ? -ny * maxRadians : 0)
          ..rotateY(_hovered && !reduced ? nx * maxRadians : 0);

    final skin = DesktopSkin.of(context);
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
        // 投影、描边与遮罩必须和图片一起倾斜：样例 `.tilt::after` 是元素
        // 自身的伪层，旧的 Flutter 实现把它们留在未旋转的外层，悬停时
        // 卡片边缘会露出一条没有被遮罩/描边覆盖的亮边。
        child: RepaintBoundary(
          child: Transform(
            alignment: Alignment.center,
            transform: matrix,
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
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                            spreadRadius: -18,
                          ),
                        ]
                        : null,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color:
                      _hovered && !reduced
                          ? skin.accent.withValues(alpha: 0.70)
                          : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.radius),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
