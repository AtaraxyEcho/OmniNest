import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 音乐甲板与沉浸播放器之间的同路由过渡。
///
/// 同路由内的 AnimatedSwitcher 不触发 Hero，硬编码 tag 还会与列表封面重复；
/// 这里只做短距上滑 + 淡入，位移轴与卡片内容的主延展方向一致。
Widget musicDeckImmersiveTransition(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: MotionToken.pageCurve,
  );
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    ),
  );
}
