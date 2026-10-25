part of 'reader_view_settings.dart';

class _SettingSection extends StatelessWidget {
  const _SettingSection({
    required this.settings,
    required this.child,
    this.label,
    this.value,
    this.hint,
    this.first = false,
  });

  final ReaderViewSettings settings;
  final Widget child;
  final String? label;
  final String? value;

  /// 段名之下的一行作用域说明：只给"名字比实际作用域宽"的项用。
  final String? hint;

  /// 稿子 `.setting-section:first-of-type { border-top: 0 }`。
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:
          first
              ? null
              : BoxDecoration(
                border: Border(top: BorderSide(color: settings.lineColor)),
              ),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: EdgeInsets.only(bottom: hint == null ? 11 : 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label!,
                      style: TextStyle(
                        color: settings.onSurfaceColor,
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (value != null)
                    Text(
                      value!,
                      style: TextStyle(
                        color: settings.accentColor,
                        fontSize: AppTypography.labelMicro,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text(
                hint!,
                style: TextStyle(
                  color: settings.onSurfaceVariantColor,
                  fontSize: AppTypography.labelMicro,
                  height: 1.35,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 稿子 `.segmented`：3 内边距、3 间隙、r13 槽底（墨色 6%）；
/// 选项 38 高、r10、10px，选中面换成纸面并加 0 3 10 投影。
/// `.setting-grid .segmented button` 再收一档：padding 0 5、9px。
class _SampleSegmented extends StatelessWidget {
  const _SampleSegmented({
    required this.settings,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.dense = false,
  });

  final ReaderViewSettings settings;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: settings.onSurfaceColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: _SegmentOption(
                label: labels[i],
                selected: i == selectedIndex,
                settings: settings,
                dense: dense,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    required this.label,
    required this.selected,
    required this.settings,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final ReaderViewSettings settings;
  final VoidCallback onTap;

  /// 稿子 `.setting-grid .segmented button`：格子挤，字号与横向 padding 各降一档。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 38),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 8),
          decoration: BoxDecoration(
            color: selected ? settings.elevatedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow:
                selected
                    ? [
                      BoxShadow(
                        color: settings.shadowColor.withValues(alpha: 0.48),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                    : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  selected
                      ? settings.onSurfaceColor
                      : settings.onSurfaceVariantColor,
              fontSize:
                  dense ? AppTypography.labelNano : AppTypography.labelMicro,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 稿子 `.range-control`：`32px 1fr 32px` 三列，两端是 13px 与 21px 衬线的大 A，
/// 中间滑杆取强调色；字号档位 16..26，默认 19。
class _FontSizeRange extends StatelessWidget {
  const _FontSizeRange({
    required this.settings,
    required this.value,
    required this.onChanged,
  });

  final ReaderViewSettings settings;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // 存档允许 12..32，稿子滑杆只有 16..26：越界的历史值按端点显示，
    // 用户一动滑杆就回到稿子档位。
    final clamped = value.clamp(16.0, 26.0);
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            'A',
            textAlign: TextAlign.center,
            style: TextStyle(
              // 稿子 `.range-control > span` 两端都是衬线，只是 13 与 21 两档。
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              color: settings.onSurfaceVariantColor,
              fontSize: AppTypography.bodyMedium,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: settings.accentColor,
              inactiveTrackColor: settings.onSurfaceColor.withValues(
                alpha: 0.12,
              ),
              thumbColor: settings.accentColor,
              overlayColor: settings.accentColor.withValues(alpha: 0.18),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: AppSlider(
              value: clamped,
              min: 16,
              max: 26,
              divisions: 10,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            'A',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              color: settings.onSurfaceColor,
              // 稿子 `.range-control strong` 就是 21px 衬线大 A。
              fontSize: 21, // ignore: font_size_whitelist
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// 稿子 `.setting-grid`：字体占 0.82 份、行距占 1.18 份并排，间隙 12，
/// 各自的标签高 17。行距是三档分段（1.6 / 1.85 / 2.1）。
class _FontAndLineHeightGrid extends StatelessWidget {
  const _FontAndLineHeightGrid({
    required this.settings,
    required this.onSettingsChanged,
  });

  final ReaderViewSettings settings;
  final ValueChanged<ReaderViewSettings> onSettingsChanged;

  static const List<double> _lineHeights = <double>[1.6, 1.85, 2.1];
  static const List<String> _familyValues = <String>['serif', 'sans', 'system'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 存档里可能是三档之外的旧值（例如 1.7）：按最近的一档显示选中，
    // 点选即归到稿子档位。
    var nearest = 0;
    for (var i = 1; i < _lineHeights.length; i++) {
      if ((settings.lineHeight - _lineHeights[i]).abs() <
          (settings.lineHeight - _lineHeights[nearest]).abs()) {
        nearest = i;
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 82,
          child: _GridField(
            settings: settings,
            label: l10n.readerFontFamily,
            child: _SampleSegmented(
              settings: settings,
              dense: true,
              labels: [
                l10n.readerFontSerif,
                l10n.readerFontSans,
                l10n.readerFontSystem,
              ],
              selectedIndex: _familyValues.indexOf(settings.fontFamily),
              onChanged:
                  (index) => onSettingsChanged(
                    settings.copyWith(fontFamily: _familyValues[index]),
                  ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 118,
          child: _GridField(
            settings: settings,
            label: l10n.readerLineHeight,
            child: _SampleSegmented(
              settings: settings,
              dense: true,
              labels: const ['1.6', '1.85', '2.1'],
              selectedIndex: nearest,
              onChanged:
                  (index) => onSettingsChanged(
                    settings.copyWith(lineHeight: _lineHeights[index]),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridField extends StatelessWidget {
  const _GridField({
    required this.settings,
    required this.label,
    required this.child,
  });

  final ReaderViewSettings settings;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 17,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: settings.onSurfaceColor,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 11),
        child,
      ],
    );
  }
}

/// 稿子 `.theme-dot`：色板占满等分格、48 高、r13、1px --line；选中换成 2px
/// 强调色描边并外加 3px 强调软底光环，格内一枚 16 的勾，标签 9px。
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.localizedName,
    required this.selected,
    required this.labelColor,
    required this.onTap,
  });

  final ReaderReadingPalette theme;
  final String localizedName;
  final bool selected;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: localizedName,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 48,
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  // 稿子 `.theme-dot > span` 未选中用该档自己的 --line 描边，
                  // 色板是预览另一档纸面，不能借当前档的线色。
                  color: selected ? theme.accent : theme.line,
                  width: selected ? 2 : 1,
                ),
                boxShadow:
                    selected
                        ? [BoxShadow(color: theme.accentSoft, spreadRadius: 3)]
                        : null,
              ),
              child:
                  selected
                      ? Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: theme.accent,
                          size: 16,
                        ),
                      )
                      : null,
            ),
            const SizedBox(height: 6),
            Text(
              localizedName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: labelColor,
                fontSize: AppTypography.labelNano,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
