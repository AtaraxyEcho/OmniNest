import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 状态指示灯：规范唯一允许的正圆元素。
///
/// 心跳脉冲为克制动效：仅持续约 5 秒（3 个周期）后保持常亮，
/// 避免长驻动画干扰焦点与自动化校验。
class AdminStatusDot extends StatefulWidget {
  const AdminStatusDot({required this.color, this.pulsing = false, super.key});

  final Color color;
  final bool pulsing;

  @override
  State<AdminStatusDot> createState() => _AdminStatusDotState();
}

class _AdminStatusDotState extends State<AdminStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _pulseStopTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.pulsing) {
      if (MotionToken.prefersReducedOnPlatform()) {
        _controller.value = 1;
        return;
      }
      _controller.repeat(reverse: true);
      _pulseStopTimer = Timer(const Duration(seconds: 5), () {
        _controller.stop();
        _controller.value = 1;
      });
    }
  }

  @override
  void didUpdateWidget(covariant AdminStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing == oldWidget.pulsing) {
      return;
    }
    // 最常见路径：connecting(不闪)→healthy(脉冲)。不重启控制器会让
    // FadeTransition 钉死在 0.35 透明度，在线灯反而最暗。
    _pulseStopTimer?.cancel();
    _pulseStopTimer = null;
    if (widget.pulsing) {
      if (MotionToken.prefersReducedOnPlatform()) {
        _controller
          ..stop()
          ..value = 1;
        return;
      }
      _controller
        ..value = 0
        ..repeat(reverse: true);
      _pulseStopTimer = Timer(const Duration(seconds: 5), () {
        _controller.stop();
        _controller.value = 1;
      });
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _pulseStopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulsing) {
      return dot;
    }
    return RepaintBoundary(
      child: FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: dot,
      ),
    );
  }
}
