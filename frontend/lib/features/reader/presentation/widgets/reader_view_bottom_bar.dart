import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器底部导航、进度和工具控制栏。
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

  @override
  Widget build(BuildContext context) {
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
