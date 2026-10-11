import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/platform/platform_capabilities.dart';

class ReaderViewSettings {
  ReaderViewSettings({
    this.fontFamily = 'serif',
    this.fontSize = 18.0,
    this.lineHeight = 1.8,
    String? paletteId,
    int? themeIndex,
    this.readingMode = 'scroll',
    this.immersiveMode = false,
    this.pageTurnMode = 'slide',
    this.volumeKeyPaging = true,
    this.mobileDefaults = false,
  }) : paletteId =
           paletteId ?? ReaderReadingPalette.idFromLegacyIndex(themeIndex ?? 2);

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final String paletteId;

  int get themeIndex => ReaderReadingPalette.legacyIndexFromId(paletteId);

  /// 阅读模式：'scroll' | 'page'。
  final String readingMode;
  final bool immersiveMode;

  /// 翻页动画样式：'slide' | 'cover' | 'fade'。
  final String pageTurnMode;

  /// 音量键翻页：移动端将音量键映射为翻页命令，默认开启。
  final bool volumeKeyPaging;

  /// 移动壳层默认值：暗档正文改用样例的衬线 19/1.85。
  /// 桌面端与已保存偏好看不见此分支。
  final bool mobileDefaults;

  ReaderViewSettings withMobileDefaults() {
    if (mobileDefaults || paletteId != ReaderReadingPalette.dark.id) {
      return this;
    }
    return copyWith(
      // ignore: font_size_whitelist
      fontSize: 19,
      lineHeight: 1.85,
    );
  }

  ReaderReadingPalette get palette => ReaderReadingPalette.fromId(paletteId);
  Color get surfaceColor => palette.surface;
  Color get elevatedColor => palette.elevated;
  Color get onSurfaceColor => palette.onSurface;
  Color get onSurfaceVariantColor => palette.onSurfaceVariant;
  Color get faintColor => palette.faint;
  Color get lineColor => palette.line;
  Color get accentColor => palette.accent;
  Color get accentSoftColor => palette.accentSoft;
  Color get controlSurfaceColor => palette.controlSurface;
  Color get glassColor => palette.glass;
  Color get glassSolidColor => palette.glassSolid;
  Color get shadowColor => palette.shadow;
  Color get selectionColor => palette.selection;
  bool get isDark => paletteId == ReaderReadingPalette.dark.id;

  String? get resolvedFontFamily =>
      fontFamily == 'serif' ? 'NotoSerifSC' : null;

  /// 正文样式：字距按稿子 `.article-column > p` 的 `letter-spacing: .025em`，
  /// 分页引擎的 `ReaderViewContent.spanStyle` 必须跟着同一份，否则测量与渲染
  /// 的行长不一致，断页会漂。
  TextStyle get bodyStyle => TextStyle(
    fontFamily: resolvedFontFamily,
    fontSize: fontSize,
    height: lineHeight,
    letterSpacing: fontSize * 0.025,
    color: onSurfaceColor,
  );

  /// 返回与正文渲染及分页测量一致的行高约束。
  StrutStyle bodyStrutStyle({double textScale = 1}) => StrutStyle(
    fontFamily: resolvedFontFamily,
    fontSize: fontSize * textScale,
    height: lineHeight,
    forceStrutHeight: true,
  );

