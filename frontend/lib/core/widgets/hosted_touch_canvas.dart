import 'package:flutter/widgets.dart';

/// 托管态触屏内容画布：窄屏无感铺满，宽画布下按给定上限封顶居中。
///
/// 封顶时同步把 [MediaQueryData.size] 改写为画布宽度，使子树内
/// `MediaQuery.sizeOf(context).width` 与 `LayoutBuilder` 的约束宽一致；
/// 否则平板托管态会出现「屏幕宽判桌面、画布宽只有上限」的相反结论。
///
/// 与 `DesktopFormMinWidth` 同属一类护栏：两者都用覆写 MediaQuery 的方式
/// 让宽度判定与真实可用画布保持单一口径。
class HostedTouchCanvas extends StatelessWidget {
  const HostedTouchCanvas({
    required this.hosted,
    required this.maxContentWidth,
    required this.child,
    super.key,
  });

  /// 是否由应用级移动壳层承载；非托管时直接铺满子树，不介入宽度。
  final bool hosted;

  /// 触屏内容的最大宽度，与壳层 chrome 限宽同源。
  final double maxContentWidth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hosted) {
      return child;
    }
    // 分支只随 hosted 变化，不随宽度增删节点，避免旋转或缩放时子树重挂载。
    final mediaQuery = MediaQuery.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: maxContentWidth),
        child: MediaQuery(
          data: mediaQuery.copyWith(
            size: Size(maxContentWidth, mediaQuery.size.height),
          ),
          child: child,
        ),
      ),
    );
  }
}
