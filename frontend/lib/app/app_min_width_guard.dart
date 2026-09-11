import 'package:flutter/material.dart';

/// 桌面形态的最小内容宽度护栏。
///
/// 桌面浏览器缩窗到该宽度以下时，不再进入各模块的窄窗自适配分支
/// （与移动壳层并行的第二套实现），而是固定内容宽度并允许横向滚动；
/// 移动形态（手机浏览器 / 移动应用）与不小于该宽度的桌面形态不受影响。
class DesktopFormMinWidth extends StatelessWidget {
  const DesktopFormMinWidth({
    required this.mobileForm,
    required this.child,
    super.key,
  });

  /// 当前视口是否为移动形态（由调用方按宿主身份判定后传入）。
  final bool mobileForm;

  final Widget child;

  /// 桌面双栏布局的最低内容宽度，与桌面端最小窗口尺寸一致。
  static const double minWidth = 1024;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (mobileForm || constraints.maxWidth >= minWidth) {
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