  ReaderViewSettings copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    String? paletteId,
    int? themeIndex,
    String? readingMode,
    bool? immersiveMode,
    String? pageTurnMode,
    bool? volumeKeyPaging,
    bool? mobileDefaults,
  }) {
    return ReaderViewSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paletteId:
          paletteId ??
          (themeIndex == null
              ? this.paletteId
              : ReaderReadingPalette.idFromLegacyIndex(themeIndex)),
      readingMode: readingMode ?? this.readingMode,
      immersiveMode: immersiveMode ?? this.immersiveMode,
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      volumeKeyPaging: volumeKeyPaging ?? this.volumeKeyPaging,
      mobileDefaults: mobileDefaults ?? this.mobileDefaults,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paletteId': paletteId,
    'themeIndex': themeIndex,
    'readingMode': readingMode,
    'immersiveMode': immersiveMode,
    'pageTurnMode': pageTurnMode,
    'volumeKeyPaging': volumeKeyPaging,
    'version': _settingsVersion,
  };

  factory ReaderViewSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    // 版本迁移：逐步升级旧版本数据到最新结构
    var migrated = Map<String, dynamic>.from(json);
    if (version < 1) {
      // v0 → v1：新增 immersiveMode 字段，使用默认值
      migrated['immersiveMode'] ??= false;
    }
    if (version < 3) {
      // v1/v2 → v3：pageTransition 重命名为 pageTurnMode，移除 scroll 值
      final oldTransition = migrated.remove('pageTransition') as String?;
      if (oldTransition != null && oldTransition != 'scroll') {
        migrated['pageTurnMode'] = oldTransition;
      }
      migrated.remove('pageTransition');
    }
    if (version < 4) {
      final legacyThemeIndex = migrated['themeIndex'] as int? ?? 2;
      migrated['paletteId'] = ReaderReadingPalette.idFromLegacyIndex(
        legacyThemeIndex,
      );
    }
    if (version < 5) {
      // v4 → v5：新增 volumeKeyPaging 字段，默认开启
      migrated['volumeKeyPaging'] ??= true;
    }

    final rawFontSize = (migrated['fontSize'] as num?)?.toDouble() ?? 18.0;
    final rawLineHeight = (migrated['lineHeight'] as num?)?.toDouble() ?? 1.8;
    final rawPaletteId = migrated['paletteId'] as String? ?? 'dark';
    final rawFontFamily = migrated['fontFamily'] as String? ?? 'serif';
    const allowedFonts = ['serif', 'sans', 'system'];
    const allowedTurnModes = ['slide', 'cover', 'fade'];
    final rawTurnMode = migrated['pageTurnMode'] as String? ?? 'slide';
    return ReaderViewSettings(
      fontFamily:
          allowedFonts.contains(rawFontFamily) ? rawFontFamily : 'serif',
      fontSize: rawFontSize.clamp(12.0, 32.0),
      lineHeight: rawLineHeight.clamp(1.0, 3.0),
      paletteId: ReaderReadingPalette.fromId(rawPaletteId).id,
      readingMode:
          supportsPageMode
              ? (migrated['readingMode'] as String? ?? 'scroll')
              : 'scroll',
      immersiveMode: migrated['immersiveMode'] as bool? ?? false,
      pageTurnMode:
          allowedTurnModes.contains(rawTurnMode) ? rawTurnMode : 'slide',
      volumeKeyPaging: migrated['volumeKeyPaging'] as bool? ?? true,
    );
  }

  static const _settingsVersion = 5;
}

class ReaderViewSettingsPanel extends StatelessWidget {
  const ReaderViewSettingsPanel({
    required this.settings,
    required this.onSettingsChanged,
    this.embedded = false,
    this.pageModeEnabled,
    this.mobile = false,
    super.key,
  });

  final ReaderViewSettings settings;
  final ValueChanged<ReaderViewSettings> onSettingsChanged;
  final bool embedded;

  /// 是否提供翻页模式；null 时跟随 [supportsPageMode]（Web 恒 false）。
  final bool? pageModeEnabled;

