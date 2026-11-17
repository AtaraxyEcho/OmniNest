import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 桌面形态的最小内容宽度护栏。
///
/// 桌面浏览器缩窗到该宽度以下时，不再进入各模块的窄窗自适配分支
/// （与移动壳层并行的第二套实现），而是固定内容宽度并允许横向滚动；
/// 移动形态（手机浏览器 / 移动应用）与不小于该宽度的桌面形态不受影响。
///
/// 无 hover 指针的设备（触屏笔电、平板桌面模式）不适用：它们无法靠悬停
/// 补偿挤掉的控件，改由各模块的窄屏分支承接（模块在非托管窄宽下自带底部
/// 导航，见 `file_browser_page.dart` 的 `isWide || hosted` 判定）。
class DesktopFormMinWidth extends StatelessWidget {
  const DesktopFormMinWidth({
    required this.mobileForm,
    required this.hoverCapable,
    required this.child,
    super.key,
  });

  /// 当前视口是否为移动形态（由调用方按宿主身份判定后传入）。
  final bool mobileForm;

  /// 是否存在可产生 hover 事件的指针；false 时护栏放行窄宽触屏布局。
  final bool hoverCapable;

  final Widget child;

  /// 桌面双栏布局的最低内容宽度，与 [ResponsiveBreakpoints.workbenchRail]
  /// 同源，也是桌面端最小窗口尺寸。
  static const double minWidth = ResponsiveBreakpoints.workbenchRail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (mobileForm || !hoverCapable || constraints.maxWidth >= minWidth) {
          return child;
        }
        final mediaQuery = MediaQuery.of(context);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            height: constraints.maxHeight,
            child: MediaQuery(
              data: mediaQuery.copyWith(
                size: Size(minWidth, constraints.maxHeight),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
