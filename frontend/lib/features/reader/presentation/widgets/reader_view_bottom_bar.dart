import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器底部导航、进度和工具控制栏。
///
/// [sampleChrome] 为样例 ReaderFocus 页脚皮肤（移动壳层）：底部渐隐
/// 渐变、3px 全书进度条 + 百分比、目录与「Aa」设置玻璃方钮；默认
/// false 维持工位实底皮肤。
class ReaderViewBottomBar extends StatelessWidget {
  const ReaderViewBottomBar({
    required this.settings,
    required this.progress,
    required this.isPageMode,
    required this.onPrevious,
    required this.onNext,
    required this.onShowContents,
    required this.onShowSettings,
    required this.onToggleImmersive,
    this.onProgressSeek,
    this.chapterIndex,
    this.chapterCount,
    this.sampleChrome = false,
    super.key,
  });

  final ReaderViewSettings settings;
  final double progress;
  final bool isPageMode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onShowContents;
  final VoidCallback onShowSettings;
  final VoidCallback onToggleImmersive;
  final ValueChanged<double>? onProgressSeek;

  /// 当前章序号（1-based）；与 [chapterCount] 同时提供时展示章节位置。
  final int? chapterIndex;
  final int? chapterCount;

  /// 样例 ReaderFocus 页脚皮肤（移动壳层玻璃 chrome）。
  final bool sampleChrome;

  @override
  Widget build(BuildContext context) {
    if (sampleChrome) {
      return _ReaderSampleBottomBar(bar: this);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = ReaderControlLayout.resolve(
          viewport: Size(
            constraints.maxWidth,
            MediaQuery.sizeOf(context).height,
          ),
          fontSize: settings.fontSize,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        );
        return ColoredBox(
          color: settings.controlSurfaceColor.withValues(alpha: 0.98),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReaderProgressSlider(
                  settings: settings,
                  progress: progress,
                  onSeekEnd: onProgressSeek,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    layout.density == ReaderControlDensity.compact ? 8 : 16,
                    2,
                    layout.density == ReaderControlDensity.compact ? 8 : 16,
                    6,
                  ),
                  child: switch (layout.density) {
                    ReaderControlDensity.compact => _buildCompact(context),
                    ReaderControlDensity.medium => _buildMedium(context),
                    ReaderControlDensity.expanded => _buildExpanded(context),
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompact(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('readerControlsCompact'),
      children: [
        _ReaderDockButton(
          settings: settings,
          icon: Icons.chevron_left_rounded,
          tooltip: l10n.readerPreviousPage,
          onPressed: onPrevious,
          size: 48,
        ),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.chevron_right_rounded,
          tooltip: l10n.readerNextPage,
          onPressed: onNext,
          size: 48,
        ),
        Expanded(child: _progressLabel(context)),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.text_format_rounded,
          tooltip: l10n.readerSettingsTitle,
          onPressed: onShowSettings,
          size: 48,
        ),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.toc_rounded,
          tooltip: l10n.readerTableOfContents,
          onPressed: onShowContents,
          size: 48,
        ),
      ],
    );
  }

