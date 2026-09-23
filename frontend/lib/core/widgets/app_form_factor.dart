import 'package:flutter/widgets.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 页面内容画布的形态。
enum OmniCanvasForm {
  /// 触屏画布：使用窄布局，内容需自限宽度。
  touchCanvas,

  /// 桌面画布：允许左侧导航 + 顶部工具栏的宽布局。
  desktopRail,
}

/// 判定当前内容画布应使用触屏布局还是桌面布局。
///
/// `maxWidth` 必须是内容实际可用宽度：在 LayoutBuilder 内传
/// `constraints.maxWidth`。`hosted` 取 `MobileShellScope.isHosted`，托管
/// 平板会被 `_HostedTouchCanvas` 一类限宽容器收窄画布，读 `MediaQuery` 的
/// 屏幕宽会与该容器结论相反。
///
/// `/activity`、`/admin`、`/profile` 等顶层路由由根 Navigator 承载，不在
/// 壳层子树内，此时 `hosted` 恒为 false，只能靠宽度落到触屏形态。
///
/// 画布形态与「是否为手机」是两件事：入口可见性应按
/// [ResponsiveBreakpoints.mobile] 判定，不得用本函数结果代替，否则托管平板
/// 会被误判为不可用。
OmniCanvasForm resolveOmniCanvasForm({
  required double maxWidth,
  required bool hosted,
}) {
  if (hosted) {
    return OmniCanvasForm.touchCanvas;
  }
  return maxWidth >= ResponsiveBreakpoints.workbenchRail
      ? OmniCanvasForm.desktopRail
      : OmniCanvasForm.touchCanvas;
}

/// 在 LayoutBuilder 的 builder 内判定当前画布形态。
OmniCanvasForm omniCanvasFormOf(
  BuildContext context,
  BoxConstraints constraints,
) {
  return resolveOmniCanvasForm(
    maxWidth: constraints.maxWidth,
    hosted: MobileShellScope.isHosted(context),
  );
}
