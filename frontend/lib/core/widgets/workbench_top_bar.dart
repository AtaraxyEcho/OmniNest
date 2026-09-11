import 'package:flutter/material.dart';

/// 工作台顶部工具栏，使用不透明主题表面并处理系统安全区域。
class WorkbenchTopBar extends StatelessWidget {
  const WorkbenchTopBar({
    required this.child,
    this.height = 56,
    this.surfaceColor,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final double height;
  final Color? surfaceColor;
  final Color? borderColor;

  /// 返回顶部安全区域和工具栏内容的合计高度。
  static double totalHeightOf(BuildContext context, {double height = 56}) {
    return MediaQuery.paddingOf(context).top + height;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 装饰铺满含状态栏，SafeArea 只避让工具栏内容。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor ?? scheme.surface,
        border: Border(
          bottom: BorderSide(color: borderColor ?? scheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(height: height, child: child),
      ),
    );
  }
}
