import 'package:flutter/material.dart';

/// 为桌面滚动视口提供平台兼容行为。
class OmniNestScrollBehavior extends MaterialScrollBehavior {
  const OmniNestScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final scrollable = super.buildScrollbar(context, child, details);
    if (getPlatform(context) != TargetPlatform.windows) {
      return scrollable;
    }
    // Windows AXTree 当前无法稳定处理滚动视口中的 Tooltip 浮层迁移。
    return TooltipVisibility(visible: false, child: scrollable);
  }
}
