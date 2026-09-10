import 'package:flutter/material.dart';

/// 骨架容器：静态占位（禁渐变规范去除扫光动效），子树用 [SkeletonBox] 平铺。
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// 内容骨架中的矩形占位块。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final alpha = Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.10;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}
