part of 'desktop_places_globe.dart';

/// 地球缩放胶囊控件：从地球主文件拆出，保持可读长度。
class _GlobeZoomCapsule extends StatelessWidget {
  const _GlobeZoomCapsule({
    required this.zoom,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
    required this.resetTooltip,
  });

  final double zoom;
  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;
  final String resetTooltip;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter.grouped(
        filterConfig: ImageFilterConfig(
          ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        ),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: skin.pop.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: skin.line2),
            boxShadow: skin.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomCapsuleButton(
                enabled: canZoomOut,
                onTap: onZoomOut,
                child: Icon(DesktopIcons.minimize, size: 14, color: skin.text),
              ),
              Tooltip(
                message: resetTooltip,
                child: _ZoomCapsuleButton(
                  enabled: true,
                  horizontalPadding: 8,
                  onTap: onReset,
                  child: Text(
                    '${zoom.toStringAsFixed(1)}×',
                    style: DesktopType.caption(skin.text).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              _ZoomCapsuleButton(
                enabled: canZoomIn,
                onTap: onZoomIn,
                child: Icon(DesktopIcons.plus, size: 14, color: skin.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomCapsuleButton extends StatelessWidget {
  const _ZoomCapsuleButton({
    required this.enabled,
    required this.onTap,
    required this.child,
    this.horizontalPadding = 6,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          alwaysIncludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 4,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
