import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器底部导航、进度和工具控制栏。
///
/// [sampleChrome] 为移动端阅读器稿的页脚皮肤：进度行（3px 轨道 + 百分比）在上，
/// 五槽玻璃控制条（上一章 / 目录 / Aa 显示 / 书签 / 下一章）在下；默认
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
    this.onAddBookmark,
    this.onPreviousChapter,
    this.onNextChapter,
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

  /// 书签开关：样例把第五槽给书签（顶栏只留返回、书名与更多三件）。
  /// 为空时该槽按稿子的 `:disabled` 呈现，不悄悄换成别的动作。
  final VoidCallback? onAddBookmark;

  /// 样例条的首末槽按稿子走章节（`changeChapter(±1)`），不是翻页。
  /// 到章首/章末时由本控件按 [chapterIndex]/[chapterCount] 置空。
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
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

/// 样例 `.reader-bottombar`：进度行在上（章节计数 + 3px 轨道 + 百分比），
/// 五槽玻璃控制条在下（min-height 62、r22、`--glass` 底 + blur 22、
/// 投影 0 14 38）。稿子没有进度滑杆，跳转一律走目录面板，所以这条不接
/// [ReaderViewBottomBar.onProgressSeek]。
class _ReaderSampleBottomBar extends StatelessWidget {
  const _ReaderSampleBottomBar({required this.bar});

  final ReaderViewBottomBar bar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = bar.settings;
    // 稿子首末槽是 changeChapter(±1)，并在章首/章末落 `:disabled`。
    // 章节位置没给（懒加载未就绪）时按可点处理，不让整条灰掉。
    final position = bar.chapterIndex;
    final total = bar.chapterCount;
    final canStepBack = position == null || total == null || position > 1;
    final canStepAhead = position == null || total == null || position < total;
    final percent = (bar.progress.clamp(0.0, 1.0) * 100).round();
    final hasChapters = bar.chapterIndex != null && bar.chapterCount != null;
    // 稿子整条页脚铺 `linear-gradient(to bottom, transparent, --page 30%)`：
    // 9px 的章节计数与 13% 墨色的轨道都要落在纸面上才读得清，
    // 直接压在壁纸上就是"进度条显示不清晰"。
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            settings.surfaceColor.withValues(alpha: 0),
            settings.surfaceColor,
          ],
          stops: const [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
              child: Center(
                child: ConstrainedBox(
                  // 稿子 `.progress-row`：width min(100%, 680px)、内缩 6。
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        if (hasChapters) ...[
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${bar.chapterIndex} / ${bar.chapterCount}',
                              style: TextStyle(
                                color: settings.onSurfaceVariantColor,
                                fontSize: AppTypography.labelNano,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: _ReaderSampleProgressTrack(
                            settings: settings,
                            progress: bar.progress,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 29,
                          child: Text(
                            '$percent%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: settings.onSurfaceColor,
                              fontSize: AppTypography.labelMicro,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: _ReaderSampleActionStrip(
                settings: settings,
                children: [
                  _ReaderSampleFooterButton(
                    icon: OmniIcons.previous,
                    label: l10n.readerPreviousChapter,
                    tooltip: l10n.readerPreviousChapter,
                    settings: settings,
                    onTap: canStepBack ? bar.onPreviousChapter : null,
                  ),
                  _ReaderSampleFooterButton(
                    icon: OmniIcons.list,
                    label: l10n.readerTableOfContents,
                    tooltip: l10n.readerTableOfContents,
                    settings: settings,
                    onTap: bar.onShowContents,
                  ),
                  _ReaderSampleFooterButton(
                    icon: OmniIcons.settings,
                    label: l10n.readerSettingsTitle,
                    tooltip: l10n.readerSettingsTitle,
                    settings: settings,
                    onTap: bar.onShowSettings,
                    markLabel: 'Aa',
                  ),
                  _ReaderSampleFooterButton(
                    icon: OmniIcons.bookmark,
                    label: l10n.readerAddBookmark,
                    tooltip: l10n.readerAddBookmark,
                    settings: settings,
                    onTap: bar.onAddBookmark,
                  ),
                  _ReaderSampleFooterButton(
                    icon: OmniIcons.next,
                    label: l10n.readerNextChapter,
                    tooltip: l10n.readerNextChapter,
                    settings: settings,
                    onTap: canStepAhead ? bar.onNextChapter : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 样例 `.progress-track`：3px 轨道（前景 13% 铺底）+ 强调色填充。
class _ReaderSampleProgressTrack extends StatelessWidget {
  const _ReaderSampleProgressTrack({
    required this.settings,
    required this.progress,
  });

  final ReaderViewSettings settings;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: settings.onSurfaceColor.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(4),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: settings.accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 样例 `.reader-actions`：五等分玻璃条。
class _ReaderSampleActionStrip extends StatelessWidget {
  const _ReaderSampleActionStrip({
    required this.settings,
    required this.children,
  });

  final ReaderViewSettings settings;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: settings.glassColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: settings.lineColor),
            boxShadow: [
              BoxShadow(
                color: settings.shadowColor,
                blurRadius: 38,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [for (final child in children) Expanded(child: child)],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃条内的一槽：50 高、r15，图标在上、9px 标签在下；
/// `onTap` 为空即稿子 `.reader-actions button:disabled` 的 0.3 弱化态。
class _ReaderSampleFooterButton extends StatelessWidget {
  const _ReaderSampleFooterButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.settings,
    required this.onTap,
    this.markLabel,
  });

  final OmniIconsData icon;
  final String label;
  final String tooltip;
  final ReaderViewSettings settings;
  final VoidCallback? onTap;

  /// 用文字标记替掉图标（稿子的 `Aa`：衬线 17/700）。
  final String? markLabel;

  @override
  Widget build(BuildContext context) {
    final foreground =
        onTap == null ? settings.faintColor : settings.onSurfaceColor;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
            child: Opacity(
              opacity: onTap == null ? 0.3 : 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (markLabel != null)
                    Text(
                      markLabel!,
                      style: TextStyle(
                        fontFamily: AppTypography.serifFamily,
                        fontFamilyFallback: AppTypography.serifFamilyFallback,
                        // 稿子 `.aa-mark` 就是 17/700 衬线，排版档位里没有这一档。
                        fontSize: 17, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w700,
                        height: 20 / 17,
                        color: foreground,
                      ),
                    )
                  else
                    OmniIcon(icon: icon, size: 20, color: foreground),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.labelNano,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
