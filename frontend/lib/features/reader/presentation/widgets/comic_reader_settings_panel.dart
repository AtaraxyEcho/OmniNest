import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/platform/platform_capabilities.dart';

/// 漫画阅读器的显示设置面板（对齐统一磨砂抽屉样式，支持三模式、RTL、单/双页与图片适应模式）。
class ComicReaderSettingsPanel extends StatelessWidget {
  const ComicReaderSettingsPanel({
    required this.displaySettings,
    required this.themeSettings,
    required this.onChanged,
    required this.volumeKeyPaging,
    required this.onVolumeKeyPagingChanged,
    this.pageModeEnabled,
    this.mobile = false,
    this.effectiveRtl,
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

  @override
  Widget build(BuildContext context) {
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

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        if (showPageMode) ...[
          _SectionLabel(label: l10n.readerReadingMode, color: muted),
          const SizedBox(height: 10),
          _SegmentedPill<String>(
            value: displaySettings.readingMode,
            accent: themeSettings.accentColor,
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
          settings: themeSettings,
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
            settings: themeSettings,
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
            accent: themeSettings.accentColor,
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
            settings: themeSettings,
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
            AppSlider(
              value: displaySettings.contentWidth,
              min: 480,
              max: 1440,
              divisions: 12,
              onChanged:
                  (value) =>
                      onChanged(displaySettings.copyWith(contentWidth: value)),
            ),
          ],
          const SizedBox(height: 16),
          _SectionLabel(
            label: l10n.readerComicPageGap(displaySettings.pageGap.round()),
            color: muted,
          ),
          AppSlider(
            value: displaySettings.pageGap,
            min: 0,
            max: 24,
            divisions: 12,
            onChanged:
                (value) => onChanged(displaySettings.copyWith(pageGap: value)),
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
            settings: themeSettings,
            mobile: mobile,
            onChanged: onVolumeKeyPagingChanged,
          ),
        ],
      ],
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
