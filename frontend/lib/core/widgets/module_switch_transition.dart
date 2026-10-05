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
    // 减弱动效：直接呈现子树终态，不包 Opaque/Transform，视觉结果不变。
    if (MotionToken.prefersReduced(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = Curves.easeOutQuart.transform(_controller.value);
        final offset = (1 - progress) * (_forward ? 10 : -10);
        return Opacity(
          opacity: 0.78 + progress * 0.22,
          child: Transform.translate(offset: Offset(offset, 0), child: child),
        );
      },
    );
  }
}
