import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// Portal 动态背景上的局部半透明卡片。
class PortalGlassCard extends StatelessWidget {
  const PortalGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 8,
    this.surfaceAlpha = 0.78,
    this.shadow = true,
    this.backgroundColor,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double surfaceAlpha;
  final bool shadow;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = backgroundColor ?? scheme.surfaceContainer;
    final outline = borderColor ?? scheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow:
            shadow
                ? <BoxShadow>[
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
                : const <BoxShadow>[],
      ),
      child: Material(
        color: background.withValues(alpha: background.a * surfaceAlpha),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: outline.withValues(alpha: outline.a * 0.72)),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Portal 移动端动态背景导航栏。
class PortalGlassDock extends StatelessWidget {
  const PortalGlassDock({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final List<PortalGlassDockItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light;
    final smoke = light && scheme.surface.a == 0;
    final surface =
        smoke
            ? scheme.surfaceContainerLow
            : Color.lerp(
              light ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
              light ? scheme.primaryContainer : scheme.secondaryContainer,
              light ? 0.10 : 0.05,
            )!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: smoke ? surface : surface.withValues(alpha: light ? 0.74 : 0.80),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color:
                smoke
                    ? scheme.outlineVariant
                    : (light ? scheme.onSurface : scheme.outlineVariant)
                        .withValues(alpha: light ? 0.14 : 0.72),
          ),
        ),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List<Widget>.generate(items.length, (index) {
              final item = items[index];
              return _PortalGlassDockButton(
                icon: index == currentIndex ? item.selectedIcon : item.icon,
                label: item.label,
                selected: index == currentIndex,
                onTap: () => onTap(index),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Portal 导航项数据。
class PortalGlassDockItem {
  const PortalGlassDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _PortalGlassDockButton extends StatefulWidget {
  const _PortalGlassDockButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PortalGlassDockButton> createState() => _PortalGlassDockButtonState();
}

class _PortalGlassDockButtonState extends State<_PortalGlassDockButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        widget.selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1,
          duration: MotionToken.resolve(context, MotionToken.fast),
          curve: MotionToken.curve,
          child: SizedBox(
            width: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(widget.icon, size: 20, color: foreground),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
