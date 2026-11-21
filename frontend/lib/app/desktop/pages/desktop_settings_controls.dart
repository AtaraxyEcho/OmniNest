part of 'desktop_settings_page.dart';

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DesktopAccent accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: DesktopFocusOutline(
        radius: 14,
        onActivate: onTap,
        child: DesktopHover(
          builder:
              (context, hovered) => GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.fast),
                  curve: DesktopMotion.ease,
                  transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? skin.raise2
                            : hovered
                            ? skin.raise
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          selected
                              ? skin.line2
                              : hovered
                              ? skin.line
                              : Colors.transparent,
                      width: DesktopMetrics.hairlineStrong,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.12 : 1.0,
                        duration: DesktopMotion.of(context, DesktopMotion.fast),
                        curve: DesktopMotion.ease,
                        child: AnimatedContainer(
                          duration: DesktopMotion.of(
                            context,
                            DesktopMotion.fast,
                          ),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: skin.isDark ? accent.dark : accent.light,
                            shape: BoxShape.circle,
                            boxShadow:
                                selected
                                    ? [
                                      BoxShadow(
                                        color: skin.bg,
                                        blurRadius: 0,
                                        spreadRadius: 3,
                                      ),
                                      BoxShadow(
                                        color: skin.text2,
                                        blurRadius: 0,
                                        spreadRadius: 5,
                                      ),
                                    ]
                                    : null,
                          ),
                          alignment: Alignment.center,
                          child:
                              selected
                                  ? Icon(
                                    DesktopIcons.check,
                                    size: 13,
                                    color: skin.accentInk,
                                  )
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: DesktopType.caption(
                          selected ? skin.text : skin.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
