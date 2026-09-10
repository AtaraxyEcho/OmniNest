import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 照片详情/幻灯片信息与分享面板的宿主。
///
/// 宽屏（≥[photoPanelCompactBreakpoint]）保持右侧 320 侧滑栏形态；
/// 紧凑宽度改为底部滑入面板：全宽、上限 0.8 屏高、顶部圆角 24，
/// 支持下拉关闭。面板内容与开合状态由调用方提供。
class PhotoPanelHost extends StatelessWidget {
  const PhotoPanelHost({
    required this.visible,
    required this.onClose,
    required this.child,
    super.key,
  });

  final bool visible;

  /// 关闭面板的回调：点击 scrim 之外，紧凑形态下向下拖动超过阈值时触发。
  final VoidCallback onClose;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < photoPanelCompactBreakpoint) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 240) {
                onClose();
              }
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(240, size.height * 0.8),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    }
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: photoInfoPanelWidth,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(1, 0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// 信息/分享面板宽屏右侧栏宽度（详情页与幻灯片共用）。
const double photoInfoPanelWidth = 320;

/// 面板切换到紧凑底部形态的宽度断点，与详情页 compact 判定一致。
const double photoPanelCompactBreakpoint = 700;

/// 面板容器装饰：宽屏左缘 1px 描边；紧凑形态顶部圆角 24。
BoxDecoration photoPanelContainerDecoration(BuildContext context) {
  if (MediaQuery.sizeOf(context).width < photoPanelCompactBreakpoint) {
    return const BoxDecoration(
      color: Color(0xF00A0A0A),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
    );
  }
  return const BoxDecoration(
    color: Color(0xF00A0A0A),
    border: Border(left: BorderSide(color: Color(0x12FFFFFF))),
  );
}
