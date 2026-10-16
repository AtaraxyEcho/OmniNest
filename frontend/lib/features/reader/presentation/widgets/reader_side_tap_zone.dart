import 'package:flutter/material.dart';

/// 侧边点击区域。
///
/// 用真手势识别器（不是 Listener）声明这次点击：Listener 不进竞技场，
/// 正文那层的 onTap 会在同一次点击里再触发一遍，移动端点左右两侧就同时
/// 滚视口和弹 chrome。竞技场里顶部（后加入 Stack 的这层）先入队并胜出，
/// 正文的点击因此不再触发。只声明点击，不声明拖拽，纵向滚动仍由下面的
/// Scrollable 取得；轻滑阈值由 TapGestureRecognizer 的 slop 提供。
class SideTapZone extends StatelessWidget {
  const SideTapZone({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}
