import 'package:flutter/material.dart';

/// Portal 动态背景上使用的半透明固定 Sliver 顶栏。
class PortalGlassSliverAppBar extends StatelessWidget {
  const PortalGlassSliverAppBar({
    required this.title,
    this.actions = const <Widget>[],
    this.surfaceAlpha = 0.78,
    super.key,
  });

  final Widget title;
  final List<Widget> actions;
  final double surfaceAlpha;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface.withValues(alpha: surfaceAlpha),
      surfaceTintColor: Colors.transparent,
      title: title,
      actions: <Widget>[...actions, const SizedBox(width: 8)],
    );
  }
}