  /// 移动壳层：开关换成样例 .env-switch 胶囊，整行作为点按目标。
  /// 工位皮肤保持直角开关，两种形态不共用一套几何。
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final showPageMode = pageModeEnabled ?? supportsPageMode;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[_buildHeader(context), const SizedBox(height: 20)],
        if (showPageMode) ...[
          _buildReadingModeToggle(context),
          const SizedBox(height: 18),
        ],
        _buildPageTransitionToggle(context),
        const SizedBox(height: 18),
        _buildFontSizeControl(context),
        const SizedBox(height: 18),
        _buildLineHeightControl(context),
        const SizedBox(height: 18),
        _buildFontFamilyToggle(context),
        const SizedBox(height: 18),
        _buildThemeSelector(context),
        const SizedBox(height: 18),
        _buildImmersiveToggle(context),
        const SizedBox(height: 18),
        _buildVolumeKeyPagingToggle(context),
      ],
    );
    if (embedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: content,
      );
    }
    // 稿子 `.bottom-sheet`：max-height min(82dvh, 720px)，超出纵向滚动。
    // 头部换成 25pt 衬线 + 手柄后面板更高，不滚动尾部开关就落在剪切区外。
    final sheetMaxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      decoration: BoxDecoration(
        // 与目录面板同一张稿子 `.bottom-sheet`：glass-solid 实底、顶部 r28、
        // 三边 --line 描边（底边贴屏不画）、投影 0 -20 60。
        color: settings.glassSolidColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: settings.lineColor),
          left: BorderSide(color: settings.lineColor),
          right: BorderSide(color: settings.lineColor),
        ),
        boxShadow: [
          BoxShadow(
            color: settings.shadowColor,
            blurRadius: 60,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: sheetMaxHeight > 720 ? 720.0 : sheetMaxHeight,
        ),
        child: SingleChildScrollView(child: content),
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

  /// 稿子 `.sheet-handle` + `.sheet-header h2`：先手柄，再 25/600 衬线面板名。
  /// 样式的抽屉头部不放图标，图标位留给右侧关闭钮。
  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          child: Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: settings.onSurfaceColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        Text(
          l10n.readerSettingsTitle,
          style: TextStyle(
            fontFamily: AppTypography.serifFamily,
            fontFamilyFallback: AppTypography.serifFamilyFallback,
            color: settings.onSurfaceColor,
            fontSize: 25, // ignore: font_size_whitelist
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildReadingModeToggle(BuildContext context) {
    // Web 只开放滚动阅读（产品决策 D3）；整段由 build 的 showPageMode 门控。
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readerReadingMode,
          style: TextStyle(
            color: settings.onSurfaceVariantColor,
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _ReadingModeOption(
              icon: Icons.swap_vert_rounded,
              label: l10n.readerModeScroll,
              selected: settings.readingMode == 'scroll',
              color: settings.accentColor,
              surfaceColor: settings.onSurfaceColor,
              onTap:
                  () => onSettingsChanged(
                    settings.copyWith(readingMode: 'scroll'),
                  ),
            ),
            const SizedBox(width: 10),
            _ReadingModeOption(
              icon: Icons.swap_horiz_rounded,
              label: l10n.readerModePage,
              selected: settings.readingMode == 'page',
              color: settings.accentColor,
              surfaceColor: settings.onSurfaceColor,
              onTap:
                  () =>
                      onSettingsChanged(settings.copyWith(readingMode: 'page')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPageTransitionToggle(BuildContext context) {
    // 仅在翻页模式下显示
    if (settings.readingMode != 'page') return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final transitions = [
      ('slide', Icons.swap_horiz_rounded, l10n.readerTransitionSlide),
      ('cover', Icons.layers_rounded, l10n.readerTransitionCover),
      ('fade', Icons.animation_rounded, l10n.readerTransitionFade),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readerPageTransition,
          style: TextStyle(
            color: settings.onSurfaceVariantColor,
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < transitions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _ReadingModeOption(
                icon: transitions[i].$2,
                label: transitions[i].$3,
                selected: settings.pageTurnMode == transitions[i].$1,
                color: settings.accentColor,
                surfaceColor: settings.onSurfaceColor,
                onTap:
                    () => onSettingsChanged(
                      settings.copyWith(pageTurnMode: transitions[i].$1),
                    ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFontSizeControl(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.readerFontSize,
              style: TextStyle(
                color: settings.onSurfaceVariantColor,
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${settings.fontSize.round()}px',
              style: TextStyle(
                color: settings.accentColor,
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: settings.accentColor,
            inactiveTrackColor: settings.onSurfaceColor.withValues(alpha: 0.12),
            thumbColor: settings.accentColor,
            overlayColor: settings.accentColor.withValues(alpha: 0.18),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
          ),
          child: AppSlider(
            value: settings.fontSize,
            min: 14,
            max: 28,
            divisions: 14,
            onChanged: (v) => onSettingsChanged(settings.copyWith(fontSize: v)),
          ),
        ),
      ],
    );
  }

  Widget _buildLineHeightControl(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.readerLineHeight,
              style: TextStyle(
                color: settings.onSurfaceVariantColor,
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              settings.lineHeight.toStringAsFixed(1),
              style: TextStyle(
                color: settings.accentColor,
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: settings.accentColor,
            inactiveTrackColor: settings.onSurfaceColor.withValues(alpha: 0.12),
            thumbColor: settings.accentColor,
            overlayColor: settings.accentColor.withValues(alpha: 0.18),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
          ),
          child: AppSlider(
            value: settings.lineHeight,
            min: 1.2,
            max: 2.4,
            divisions: 12,
            onChanged:
                (v) => onSettingsChanged(settings.copyWith(lineHeight: v)),
          ),
        ),
      ],
    );
  }

  Widget _buildFontFamilyToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readerFontFamily,
          style: TextStyle(
            color: settings.onSurfaceVariantColor,
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        // 3 个字族项在手机面板宽度与大字号档位下会超出裸 Row 的可用宽，
        // 改用 Wrap 让其换行；间距由 Wrap 统一承担。
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FontOption(
              label: l10n.readerFontSerif,
              fontFamily: 'NotoSerifSC',
              selected: settings.fontFamily == 'serif',
              color: settings.accentColor,
              surfaceColor: settings.onSurfaceColor,
              onTap:
                  () =>
                      onSettingsChanged(settings.copyWith(fontFamily: 'serif')),
            ),
            _FontOption(
              label: l10n.readerFontSans,
              fontFamily: null,
              selected: settings.fontFamily == 'sans',
              color: settings.accentColor,
              surfaceColor: settings.onSurfaceColor,
              onTap:
                  () =>
                      onSettingsChanged(settings.copyWith(fontFamily: 'sans')),
            ),
            _FontOption(
              label: l10n.readerFontSystem,
              fontFamily: null,
              selected: settings.fontFamily == 'system',
              color: settings.accentColor,
              surfaceColor: settings.onSurfaceColor,
              onTap:
                  () => onSettingsChanged(
                    settings.copyWith(fontFamily: 'system'),
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readerTheme,
          style: TextStyle(
            color: settings.onSurfaceVariantColor,
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        // 4 个主题项在窄面板与字号上限档位下超出裸 Row 可用宽，允许换行。
        Wrap(
          runSpacing: 10,
          children: List.generate(ReaderReadingPalette.values.length, (i) {
            final theme = ReaderReadingPalette.values[i];
            final selected = settings.themeIndex == i;
            return Padding(
              padding: EdgeInsets.only(
                right: i < ReaderReadingPalette.values.length - 1 ? 10 : 0,
              ),
              child: _ThemeOption(
                theme: theme,
                localizedName: _themeName(l10n, i),
                selected: selected,
                labelColor:
                    selected
                        ? settings.accentColor
                        : settings.onSurfaceVariantColor,
                onTap:
                    () => onSettingsChanged(settings.copyWith(themeIndex: i)),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildImmersiveToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _buildToggleRow(
      context,
      icon: Icons.fullscreen_rounded,
      label: l10n.readerImmersiveMode,
      value: settings.immersiveMode,
      onChanged: (v) => onSettingsChanged(settings.copyWith(immersiveMode: v)),
    );
  }

  Widget _buildVolumeKeyPagingToggle(BuildContext context) {
    // 音量键翻页依赖原生按键拦截，仅具备该能力的平台展示（当前 Android）。
    if (!PlatformCapabilities.current().supportsVolumeKeyPageTurn) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
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
      knobOff: lightPanel ? const Color(0xFFFFFFFF) : const Color(0xFFF6F6F2),
      knobShadow: lightPanel ? _lightPanelKnobShadow : null,
    );
  }
}

/// 样例浅态 `.env-switch::after` 的旋钮投影：`0 1px 3px rgba(26,29,27,.25)`。
const List<BoxShadow> _lightPanelKnobShadow = [
  BoxShadow(color: Color(0x401A1D1B), offset: Offset(0, 1), blurRadius: 3),
];

class _ReadingModeOption extends StatelessWidget {
  const _ReadingModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.surfaceColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final Color surfaceColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color:
                selected
                    ? color.withValues(alpha: 0.14)
                    : surfaceColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected
                      ? color.withValues(alpha: 0.40)
                      : surfaceColor.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? color : surfaceColor.withValues(alpha: 0.70),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color:
                      selected ? color : surfaceColor.withValues(alpha: 0.70),
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontOption extends StatelessWidget {
  const _FontOption({
    required this.label,
    required this.fontFamily,
    required this.selected,
    required this.color,
    required this.surfaceColor,
    required this.onTap,
  });

  final String label;
  final String? fontFamily;
  final bool selected;
  final Color color;
  final Color surfaceColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color:
                selected
                    ? color.withValues(alpha: 0.14)
                    : surfaceColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected
                      ? color.withValues(alpha: 0.40)
                      : surfaceColor.withValues(alpha: 0.10),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: fontFamily,
              color: selected ? color : surfaceColor.withValues(alpha: 0.70),
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

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
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      selected
                          ? theme.accent
                          : theme.onSurface.withValues(alpha: 0.12),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child:
                  selected
                      ? Icon(Icons.check_rounded, color: theme.accent, size: 22)
                      : null,
            ),
            const SizedBox(height: 6),
            Text(
              localizedName,
              style: TextStyle(
                color: labelColor,
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
