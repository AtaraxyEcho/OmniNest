import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 键盘焦点环（样例 `desktop.css:42` 的
/// `:focus-visible{outline:2px solid accent; outline-offset:2px}`）。
///
/// 用 `foregroundPainter` 画在边界之外，不额外占位；`FocusableActionDetector`
/// 的 `onShowFocusHighlight` 只在「传统」高亮模式（键盘）上报，鼠标点击不会
/// 留一圈焦点框。
class DesktopFocusOutline extends StatefulWidget {
  const DesktopFocusOutline({
    required this.child,
    this.onActivate,
    this.radius = DesktopMetrics.radiusButton,
    super.key,
  });

  final Widget child;

  /// Enter / Space 激活；为空时不可聚焦，避免给纯展示块加 Tab 站点。
  final VoidCallback? onActivate;

  final double radius;

  @override
  State<DesktopFocusOutline> createState() => _DesktopFocusOutlineState();
}

class _DesktopFocusOutlineState extends State<DesktopFocusOutline> {
  bool _showRing = false;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final activate = widget.onActivate;
    if (activate == null) {
      return widget.child;
    }
    return FocusableActionDetector(
      enabled: true,
      onShowFocusHighlight: (value) => setState(() => _showRing = value),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            activate();
            return null;
          },
        ),
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: CustomPaint(
        foregroundPainter:
            _showRing
                ? _FocusRingPainter(
                  skin.accent.withValues(alpha: 0.70),
                  widget.radius,
                )
                : null,
        child: widget.child,
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-3, -3, size.width + 6, size.height + 6),
        Radius.circular(radius + 3),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
