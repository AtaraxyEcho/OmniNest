part of 'desktop_command_palette.dart';

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.scope,
    required this.labelOf,
    required this.onChanged,
  });

  final DesktopPaletteScope scope;
  final String Function(DesktopPaletteScope) labelOf;
  final ValueChanged<DesktopPaletteScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Semantics(
          // 样例 `Shell.tsx:381`：scope 行是 tablist，每颗是带 aria-selected
          // 的 tab，读屏才知道这是一组互斥筛选。
          container: true,
          explicitChildNodes: true,
          child: Row(
            children: [
              for (final value in DesktopPaletteScope.values)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Semantics(
                    button: true,
                    selected: value == scope,
                    inMutuallyExclusiveGroup: true,
                    child: DesktopHover(
                      builder:
                          (context, hovered) => GestureDetector(
                            onTap: () => onChanged(value),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    value == scope
                                        ? skin.accent
                                        : hovered
                                        ? skin.raise
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  DesktopMetrics.radiusPill,
                                ),
                              ),
                              child: Text(
                                labelOf(value),
                                style: DesktopType.caption(
                                  value == scope ? skin.accentInk : skin.text2,
                                ).copyWith(
                                  fontWeight:
                                      value == scope
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
