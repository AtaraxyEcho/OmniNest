import 'package:flutter/material.dart';

/// 通用浮动操作按钮，用于移动端快速操作入口。
///
/// 使用 surfaceContainer 作为背景、onSurface 作为前景，
/// 确保在深色/浅色主题下均有足够对比度。
class OmniFab extends StatelessWidget {
  const OmniFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: colorScheme.surfaceContainerHigh,
      foregroundColor: colorScheme.onSurface,
      elevation: 2,
      child: Icon(icon),
    );
  }
}
