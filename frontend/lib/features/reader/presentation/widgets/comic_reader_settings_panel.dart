import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/application/reader_preferences_controller.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/platform/platform_capabilities.dart';

/// 漫画阅读器的显示设置面板（对齐统一磨砂抽屉样式，支持背景主题 4 色卡、亮度、护眼暖色、
/// 自动夜间、漫画缩放、三模式、RTL、单/双页与图片适应模式）。
class ComicReaderSettingsPanel extends ConsumerWidget {
  const ComicReaderSettingsPanel({
    required this.displaySettings,
    required this.themeSettings,
    required this.onChanged,
    required this.volumeKeyPaging,
    required this.onVolumeKeyPagingChanged,
    this.pageModeEnabled,
    this.mobile = false,
    this.effectiveRtl,
    this.zoomScale,
    this.onZoomIn,
    this.onZoomOut,
    this.onResetZoom,
    super.key,
  });

  final ComicReaderDisplaySettings displaySettings;
  final ReaderViewSettings themeSettings;
  final ValueChanged<ComicReaderDisplaySettings> onChanged;
  final bool volumeKeyPaging;
  final ValueChanged<bool> onVolumeKeyPagingChanged;

  /// 是否提供翻页模式；null 时跟随平台能力（桌面 Web 与原生支持，手机 Web 不支持）。
  final bool? pageModeEnabled;

  /// 移动壳层：开关换成样例 .env-switch 胶囊（见 [ReaderToggleSwitch]）。
  final bool mobile;

  /// 当前生效的 RTL 状态（含清单默认推导）；为空时取 `displaySettings.rtlOverride ?? false`。
  final bool? effectiveRtl;

  /// 可选缩放倍率与回调；未显式传入时自动联动宿主 `ComicReaderViewState`。
  final double? zoomScale;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onResetZoom;

