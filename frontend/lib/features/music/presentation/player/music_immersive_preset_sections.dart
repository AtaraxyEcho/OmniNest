part of 'music_immersive_preset_editor.dart';

class _VisualEditorSection extends StatelessWidget {
  const _VisualEditorSection({
    required this.palette,
    required this.title,
    required this.children,
  });

  final MusicImmersivePalette palette;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                color: palette.text.withValues(alpha: 0.82),
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualSwitch extends StatelessWidget {
  const _VisualSwitch({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
    this.scopeLabel,
  });

  final MusicImmersivePalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 生效范围徽标文案（桌面/移动端/通用），为空时不渲染徽标。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      enabled: true,
      // 测试与调用方定位开关行的稳定锚点。
      key: ValueKey<String>('visual-switch-$label'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(color: palette.text),
                        ),
                      ),
                      if (scopeLabel != null)
                        MusicVisualScopeBadge(
                          palette: palette,
                          label: scopeLabel!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 方形轨道：几何与 WorkstationToggle 对齐（32×16 + 10×10
                // 方滑块），颜色取面板 glass 色板以融入强制深色窗口。
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 32,
                  height: 16,
                  padding: EdgeInsets.only(
                    top: 2,
                    bottom: 2,
                    left: value ? 18 : 2,
                    right: value ? 2 : 18,
                  ),
                  decoration: BoxDecoration(
                    color:
                        value
                            ? palette.accent.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color:
                          value
                              ? palette.accent
                              : palette.muted.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 10,
                    height: 10,
                    color: value ? palette.text : palette.muted,
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

/// 下拉控件之间的统一间距：与滑杆的纵向留白对齐。
class _VisualControlGap extends StatelessWidget {
  const _VisualControlGap({required this.child, this.scopeLabel});

  final Widget child;

  /// 生效范围徽标文案：渲染在控件上缘右侧，与下拉自带的标签同行对齐。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scopeLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: MusicVisualScopeBadge(
                palette: MusicImmersivePalette.fromColorScheme(
                  Theme.of(context).colorScheme,
                ),
                label: scopeLabel!,
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _VisualSlider extends StatelessWidget {
  const _VisualSlider({
    required this.palette,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.displayAsInteger = false,
    this.valueSuffix = '',
    this.valuePercent = false,
    this.scopeLabel,
  });

  final MusicImmersivePalette palette;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool displayAsInteger;

  /// 数值单位后缀（如 ` px`、`×`、`%`）。
  final String valueSuffix;

  /// 按百分比显示（0–1 的设置值 × 100）。
  final bool valuePercent;
  final ValueChanged<double> onChanged;

  /// 生效范围徽标文案（桌面/移动端/通用），为空时不渲染徽标。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    final scaled = valuePercent ? value * 100 : value;
    final number =
        displayAsInteger
            ? scaled.round().toString()
            : scaled.toStringAsFixed(2);
    // 百分比自带 % 单位，调用方无需重复传后缀。
    final suffix = valuePercent ? '%$valueSuffix' : valueSuffix;
    final display = '$number$suffix';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: palette.text)),
              ),
              if (scopeLabel != null) ...[
                const SizedBox(width: 6),
                MusicVisualScopeBadge(palette: palette, label: scopeLabel!),
              ],
              Text(
                display,
                style: TextStyle(
                  color: palette.text.withValues(alpha: 0.86),
                  fontSize: AppTypography.bodySmall,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          AppSlider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            semanticLabel: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
