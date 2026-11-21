import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/feature/photos_chrome_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 照片详情/幻灯片信息与分享面板的宿主。
///
/// 宽屏（≥[photoPanelCompactBreakpoint]）以指定宽度保持右侧侧滑栏形态；
/// 紧凑宽度改为底部滑入面板：全宽、上限 0.8 屏高、顶部圆角 24，
/// 支持下拉关闭。面板内容与开合状态由调用方提供。
class PhotoPanelHost extends StatelessWidget {
  const PhotoPanelHost({
    required this.visible,
    required this.onClose,
    required this.child,
    this.width = photoInfoPanelWidth,
    this.desktopStyle = false,
    super.key,
  });

  final bool visible;

  /// 关闭面板的回调：点击 scrim 之外，紧凑形态下向下拖动超过阈值时触发。
  final VoidCallback onClose;

  final Widget child;
  final double width;
  final bool desktopStyle;

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
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 320),
          ),
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
              // 底部安全区由面板装饰内侧的 SafeArea 处理，避免手势区空白。
              child: child,
            ),
          ),
        ),
      );
    }
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: width,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(1, 0),
        duration:
            desktopStyle
                ? DesktopMotion.of(context, DesktopMotion.drawer)
                : MotionToken.normal,
        curve: desktopStyle ? DesktopMotion.drawerCurve : Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// 信息面板宽度；分享抽屉另按原型使用 [photoSharePanelWidth]。
const double photoInfoPanelWidth = 320;

/// `polish.css` 桌面抽屉的参考宽度。
const double photoSharePanelWidth = 330;

/// 面板切换到紧凑底部形态的宽度断点，与详情页 compact 判定一致。
const double photoPanelCompactBreakpoint = 700;

/// 面板容器装饰按桌面主题或移动 Photos 原有样式分支，避免跨端串色。
BoxDecoration photoPanelContainerDecoration(
  BuildContext context, {
  bool desktopStyle = false,
}) {
  final compact =
      MediaQuery.sizeOf(context).width < photoPanelCompactBreakpoint;
  if (compact && !desktopStyle) {
    return const BoxDecoration(
      color: PhotosChromeColors.panelFill,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      border: Border(top: BorderSide(color: PhotosChromeColors.white12)),
    );
  }
  if (desktopStyle) {
    final skin = DesktopSkin.of(context);
    if (compact) {
      return BoxDecoration(
        color: skin.panelSolid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: skin.line2)),
        boxShadow: const [
          BoxShadow(
            color: DesktopPalette.drawerShadow,
            blurRadius: 70,
            offset: Offset(0, -20),
            spreadRadius: -20,
          ),
        ],
      );
    }
    return BoxDecoration(
      color: skin.panelSolid,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
      border: Border(left: BorderSide(color: skin.line2)),
      boxShadow: const [
        BoxShadow(
          color: DesktopPalette.drawerShadow,
          blurRadius: 70,
          offset: Offset(-30, 0),
          spreadRadius: -20,
        ),
      ],
    );
  }
  return const BoxDecoration(
    color: PhotosChromeColors.panelFill,
    border: Border(left: BorderSide(color: PhotosChromeColors.white12)),
  );
}