  Future<void> _savePreferencePatch(
    WidgetRef ref,
    Map<String, dynamic> patch,
  ) async {
    final current =
        ref.read(readerPreferencesProvider).asData?.value ??
        await ref.read(readerPreferencesProvider.future);
    await ref.read(readerPreferencesProvider.notifier).save({
      ...?current,
      ...patch,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final inDarkGlass = ReaderPanelSurfaceScope.isDarkGlass(context);
    final fg =
        inDarkGlass
            ? ReaderReadingPalette.desktopPopoverOnSurface
            : themeSettings.onSurfaceColor;
    final muted =
        inDarkGlass
            ? ReaderReadingPalette.desktopPopoverMuted
            : themeSettings.onSurfaceVariantColor;
    final showPageMode = pageModeEnabled ?? supportsPageMode;
    final isRtl = effectiveRtl ?? displaySettings.rtlOverride ?? false;
    final isPaged = displaySettings.readingMode != 'scroll';
    final isSwipeMode =
        displaySettings.readingMode == 'page' ||
        displaySettings.readingMode == 'swipe';

    final prefsMap = ref.watch(readerPreferencesProvider).asData?.value;
    final activeSettings =
        prefsMap != null && prefsMap.isNotEmpty
            ? ReaderViewSettings.fromJson(prefsMap)
            : themeSettings;
    final hostState = context.findAncestorStateOfType<ComicReaderViewState>();
    final effectiveZoom =
        isSwipeMode ? (zoomScale ?? hostState?.currentZoomScale ?? 1.0) : 1.0;
    final handleZoomOut =
        isSwipeMode ? (onZoomOut ?? hostState?.zoomOut) : null;
    final handleZoomIn = isSwipeMode ? (onZoomIn ?? hostState?.zoomIn) : null;
    final handleResetZoom =
        isSwipeMode ? (onResetZoom ?? hostState?.resetZoom) : null;

    final sliderTheme = SliderThemeData(
      trackHeight: 4,
      activeTrackColor: activeSettings.accentColor,
      inactiveTrackColor: fg.withValues(alpha: 0.18),
      thumbColor: activeSettings.accentColor,
      overlayColor: activeSettings.accentColor.withValues(alpha: 0.18),
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
    );

    final themeChoices = <(ReaderReadingPalette, String)>[
      (ReaderReadingPalette.light, isZh ? '纸白' : 'Paper'),
      (ReaderReadingPalette.eyeCare, isZh ? '暖黄' : 'Sepia'),
      (ReaderReadingPalette.dusk, isZh ? '暮色' : 'Dusk'),
      (ReaderReadingPalette.dark, isZh ? '夜间' : 'Night'),
    ];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        // 1. 背景主题 4 色卡（Paper / Sepia / Dusk / Night）
        _SectionLabel(label: l10n.readerTheme, color: muted),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < themeChoices.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ThemeSwatchCard(
                  palette: themeChoices[i].$1,
                  label: themeChoices[i].$2,
                  selected: activeSettings.paletteId == themeChoices[i].$1.id,
                  accent: activeSettings.accentColor,
                  foreground: fg,
                  onTap: () {
                    final palette = themeChoices[i].$1;
                    unawaited(
                      _savePreferencePatch(ref, {
                        'paletteId': palette.id,
                        'themeIndex': ReaderReadingPalette.legacyIndexFromId(
                          palette.id,
                        ),
                      }),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),

        // 2. 亮度（30–100%）
        _SliderHeader(
          label: l10n.readerBrightness,
          valueLabel: '${activeSettings.brightness}%',
          color: muted,
          accent: activeSettings.accentColor,
        ),
        SliderTheme(
          data: sliderTheme,
          child: AppSlider(
            value: activeSettings.brightness.clamp(30, 100).toDouble(),
            min: 30,
            max: 100,
            divisions: 14,
            onChanged:
                (v) => unawaited(
                  _savePreferencePatch(ref, {'brightness': v.round()}),
                ),
          ),
        ),
        const SizedBox(height: 10),

        // 3. 护眼暖色（0–60%）
        _SliderHeader(
          label: l10n.readerWarmth,
          valueLabel: '${activeSettings.warmth}%',
          color: muted,
          accent: activeSettings.accentColor,
        ),
        SliderTheme(
          data: sliderTheme,
          child: AppSlider(
            value: activeSettings.warmth.clamp(0, 60).toDouble(),
            min: 0,
            max: 60,
            divisions: 12,
            onChanged:
                (v) =>
                    unawaited(_savePreferencePatch(ref, {'warmth': v.round()})),
          ),
        ),
        const SizedBox(height: 12),

        // 4. 自动夜间开关
        _ToggleRow(
          title: l10n.readerAutoNight,
          subtitle: l10n.readerAutoNightHint,
          value: activeSettings.autoNight,
          foreground: fg,
          muted: muted,
          settings: activeSettings,
          mobile: mobile,
          onChanged:
              (v) => unawaited(_savePreferencePatch(ref, {'autoNight': v})),
        ),
        const SizedBox(height: 18),

        // 5. 漫画 Zoom（- / 100% / +；非 Swipe 模式置灰并标注提示）
        Row(
          children: [
            Expanded(
              child: _SectionLabel(label: isZh ? '画面缩放' : 'Zoom', color: muted),
            ),
            if (!isSwipeMode)
              Text(
                isZh ? '仅滑动模式可用' : 'Swipe mode only',
                style: TextStyle(
                  color: muted.withValues(alpha: 0.78),
                  fontSize: AppTypography.labelMicro,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Opacity(
          opacity: isSwipeMode ? 1.0 : 0.45,
          child: IgnorePointer(
            ignoring: !isSwipeMode,
            child: _ZoomControlRow(
              zoomScale: effectiveZoom,
              foreground: fg,
              accent: activeSettings.accentColor,
              onZoomOut: handleZoomOut,
              onResetZoom: handleResetZoom,
              onZoomIn: handleZoomIn,
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (showPageMode) ...[
          _SectionLabel(label: l10n.readerReadingMode, color: muted),
          const SizedBox(height: 10),
          _SegmentedPill<String>(
            value: displaySettings.readingMode,
            accent: activeSettings.accentColor,
            foreground: fg,
            options: [
              ('book', l10n.readerModeBook, Icons.auto_stories_outlined),
              ('page', l10n.readerModeSwipe, Icons.swap_horiz_rounded),
              ('scroll', l10n.readerModeScroll, Icons.view_stream_outlined),
            ],
            onSelected:
                (mode) =>
                    onChanged(displaySettings.copyWith(readingMode: mode)),
          ),
          const SizedBox(height: 20),
        ],
        // RTL 日漫阅读方向切换
        _ToggleRow(
          title: isZh ? '日漫方向（从右向左）' : 'Right-to-Left (Manga)',
          subtitle:
              isZh
                  ? '翻转左右翻页热区、3D 翻页与底栏进度方向'
                  : 'Reverse tap zones, page curl, and progress bar',
          value: isRtl,
          foreground: fg,
          muted: muted,
          settings: activeSettings,
          mobile: mobile,
          onChanged:
              (value) =>
                  onChanged(displaySettings.copyWith(rtlOverride: value)),
        ),
        if (showPageMode && isPaged) ...[
          const SizedBox(height: 16),
          // 单/双页跨页切换
          _ToggleRow(
            title: isZh ? '双页跨页显示' : 'Dual-Page Spread',
            subtitle:
                isZh
                    ? '宽屏并排显示两页，跨页宽图自动独占整屏'
                    : 'Show two pages side by side; wide spreads fill screen',
            value: displaySettings.dualPage,
            foreground: fg,
            muted: muted,
            settings: activeSettings,
            mobile: mobile,
            onChanged:
                (value) => onChanged(displaySettings.copyWith(dualPage: value)),
          ),
          const SizedBox(height: 20),
          // 图片适应模式
          _SectionLabel(label: isZh ? '图片适应模式' : 'Image Fit', color: muted),
          const SizedBox(height: 10),
          _SegmentedPill<String>(
            value: displaySettings.imageFit,
            accent: activeSettings.accentColor,
            foreground: fg,
            options: [
              (
                'contain',
                isZh ? '适应屏幕' : 'Fit Screen',
                Icons.fit_screen_outlined,
              ),
              (
                'fitWidth',
                isZh ? '适应宽度' : 'Fit Width',
                Icons.swap_horiz_rounded,
              ),
              (
                'fitHeight',
                isZh ? '适应高度' : 'Fit Height',
                Icons.swap_vert_rounded,
              ),
            ],
            onSelected:
                (fit) => onChanged(displaySettings.copyWith(imageFit: fit)),
          ),
        ],
        if (!isPaged) ...[
          const SizedBox(height: 18),
          _ToggleRow(
            title: l10n.readerComicFullWidth,
            subtitle: l10n.readerComicFullWidthHint,
            value: displaySettings.fullWidth,
            foreground: fg,
            muted: muted,
            settings: activeSettings,
            mobile: mobile,
            onChanged:
                (value) =>
                    onChanged(displaySettings.copyWith(fullWidth: value)),
          ),
          if (!displaySettings.fullWidth) ...[
            const SizedBox(height: 16),
            _SectionLabel(
              label: l10n.readerComicContentWidth(
                displaySettings.contentWidth.round(),
              ),
              color: muted,
            ),
            SliderTheme(
              data: sliderTheme,
              child: AppSlider(
                value: displaySettings.contentWidth,
                min: 480,
                max: 1440,
                divisions: 12,
                onChanged:
                    (value) => onChanged(
                      displaySettings.copyWith(contentWidth: value),
                    ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _SectionLabel(
            label: l10n.readerComicPageGap(displaySettings.pageGap.round()),
            color: muted,
          ),
          SliderTheme(
            data: sliderTheme,
            child: AppSlider(
              value: displaySettings.pageGap,
              min: 0,
              max: 24,
              divisions: 12,
              onChanged:
                  (value) =>
                      onChanged(displaySettings.copyWith(pageGap: value)),
            ),
          ),
        ],
        // 音量键翻页依赖原生按键拦截，仅具备该能力的平台提供设置项。
        if (PlatformCapabilities.current().supportsVolumeKeyPageTurn) ...[
          const SizedBox(height: 18),
          _ToggleRow(
            title: l10n.readerVolumeKeyPaging,
            value: volumeKeyPaging,
            foreground: fg,
            muted: muted,
            settings: activeSettings,
            mobile: mobile,
            onChanged: onVolumeKeyPagingChanged,
          ),
        ],
      ],
    );
  }
}

class _ThemeSwatchCard extends StatelessWidget {
  const _ThemeSwatchCard({
    required this.palette,
    required this.label,
    required this.selected,
    required this.accent,
    required this.foreground,
    required this.onTap,
  });

  final ReaderReadingPalette palette;
  final String label;
  final bool selected;
  final Color accent;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: MotionToken.reduced(context, MotionToken.fast),
            height: 36,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : foreground.withValues(alpha: 0.16),
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: palette.onSurface,
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? accent : foreground.withValues(alpha: 0.72),
              fontSize: AppTypography.labelMicro,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderHeader extends StatelessWidget {
  const _SliderHeader({
    required this.label,
    required this.valueLabel,
    required this.color,
    required this.accent,
  });

  final String label;
  final String valueLabel;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SectionLabel(label: label, color: color)),
        Text(
          valueLabel,
          style: TextStyle(
            color: accent,
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ZoomControlRow extends StatelessWidget {
  const _ZoomControlRow({
    required this.zoomScale,
    required this.foreground,
    required this.accent,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.onZoomIn,
  });

  final double zoomScale;
  final Color foreground;
  final Color accent;
  final VoidCallback? onZoomOut;
  final VoidCallback? onResetZoom;
  final VoidCallback? onZoomIn;

  @override
  Widget build(BuildContext context) {
    final percent = (zoomScale * 100).round();
    final enabled = onZoomIn != null && onZoomOut != null;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: foreground.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ZoomActionButton(
              icon: Icons.remove_rounded,
              foreground: foreground,
              onTap: enabled && zoomScale > 1.01 ? onZoomOut : null,
            ),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onResetZoom : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      zoomScale > 1.02
                          ? accent.withValues(alpha: 0.22)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$percent%',
                  style: TextStyle(
                    color: zoomScale > 1.02 ? accent : foreground,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _ZoomActionButton(
              icon: Icons.add_rounded,
              foreground: foreground,
              onTap: enabled && zoomScale < 3.95 ? onZoomIn : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomActionButton extends StatelessWidget {
  const _ZoomActionButton({
    required this.icon,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color:
              onTap == null
                  ? foreground.withValues(alpha: 0.30)
                  : foreground.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.foreground,
    required this.muted,
    required this.settings,
    required this.mobile,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final Color foreground;
  final Color muted;
  final ReaderViewSettings settings;
  final bool mobile;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: muted,
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ReaderToggleSwitch(
            settings: settings,
            mobile: mobile,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SegmentedPill<T> extends StatelessWidget {
  const _SegmentedPill({
    required this.value,
    required this.accent,
    required this.foreground,
    required this.options,
    required this.onSelected,
  });

  final T value;
  final Color accent;
  final Color foreground;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: foreground.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          for (final (id, label, icon) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(id),
                child: AnimatedContainer(
                  duration: MotionToken.reduced(context, MotionToken.fast),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color:
                        value == id
                            ? accent.withValues(alpha: 0.22)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color:
                            value == id
                                ? accent
                                : foreground.withValues(alpha: 0.72),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                value == id
                                    ? foreground
                                    : foreground.withValues(alpha: 0.72),
                            fontSize: AppTypography.bodySmall,
                            fontWeight:
                                value == id ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}
