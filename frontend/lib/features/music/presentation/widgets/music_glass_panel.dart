import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';

/// Music 动态背景上的局部半透明面板。
class MusicGlassPanel extends StatelessWidget {
  const MusicGlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 8,
    this.opacity = 0.88,
    this.blur = 12,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double opacity;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final light = Theme.of(context).brightness == Brightness.light;
    final requestedOpacity = light && opacity > 0.48 ? 0.48 : opacity;
    final effectiveOpacity =
        requestedOpacity < colors.surfaceContainer.a
            ? requestedOpacity
            : colors.surfaceContainer.a;
    final requestedOutlineAlpha = light ? 0.68 : 1.0;
    final outlineAlpha =
        requestedOutlineAlpha < colors.outline.a
            ? requestedOutlineAlpha
            : colors.outline.a;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: colors.surfaceContainer.withValues(alpha: effectiveOpacity),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(
              color: colors.outline.withValues(alpha: outlineAlpha),
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
