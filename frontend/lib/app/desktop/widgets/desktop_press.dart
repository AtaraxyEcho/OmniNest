import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';

/// 按下缩放（样例 `.tb-btn:active`）。
///
/// 用 [Listener] 而不是手势识别器：按钮自己的 onTap 已经在手势竞技场里，
/// 这里只旁听指针状态，不参与竞争。
class DesktopPressScale extends StatefulWidget {
  const DesktopPressScale({
    required this.enabled,
    required this.child,
    this.scale = 0.88,
    super.key,
  });

  final bool enabled;
  final Widget child;

  /// `.tb-btn:active` 是 0.88；`.btn:active` 只有 0.96。
  final double scale;

  @override
  State<DesktopPressScale> createState() => DesktopPressScaleState();
}

class DesktopPressScaleState extends State<DesktopPressScale> {
  bool _down = false;

  void _set(bool value) {
    if (!widget.enabled || _down == value) {
      return;
    }
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: DesktopMotion.of(context, DesktopMotion.springHover),
        curve: DesktopMotion.spring,
        child: widget.child,
      ),
    );
  }
}

/// 徽标出现时的弹入（样例 `.badge { animation: pop .5s var(--spring) }`）。
class DesktopBadgePop extends StatefulWidget {
  const DesktopBadgePop({required this.value, required this.child, super.key});

  final int value;
  final Widget child;

  @override
  State<DesktopBadgePop> createState() => DesktopBadgePopState();
}

class DesktopBadgePopState extends State<DesktopBadgePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.badge,
    value: 1,
  );

  @override
  void didUpdateWidget(DesktopBadgePop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // pop：0.6 → 1.3（60%）→ 1。
        final t = _controller.value;
        final scale =
            t < 0.6
                ? 0.6 + (1.3 - 0.6) * (t / 0.6)
                : 1.3 - 0.3 * ((t - 0.6) / 0.4);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}
