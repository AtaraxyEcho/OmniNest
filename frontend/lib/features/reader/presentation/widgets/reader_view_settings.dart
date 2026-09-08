import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';

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

  ReaderReadingPalette get palette => ReaderReadingPalette.fromId(paletteId);
  Color get surfaceColor => palette.surface;
  Color get onSurfaceColor => palette.onSurface;
  Color get onSurfaceVariantColor => palette.onSurfaceVariant;
  Color get accentColor => palette.accent;
  Color get controlSurfaceColor => palette.controlSurface;
  Color get selectionColor => palette.selection;
  Color get annotationColor => palette.annotation;
  bool get isDark => paletteId == ReaderReadingPalette.dark.id;

  String? get resolvedFontFamily =>
      fontFamily == 'serif' ? 'NotoSerifSC' : null;

  TextStyle get bodyStyle => TextStyle(
    fontFamily: resolvedFontFamily,
    fontSize: fontSize,
    height: lineHeight,
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
    );
  }

  static const _settingsVersion = 4;
}

class ReaderViewSettingsPanel extends StatelessWidget {
  const ReaderViewSettingsPanel({
    required this.settings,
    required this.onSettingsChanged,
    this.embedded = false,
    super.key,
  });

  final ReaderViewSettings settings;
  final ValueChanged<ReaderViewSettings> onSettingsChanged;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[_buildHeader(context), const SizedBox(height: 20)],
        _buildReadingModeToggle(context),
        const SizedBox(height: 18),
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
      ],
    );
    if (embedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: content,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: BoxDecoration(
        color: settings.controlSurfaceColor.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(
          top: BorderSide(
            color: settings.onSurfaceColor.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: content,
    );
  }

  static String _themeName(AppLocalizations l10n, int index) {
    return switch (index) {
      0 => l10n.readerThemeLight,
      1 => l10n.readerThemeEyeCare,
      2 => l10n.readerThemeDark,
      3 => l10n.readerThemeGreen,
      _ => '',
    };
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          Icons.text_format_rounded,
          color: settings.onSurfaceColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(
          l10n.readerSettingsTitle,
          style: TextStyle(
            color: settings.onSurfaceColor,
            fontSize: AppTypography.titleMedium,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildReadingModeToggle(BuildContext context) {
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
            if (supportsPageMode) ...[
              const SizedBox(width: 10),
              _ReadingModeOption(
                icon: Icons.swap_horiz_rounded,
                label: l10n.readerModePage,
                selected: settings.readingMode == 'page',
                color: settings.accentColor,
                surfaceColor: settings.onSurfaceColor,
                onTap:
                    () => onSettingsChanged(
                      settings.copyWith(readingMode: 'page'),
                    ),
              ),
            ],
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
        Row(
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
            const SizedBox(width: 10),
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
            const SizedBox(width: 10),
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
        Row(
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
    return Row(
      children: [
        Icon(
          Icons.fullscreen_rounded,
          color: settings.onSurfaceVariantColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.readerImmersiveMode,
            style: TextStyle(
              color: settings.onSurfaceVariantColor,
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Switch(
          value: settings.immersiveMode,
          onChanged:
              (v) => onSettingsChanged(settings.copyWith(immersiveMode: v)),
          activeThumbColor: settings.accentColor,
        ),
      ],
    );
  }
}

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
