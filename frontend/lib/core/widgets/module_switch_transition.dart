import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 在不复制页面树的前提下为模块切换提供短距离进入动画。
class ModuleSwitchTransition extends StatefulWidget {
  const ModuleSwitchTransition({
    required this.transitionKey,
    required this.child,
    this.forward = true,
    super.key,
  });

  final Object transitionKey;
  final Widget child;
  final bool forward;

  @override
  State<ModuleSwitchTransition> createState() => _ModuleSwitchTransitionState();
}

class _ModuleSwitchTransitionState extends State<ModuleSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late bool _forward;

  @override
  void initState() {
    super.initState();
    _forward = widget.forward;
    _controller = AnimationController(
      duration: MotionToken.pageSwitch,
      value: 1,
      vsync: this,
    );
    _opacity = Tween<double>(
      begin: 0.78,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));
  }

  @override
  void didUpdateWidget(covariant ModuleSwitchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transitionKey == widget.transitionKey) {
      return;
    }
    _forward = widget.forward;
    // 减弱动效：跳过过渡直接落在终态（value=1，全不透明、零位移）。
    if (MotionToken.prefersReduced(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 常驻同构树：无论动画进行中、已结束还是减弱动效，都保持
    // FadeTransition → AnimatedBuilder 的固定深度；Opacity 在 1.0 时
    // 不产生离屏合成层，也不会在完成瞬间让 StatefulNavigationShell 重挂。
    return FadeTransition(
      opacity: _opacity,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final progress =
              _controller.isCompleted
                  ? 1.0
                  : Curves.easeOutQuart.transform(_controller.value);
          final offset = (1 - progress) * (_forward ? 10.0 : -10.0);
          return Transform.translate(offset: Offset(offset, 0), child: child);
        },
      ),
    );
  }
}