  Widget _buildMedium(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('readerControlsMedium'),
      children: [
        _ReaderDockButton(
          settings: settings,
          icon: Icons.chevron_left_rounded,
          tooltip: l10n.readerPreviousPage,
          onPressed: onPrevious,
        ),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.chevron_right_rounded,
          tooltip: l10n.readerNextPage,
          onPressed: onNext,
        ),
        const SizedBox(width: 8),
        Expanded(child: _progressLabel(context)),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.text_format_rounded,
          tooltip: l10n.readerSettingsTitle,
          onPressed: onShowSettings,
        ),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.toc_rounded,
          tooltip: l10n.readerTableOfContents,
          onPressed: onShowContents,
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('readerControlsExpanded'),
      children: [
        _ReaderDockButton(
          settings: settings,
          icon: Icons.chevron_left_rounded,
          tooltip: l10n.readerPreviousPage,
          onPressed: onPrevious,
        ),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.chevron_right_rounded,
          tooltip: l10n.readerNextPage,
          onPressed: onNext,
        ),
        const SizedBox(width: 12),
        Expanded(child: _progressLabel(context)),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.text_format_rounded,
          tooltip: l10n.readerSettingsTitle,
          onPressed: onShowSettings,
        ),
        _ReaderDockButton(
          settings: settings,
          icon:
              settings.immersiveMode
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
          tooltip: l10n.readerImmersiveMode,
          selected: settings.immersiveMode,
          onPressed: onToggleImmersive,
        ),
        _ReaderDockButton(
          settings: settings,
          icon: Icons.toc_rounded,
          tooltip: l10n.readerTableOfContents,
          onPressed: onShowContents,
        ),
      ],
    );
  }

  Widget _progressLabel(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final l10n = AppLocalizations.of(context);
    final current = chapterIndex;
    final total = chapterCount;
    final text =
        (current != null &&
                total != null &&
                total > 0 &&
                current >= 1 &&
                current <= total)
            ? l10n.readerBookChapterPosition(current, total, percent)
            : l10n.readerReadingProgress(percent);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: settings.onSurfaceVariantColor,
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _ReaderProgressSlider extends StatefulWidget {
  const _ReaderProgressSlider({
    required this.settings,
    required this.progress,
    required this.onSeekEnd,
  });

  final ReaderViewSettings settings;
  final double progress;
  final ValueChanged<double>? onSeekEnd;

  @override
  State<_ReaderProgressSlider> createState() => _ReaderProgressSliderState();
}

class _ReaderProgressSliderState extends State<_ReaderProgressSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          activeTrackColor: widget.settings.accentColor,
          inactiveTrackColor: widget.settings.onSurfaceColor.withValues(
            alpha: 0.30,
          ),
          thumbColor: widget.settings.accentColor,
          overlayColor: widget.settings.accentColor.withValues(alpha: 0.16),
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
        ),
        child: AppSlider(
          value: (_dragValue ?? widget.progress).clamp(0.0, 1.0),
          onChanged:
              widget.onSeekEnd == null
                  ? null
                  : (value) => setState(() => _dragValue = value),
          onChangeEnd:
              widget.onSeekEnd == null
                  ? null
                  : (value) {
                    setState(() => _dragValue = null);
                    widget.onSeekEnd!(value);
                  },
        ),
      ),
    );
  }
}

class _ReaderDockButton extends StatelessWidget {
  const _ReaderDockButton({
    required this.settings,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = 44,
  });

  final ReaderViewSettings settings;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        foregroundColor:
            selected ? settings.accentColor : settings.onSurfaceVariantColor,
        backgroundColor:
            selected
                ? settings.accentColor.withValues(alpha: 0.12)
                : Colors.transparent,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

/// 样例 ReaderFocus 页脚：底部渐隐渐变 + 进度条/百分比 + 玻璃方钮。
class _ReaderSampleBottomBar extends StatelessWidget {
  const _ReaderSampleBottomBar({required this.bar});

  final ReaderViewBottomBar bar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = (bar.progress.clamp(0.0, 1.0) * 100).round();
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bar.settings.surfaceColor.withValues(alpha: 0),
              bar.settings.surfaceColor.withValues(alpha: 0.94),
            ],
            stops: const [0, 0.28],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
          child: Row(
            children: [
              _ReaderSampleFooterButton(
                icon: OmniIcons.previous,
                tooltip: l10n.readerPreviousPage,
                settings: bar.settings,
                onTap: bar.onPrevious,
              ),
              const SizedBox(width: 8),
              _ReaderSampleFooterButton(
                icon: OmniIcons.next,
                tooltip: l10n.readerNextPage,
                settings: bar.settings,
                onTap: bar.onNext,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ReaderProgressSlider(
                  settings: bar.settings,
                  progress: bar.progress,
                  onSeekEnd: bar.onProgressSeek,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: TextStyle(
                  color: bar.settings.onSurfaceVariantColor,
                  // ignore: font_size_whitelist
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              _ReaderSampleFooterButton(
                icon: OmniIcons.list,
                tooltip: l10n.readerTableOfContents,
                settings: bar.settings,
                onTap: bar.onShowContents,
              ),
              const SizedBox(width: 8),
              _ReaderSampleFooterButton(
                icon: OmniIcons.settings,
                label: 'Aa',
                tooltip: l10n.readerSettingsTitle,
                settings: bar.settings,
                onTap: bar.onShowSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例页脚玻璃方钮：44×44 r12，底色取调色板前景 8%（原型 Aa 按钮）。
class _ReaderSampleFooterButton extends StatelessWidget {
  const _ReaderSampleFooterButton({
    required this.icon,
    required this.tooltip,
    required this.settings,
    required this.onTap,
    this.label,
  });

  final OmniIconsData icon;
  final String tooltip;
  final ReaderViewSettings settings;
  final VoidCallback onTap;

  /// 按钮文字（如 Aa）；提供时与图标并排。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final Widget content =
        label == null
            ? OmniIcon(icon: icon, size: 19, color: settings.onSurfaceColor)
            : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OmniIcon(icon: icon, size: 16, color: settings.onSurfaceColor),
                const SizedBox(width: 4),
                Text(
                  label!,
                  style: TextStyle(
                    color: settings.onSurfaceColor,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: settings.onSurfaceColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
