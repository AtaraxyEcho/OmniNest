part of 'reader_view_settings.dart';

/// 阅读设置面板与开关控件（从 ReaderViewSettings 模型文件拆出）。
class ReaderViewSettingsPanel extends StatelessWidget {
  const ReaderViewSettingsPanel({
    required this.settings,
    required this.onSettingsChanged,
    this.pageModeEnabled,
    this.mobile = false,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    super.key,
  });

  final ReaderViewSettings settings;
  final ValueChanged<ReaderViewSettings> onSettingsChanged;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  /// 是否提供翻页模式；null 时跟随 [supportsPageMode]（Web 恒 false）。
  final bool? pageModeEnabled;

  /// 移动壳层：开关换成样例 .env-switch 胶囊，整行作为点按目标。
  /// 工位皮肤保持直角开关，两种形态不共用一套几何。
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final colors = ReaderPanelColors.resolve(context, settings.palette);
    final showPageMode = pageModeEnabled ?? supportsPageMode;
    final showPageTurn =
        !colors.isDarkGlass && showPageMode && settings.readingMode == 'page';
    final l10n = AppLocalizations.of(context);
    if (colors.isDarkGlass) {
      return _buildDesktopSettingsBody(context, l10n, colors, showPageMode);
    }
    // 稿子 `.sheet-appearance` 的分区顺序与分隔：阅读方式 → 字号 → 字体+行距 →
    // 阅读背景，每段 `.setting-section` 上沿一条 --line 发丝线，首段不画。
    // 音量键翻页是本产品特有开关（稿子没有键盘控件），排在最后同一段式。
    // 点按正文控制 chrome 显隐；全屏入口只在桌面抽屉底部（F11 同一动作）。
    final sections = <Widget>[
      if (showPageMode)
        _SettingSection(
          settings: settings,
          first: true,
          label: l10n.readerReadingMode,
          value:
              settings.readingMode == 'scroll'
                  ? l10n.readerModeScroll
                  : l10n.readerModePage,
          child: _SampleSegmented(
            settings: settings,
            labels: [l10n.readerModeScroll, l10n.readerModePage],
            selectedIndex: settings.readingMode == 'scroll' ? 0 : 1,
            onChanged:
                (index) => onSettingsChanged(
                  settings.copyWith(
                    readingMode: index == 0 ? 'scroll' : 'page',
                  ),
                ),
          ),
        ),
      if (showPageTurn)
        _SettingSection(
          settings: settings,
          first: !showPageMode,
          label: l10n.readerPageTransition,
          child: _SampleSegmented(
            settings: settings,
            labels: [
              l10n.readerTransitionSlide,
              l10n.readerTransitionCover,
              l10n.readerTransitionFade,
            ],
            selectedIndex: const [
              'slide',
              'cover',
              'fade',
            ].indexOf(settings.pageTurnMode),
            onChanged:
                (index) => onSettingsChanged(
                  settings.copyWith(
                    pageTurnMode: const ['slide', 'cover', 'fade'][index],
                  ),
                ),
          ),
        ),
      _SettingSection(
        settings: settings,
        label: l10n.readerFontSize,
        value: '${settings.fontSize.round()}px',
        child: _FontSizeRange(
          settings: settings,
          value: settings.fontSize,
          onChanged: (v) => onSettingsChanged(settings.copyWith(fontSize: v)),
        ),
      ),
      _SettingSection(
        settings: settings,
        // 稿子把字体与行距并排放在 `.setting-grid`（0.82fr / 1.18fr，间隙 12）。
        child: _FontAndLineHeightGrid(
          settings: settings,
          onSettingsChanged: onSettingsChanged,
        ),
      ),
      _buildThemeSection(context, l10n),
      _SettingSection(
        settings: settings,
        label: l10n.readerBrightness,
        value: '${settings.brightness}%',
        child: AppSlider(
          value: settings.brightness.toDouble(),
          min: 30,
          max: 100,
          divisions: 70,
          onChanged:
              (v) =>
                  onSettingsChanged(settings.copyWith(brightness: v.round())),
        ),
      ),
      _SettingSection(
        settings: settings,
        label: l10n.readerWarmth,
        value: '${settings.warmth}%',
        child: AppSlider(
          value: settings.warmth.toDouble(),
          min: 0,
          max: 60,
          divisions: 60,
          onChanged:
              (v) => onSettingsChanged(settings.copyWith(warmth: v.round())),
        ),
      ),
      _SettingSection(
        settings: settings,
        label: l10n.readerAutoNight,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            l10n.readerAutoNightHint,
            style: TextStyle(
              color: settings.onSurfaceVariantColor,
              fontSize: AppTypography.labelSmall,
            ),
          ),
          value: settings.autoNight,
          onChanged: (v) => onSettingsChanged(settings.copyWith(autoNight: v)),
        ),
      ),
      _SettingSection(
        settings: settings,
        label: l10n.readerJustifyLabel,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            l10n.readerJustifyHint,
            style: TextStyle(
              color: settings.onSurfaceVariantColor,
              fontSize: AppTypography.labelSmall,
            ),
          ),
          value: settings.justify,
          onChanged: (v) => onSettingsChanged(settings.copyWith(justify: v)),
        ),
      ),
      _SettingSection(
        settings: settings,
        label: l10n.readerMarginLabel,
        child: _SampleSegmented(
          settings: settings,
          labels: [
            l10n.readerMarginNarrow,
            l10n.readerMarginStandard,
            l10n.readerMarginWide,
          ],
          selectedIndex: const [
            'narrow',
            'standard',
            'wide',
          ].indexOf(settings.marginPreset),
          onChanged:
              (index) => onSettingsChanged(
                settings.copyWith(
                  marginPreset: const ['narrow', 'standard', 'wide'][index],
                ),
              ),
        ),
      ),
      _SettingSection(
        settings: settings,
        label: l10n.readerFollowBookTypesetting,
        // 开关名比它的实际作用域宽（只管缩进·段距·对齐，字号字体行距恒归读者），
        // 说明放在段名下而不是开关行里：移动态整行 excludeSemantics，
        // 挂在行内会被读屏吞掉，作为段的兄弟节点才念得到。
        hint: l10n.readerFollowBookTypesettingHint,
        child: _buildFollowBookTypesettingRow(context, l10n),
      ),
      if (PlatformCapabilities.current().supportsVolumeKeyPageTurn)
        _SettingSection(
          settings: settings,
          label: l10n.readerVolumeKeyPaging,
          child: _buildVolumeKeyPagingRow(context, l10n),
        ),
    ];
    // 稿子 `.sheet-appearance`：段与段自带发丝线，尾部留 safe-bottom + 14。
    // 抽屉外壳由 ReaderAdaptivePanelFrame 画，这里只交滚动本体。
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  /// 桌面端紧凑水平行 `.bt-row`（对齐样例 ReaderView.tsx:346-364）。
  Widget _buildDesktopSettingsBody(
    BuildContext context,
    AppLocalizations l10n,
    ReaderPanelColors colors,
    bool showPageMode,
  ) {
    final currentModeIndex =
        settings.readingMode == 'scroll'
            ? 2
            : settings.pageTurnMode == 'slide'
            ? 1
            : 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingSection(
            settings: settings,
            first: true,
            label: l10n.readerTheme,
            child: Row(
              children: List.generate(ReaderReadingPalette.values.length, (i) {
                final theme = ReaderReadingPalette.values[i];
                final selected = settings.themeIndex == i;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 3 ? 0 : 10),
                    child: _ThemeOption(
                      theme: theme,
                      localizedName: _themeName(l10n, i),
                      selected: selected,
                      labelColor:
                          selected ? colors.accent : colors.onSurfaceVariant,
                      onTap:
                          () => onSettingsChanged(
                            settings.copyWith(themeIndex: i),
                          ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (showPageMode)
            _DesktopSettingRow(
              colors: colors,
              label: l10n.readerReadingMode,
              control: SizedBox(
                width: 210,
                child: _SampleSegmented(
                  settings: settings,
                  labels: [
                    l10n.readerModeBook,
                    l10n.readerModeSwipe,
                    l10n.readerModeScroll,
                  ],
                  selectedIndex: currentModeIndex,
                  onChanged: (i) {
                    if (i == 2) {
                      onSettingsChanged(
                        settings.copyWith(readingMode: 'scroll'),
                      );
                    } else {
                      onSettingsChanged(
                        settings.copyWith(
                          readingMode: 'page',
                          pageTurnMode: i == 0 ? 'cover' : 'slide',
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerBrightness,
            control: _DesktopSliderControl(
              colors: colors,
              value: settings.brightness.toDouble(),
              min: 30,
              max: 100,
              divisions: 70,
              label: '${settings.brightness}%',
              onChanged:
                  (v) => onSettingsChanged(
                    settings.copyWith(brightness: v.round()),
                  ),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerWarmth,
            control: _DesktopSliderControl(
              colors: colors,
              value: settings.warmth.toDouble(),
              min: 0,
              max: 60,
              divisions: 60,
              label: '${settings.warmth}%',
              onChanged:
                  (v) =>
                      onSettingsChanged(settings.copyWith(warmth: v.round())),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerAutoNight,
            control: Switch.adaptive(
              value: settings.autoNight,
              activeTrackColor: colors.accent,
              onChanged:
                  (v) => onSettingsChanged(settings.copyWith(autoNight: v)),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerFontFamily,
            control: SizedBox(
              width: 210,
              child: _SampleSegmented(
                settings: settings,
                labels: [
                  l10n.readerFontSerif,
                  l10n.readerFontSans,
                  l10n.readerFontSystem,
                ],
                selectedIndex: const [
                  'serif',
                  'sans',
                  'system',
                ].indexOf(settings.fontFamily).clamp(0, 2),
                onChanged:
                    (i) => onSettingsChanged(
                      settings.copyWith(
                        fontFamily: const ['serif', 'sans', 'system'][i],
                      ),
                    ),
              ),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerFontSize,
            control: _DesktopSliderControl(
              colors: colors,
              value: settings.fontSize.clamp(14.0, 28.0),
              min: 14,
              max: 28,
              divisions: 14,
              label: '${settings.fontSize.round()}',
              onChanged:
                  (v) => onSettingsChanged(settings.copyWith(fontSize: v)),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerLineHeight,
            control: _DesktopSliderControl(
              colors: colors,
              value: settings.lineHeight.clamp(1.3, 2.2),
              min: 1.3,
              max: 2.2,
              divisions: 9,
              label: settings.lineHeight.toStringAsFixed(1),
              onChanged:
                  (v) => onSettingsChanged(
                    settings.copyWith(
                      lineHeight: double.parse(v.toStringAsFixed(1)),
                    ),
                  ),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerJustifyLabel,
            control: Switch.adaptive(
              value: settings.justify,
              activeTrackColor: colors.accent,
              onChanged:
                  (v) => onSettingsChanged(settings.copyWith(justify: v)),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerMarginLabel,
            control: SizedBox(
              width: 190,
              child: _SampleSegmented(
                settings: settings,
                labels: [
                  l10n.readerMarginNarrow,
                  l10n.readerMarginStandard,
                  l10n.readerMarginWide,
                ],
                selectedIndex: const [
                  'narrow',
                  'standard',
                  'wide',
                ].indexOf(settings.marginPreset).clamp(0, 2),
                onChanged:
                    (i) => onSettingsChanged(
                      settings.copyWith(
                        marginPreset: const ['narrow', 'standard', 'wide'][i],
                      ),
                    ),
              ),
            ),
          ),
          _DesktopSettingRow(
            colors: colors,
            label: l10n.readerFollowBookTypesetting,
            control: Switch.adaptive(
              value: settings.followBookTypesetting,
              activeTrackColor: colors.accent,
              onChanged:
                  (v) => onSettingsChanged(
                    settings.copyWith(followBookTypesetting: v),
                  ),
            ),
          ),
          if (onToggleFullscreen != null)
            _DesktopSettingRow(
              colors: colors,
              label: '${l10n.portalImmersiveModeEnter} (F11)',
              control: Switch.adaptive(
                value: isFullscreen,
                activeTrackColor: colors.accent,
                onChanged: (_) => onToggleFullscreen?.call(),
              ),
            ),
        ],
      ),
    );
  }

  static String _themeName(AppLocalizations l10n, int index) {
    return switch (index) {
      0 => l10n.readerThemeLight,
      1 => l10n.readerThemeEyeCare,
      2 => l10n.readerThemeDark,
      _ => l10n.readerThemeGreen,
    };
  }

  Widget _buildThemeSection(BuildContext context, AppLocalizations l10n) {
    // 稿子 `.theme-picker` 没有固定高：色板 48 + 间隙 6 + 9px 档名，四格等高
    // 由结构保证，写死 66 会在档名行高变化时溢出 1px。
    return _SettingSection(
      settings: settings,
      label: l10n.readerTheme,
      child: Row(
        children: List.generate(ReaderReadingPalette.values.length, (i) {
          final theme = ReaderReadingPalette.values[i];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 10),
              child: _ThemeOption(
                theme: theme,
                localizedName: _themeName(l10n, i),
                selected: settings.themeIndex == i,
                // 稿子的档名恒为 --muted，选中只靠描边与光环；这里额外把
                // 当前档名转强调色，是给色弱用户的第二通道（光环是纯亮度差）。
                labelColor:
                    settings.themeIndex == i
                        ? settings.accentColor
                        : settings.onSurfaceVariantColor,
                onTap:
                    () => onSettingsChanged(settings.copyWith(themeIndex: i)),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 跟随原书排版开关：书的样式表与内联 `style` 参与层叠。
  Widget _buildFollowBookTypesettingRow(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return _buildToggleRow(
      context,
      icon: Icons.format_size_rounded,
      label: l10n.readerFollowBookTypesetting,
      value: settings.followBookTypesetting,
      onChanged:
          (v) => onSettingsChanged(settings.copyWith(followBookTypesetting: v)),
    );
  }

  Widget _buildVolumeKeyPagingRow(BuildContext context, AppLocalizations l10n) {
    return _buildToggleRow(
      context,
      icon: Icons.volume_up_rounded,
      label: l10n.readerVolumeKeyPaging,
      value: settings.volumeKeyPaging,
      onChanged:
          (v) => onSettingsChanged(settings.copyWith(volumeKeyPaging: v)),
    );
  }

  /// 开关行：工位保持直角开关；移动壳层换成样例胶囊，并把整行做成点按目标
  /// （胶囊本体 34×20，低于次级控件触控下限）。
  Widget _buildToggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final children = <Widget>[
      Icon(icon, color: settings.onSurfaceVariantColor, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: settings.onSurfaceVariantColor,
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      _buildToggleSwitch(value, onChanged),
    ];
    if (!mobile) {
      return Row(children: children);
    }
    // excludeSemantics：行内胶囊自带 button+toggled 节点，不屏蔽会念两遍。
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(children: children),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, ValueChanged<bool> onChanged) {
    return ReaderToggleSwitch(
      settings: settings,
      mobile: mobile,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 阅读设置里的开关：工位保持直角开关，移动壳层换成样例 .env-switch 胶囊。
///
/// 颜色全部来自阅读调色板（面板底与正文色由用户选的调色板决定），
/// 不跟全局极性表，否则浅色纸面 + 深色环境会配出看不见的旋钮。
class ReaderToggleSwitch extends StatelessWidget {
  const ReaderToggleSwitch({
    required this.settings,
    required this.mobile,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ReaderViewSettings settings;
  final bool mobile;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (!mobile) {
      return WorkstationSwitch(value: value, onChanged: onChanged);
    }
    // 样例 .env-switch：轨道是面板上的墨色低透明档，开=强调色；
    // 旋钮与所在面反相——强调色亮时用画布色，面板亮时用近白 + 投影。
    final lightPanel = settings.controlSurfaceColor.computeLuminance() > 0.5;
    return MobilePillSwitch(
      value: value,
      onChanged: onChanged,
      trackOn: settings.accentColor,
      trackOff: settings.onSurfaceColor.withValues(alpha: 0.16),
      knobOn: settings.surfaceColor,
      knobOff:
          lightPanel
              ? MobileEnvPalette.light.switchKnobOff
              : MobileEnvPalette.dark.switchKnobOff,
      knobShadow: lightPanel ? _lightPanelKnobShadow : null,
    );
  }
}

/// 样例浅态 `.env-switch::after` 的旋钮投影：`0 1px 3px rgba(26,29,27,.25)`。
const List<BoxShadow> _lightPanelKnobShadow = [
  BoxShadow(
    color: ReaderSpaceColors.knobShadow,
    offset: Offset(0, 1),
    blurRadius: 3,
  ),
];

/// 稿子 `.setting-section`：上下 14/16 内边距，段间一条 --line 发丝线，首段不画。
/// 标签行 `.setting-label`：11/600 段名在左，强调色 10px 当前值在右，下沿 11 间隙。
