import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 顶栏图标控件的统一悬停反馈：轻微放大替代置色高亮。
///
/// 缩放是纯视觉变换，不改变布局约束；系统开启减弱动态时不缩放。
class HoverScale extends StatefulWidget {
  const HoverScale({required this.child, this.scale = 1.08, super.key});

  final Widget child;
  final double scale;

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final allowScale = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: allowScale && _hovered ? widget.scale : 1.0,
        duration: MotionToken.fast,
        curve: MotionToken.curve,
        child: widget.child,
      ),
    );
  }
}
