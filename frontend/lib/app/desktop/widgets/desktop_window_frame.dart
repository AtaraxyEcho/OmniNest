import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';

/// 无边框窗口的边缘缩放带。
///
/// 窗口去掉 WS_THICKFRAME 后系统不再提供缩放边框；而客户区被 Flutter
/// 子窗口铺满，原生 WM_NCHITTEST 也收不到（消息先被子窗口吃掉）。所以
/// 缩放由界面在最外圈铺一圈 5px 的命中带，按下就交给原生去跑缩放循环。
///
/// 只覆盖最外圈，不参与页面布局：内容仍在下面正常滚动与点击。
class DesktopWindowFrame extends ConsumerWidget {
  const DesktopWindowFrame({required this.child, super.key});

  final Widget child;

  static const double _edge = 5;
  static const double _corner = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopPlatform) {
      return child;
    }
    final controller = ref.read(windowChromeControllerProvider.notifier);
    // 最大化/全屏时窗口没有可缩放的边：继续留着命中带会让鼠标移到四边
    // 变成双箭头，点一下还会把窗口从最大化状态拖出来。命中带结构保留
    // （八条 MouseRegion 仍铺着），只在不再可缩放时整体让位。
    final disableResize = ref.watch(
      windowChromeControllerProvider.select(
        (state) => state.isMaximized || state.isFullscreen,
      ),
    );

    Widget grip(
      WindowResizeEdge edge,
      MouseCursor cursor, {
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) {
      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        // 按下即进入缩放：原生边框也是 mousedown 就开始，等手势滑动
        // 识别（18px 滑动阈值）会让 5px 的边上"按下去没反应"。
        child: IgnorePointer(
          ignoring: disableResize,
          child: MouseRegion(
            cursor: cursor,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => controller.startResizing(edge),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        grip(
          WindowResizeEdge.top,
          SystemMouseCursors.resizeUpDown,
          left: _corner,
          right: _corner,
          top: 0,
          height: _edge,
        ),
        grip(
          WindowResizeEdge.bottom,
          SystemMouseCursors.resizeUpDown,
          left: _corner,
          right: _corner,
          bottom: 0,
          height: _edge,
        ),
        grip(
          WindowResizeEdge.left,
          SystemMouseCursors.resizeLeftRight,
          left: 0,
          top: _corner,
          bottom: _corner,
          width: _edge,
        ),
        grip(
          WindowResizeEdge.right,
          SystemMouseCursors.resizeLeftRight,
          right: 0,
          top: _corner,
          bottom: _corner,
          width: _edge,
        ),
        grip(
          WindowResizeEdge.topLeft,
          SystemMouseCursors.resizeUpLeftDownRight,
          left: 0,
          top: 0,
          width: _corner,
          height: _corner,
        ),
        // 右上角与关闭键（46×46，right:0 / top:0）重叠：14px 见方的角块会
        // 把关闭键右上那片热区整个吞掉，鼠标甩到角落点关闭既不亮红底也
        // 点不中。这里只保留 5px 的贴边高度，缩放手感损失可以忽略。
        grip(
          WindowResizeEdge.topRight,
          SystemMouseCursors.resizeUpRightDownLeft,
          right: 0,
          top: 0,
          width: _corner,
          height: _edge,
        ),
        grip(
          WindowResizeEdge.bottomLeft,
          SystemMouseCursors.resizeUpRightDownLeft,
          left: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
        ),
        grip(
          WindowResizeEdge.bottomRight,
          SystemMouseCursors.resizeUpLeftDownRight,
          right: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
        ),
      ],
    );
  }
}
