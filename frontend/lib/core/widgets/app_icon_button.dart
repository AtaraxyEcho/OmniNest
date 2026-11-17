import 'package:flutter/material.dart';

/// 强制提供 tooltip 的图标按钮，满足可访问性对图标操作的语义标注要求。
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.iconSize,
    this.style,
    super.key,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double? iconSize;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      color: color,
      iconSize: iconSize,
      style: style,
    );
  }
}
