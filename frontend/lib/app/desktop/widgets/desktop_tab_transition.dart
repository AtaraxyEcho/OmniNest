import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';

/// 桌面详情页 Tab 切换过渡容器。
///
/// 组合 `AnimatedSize`（平滑高度，消除下方相关推荐瞬跳）与方向感知的
/// `AnimatedSwitcher`（基于 [tabIndex] 的固定像素微位移 ±18px / ∓12px + 淡入淡出）。
/// 严格遵循 Windows `ui::AXTree` 语义安全规范：
/// - `layoutBuilder` 使用 `excludeExitingSemanticsStack`；
/// - `FadeTransition` 显式开启 `alwaysIncludeSemantics: true`；
/// - 退场子树包裹 `IgnorePointer`，防止动画中途误触。
class DesktopTabTransition extends StatefulWidget {
  const DesktopTabTransition({
    required this.tabIndex,
    required this.child,
    super.key,
  });

  final int tabIndex;
  final Widget child;

  @override
  State<DesktopTabTransition> createState() => _DesktopTabTransitionState();
}

class _DesktopTabTransitionState extends State<DesktopTabTransition> {
  int _prevIndex = 0;
  double _direction = 1;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.tabIndex;
  }

  @override
  void didUpdateWidget(covariant DesktopTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabIndex != _prevIndex) {
      _direction = widget.tabIndex >= _prevIndex ? 1 : -1;
      _prevIndex = widget.tabIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeDuration = DesktopMotion.of(
      context,
      const Duration(milliseconds: 260),
    );
    final inDuration = DesktopMotion.of(
      context,
      const Duration(milliseconds: 240),
    );
    final outDuration = DesktopMotion.of(
      context,
      const Duration(milliseconds: 160),
    );
    final reduced = inDuration == Duration.zero;

    return AnimatedSize(
      duration: sizeDuration,
      curve: DesktopMotion.ease,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: inDuration,
        reverseDuration: outDuration,
        switchInCurve: DesktopMotion.ease,
        switchOutCurve: DesktopMotion.exitCurve,
        layoutBuilder:
            (currentChild, previousChildren) => excludeExitingSemanticsStack(
              currentChild,
              previousChildren,
              alignment: AlignmentDirectional.topStart,
            ),
        transitionBuilder: (child, animation) {
          final isEntering = child.key == widget.child.key;
          final faded = FadeTransition(
            opacity: animation,
            alwaysIncludeSemantics: true,
            child:
                reduced
                    ? child
                    : AnimatedBuilder(
                      animation: animation,
                      builder: (context, inner) {
                        final t = animation.value;
                        final dx =
                            isEntering
                                ? (1 - t) * 18.0 * _direction
                                : (1 - t) * -12.0 * _direction;
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: inner,
                        );
                      },
                      child: child,
                    ),
          );
          if (isEntering) {
            return faded;
          }
          return IgnorePointer(child: faded);
        },
        child: widget.child,
      ),
    );
  }
}
