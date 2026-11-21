part of 'comic_reader_overlays.dart';

/// 漫画阅读器的统一底部控制栏（对齐 `.bk-foot` 单行居中样式，RTL 自动反转进度条，
/// 支持拖动进度条实时预览页码与百分比，双页显示 `Pages X–Y of TOTAL`）。
class ComicReaderBottomBar extends StatefulWidget {
  const ComicReaderBottomBar({
    required this.currentPageIndex,
    required this.totalPages,
    required this.isPageMode,
    required this.settings,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.onShowContents,
    this.onSwitchReadingMode,
    this.visible = true,
    this.isRtl = false,
    this.isDualPage = false,
    this.visibleEndPageIndex,
    this.zoomScale = 1.0,
    this.onResetZoom,
    super.key,
  });

  final int currentPageIndex;
  final int totalPages;
  final bool isPageMode;
  final ReaderViewSettings settings;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onSeek;
  final VoidCallback onShowContents;
  final VoidCallback? onSwitchReadingMode;

  /// 控件条显隐：子树常驻语义树，隐藏时仅淡出并屏蔽指针。
  final bool visible;

  /// RTL 日漫模式：自动反转进度条方向（`TextDirection.rtl`）。
  final bool isRtl;

  /// 双页模式：显示 `Pages X–Y of TOTAL`。
  final bool isDualPage;

  /// 当前跨页可见末页索引（0-based）。
  final int? visibleEndPageIndex;

  /// 当前缩放倍率（> 1.02 时展示可点击复位徽标）。
  final double zoomScale;
  final VoidCallback? onResetZoom;

  @override
  State<ComicReaderBottomBar> createState() => _ComicReaderBottomBarState();
}

class _ComicReaderBottomBarState extends State<ComicReaderBottomBar> {
  int? _previewPageIndex;

  @override
  void didUpdateWidget(ComicReaderBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalPages != widget.totalPages) {
      _previewPageIndex = null;
    }
  }

  void _handlePreviewChanged(int? pageIndex) {
    if (_previewPageIndex != pageIndex) {
      setState(() => _previewPageIndex = pageIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalPages = widget.totalPages;
    final maxPage = totalPages <= 1 ? 1.0 : (totalPages - 1).toDouble();
    final settings = widget.settings;
    final bookMode = settings.usesBookDesk;
    final textColor =
        bookMode
            ? settings.bookDeskTextColor.withValues(alpha: 0.72)
            : settings.onSurfaceVariantColor;
    final isPreviewing = _previewPageIndex != null;
    final displayPageIndex =
        (_previewPageIndex ?? widget.currentPageIndex)
            .clamp(0, math.max(0, totalPages - 1))
            .toInt();
    final endIndex =
        isPreviewing
            ? displayPageIndex
            : (widget.visibleEndPageIndex ?? displayPageIndex);
    final pageLabel =
        totalPages <= 0
            ? '0 / 0'
            : (!isPreviewing && widget.isDualPage && endIndex > displayPageIndex
                ? l10n.readerPageRange(
                  displayPageIndex + 1,
                  math.min(totalPages, endIndex + 1),
                  totalPages,
                )
                : l10n.readerPageOf(displayPageIndex + 1, totalPages));
    final percent =
        totalPages <= 0
            ? 0
            : (((endIndex + 1) / totalPages).clamp(0.0, 1.0) * 100).round();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedContainer(
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, widget.visible ? 0 : 8, 0),
          child: AnimatedOpacity(
            opacity: widget.visible ? 1 : 0,
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alwaysIncludeSemantics: true,
            child: DecoratedBox(
              decoration:
                  bookMode
                      ? const BoxDecoration()
                      : BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            settings.surfaceColor.withValues(alpha: 0),
                            settings.surfaceColor.withValues(alpha: 0.94),
                          ],
                          stops: const [0, 0.6],
                        ),
                      ),
              child: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final layout = ReaderControlLayout.resolve(
                      viewport: Size(
                        constraints.maxWidth,
                        MediaQuery.sizeOf(context).height,
                      ),
                      fontSize: AppTypography.titleMedium,
                    );
                    final compact =
                        layout.density == ReaderControlDensity.compact;

                    if (!compact) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(40, 10, 40, 18),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 152,
                                  child: Text(
                                    pageLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: AppTypography.bodySmall,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Directionality(
                                    textDirection:
                                        widget.isRtl
                                            ? TextDirection.rtl
                                            : TextDirection.ltr,
                                    child: _ComicPageSlider(
                                      currentPageIndex: widget.currentPageIndex,
                                      totalPages: totalPages,
                                      maxPage: maxPage,
                                      settings: settings,
                                      onPreviewChanged: _handlePreviewChanged,
                                      onSeek: widget.onSeek,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                if (widget.zoomScale > 1.02 &&
                                    widget.onResetZoom != null) ...[
                                  GestureDetector(
                                    onTap: widget.onResetZoom,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: settings.accentColor.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${(widget.zoomScale * 100).round()}%',
                                        style: TextStyle(
                                          color: settings.accentColor,
                                          fontSize: AppTypography.bodySmall,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                SizedBox(
                                  width: 78,
                                  child: Text(
                                    widget.isRtl
                                        ? '${l10n.readerProgressPercent(percent)} · RTL'
                                        : l10n.readerProgressPercent(percent),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: AppTypography.bodySmall,
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
                      );
                    }

                    return Material(
                      color: settings.controlSurfaceColor.withValues(
                        alpha: 0.94,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Directionality(
                              textDirection:
                                  widget.isRtl
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                              child: _ComicPageSlider(
                                currentPageIndex: widget.currentPageIndex,
                                totalPages: totalPages,
                                maxPage: maxPage,
                                settings: settings,
                                onPreviewChanged: _handlePreviewChanged,
                                onSeek: widget.onSeek,
                              ),
                            ),
                            SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  _ComicControlButton(
                                    icon: Icons.chevron_left_rounded,
                                    tooltip:
                                        widget.isRtl
                                            ? l10n.readerNextPage
                                            : l10n.readerPreviousPage,
                                    settings: settings,
                                    onPressed:
                                        widget.isRtl
                                            ? widget.onNext
                                            : widget.onPrevious,
                                  ),
                                  Expanded(
                                    child: Text(
                                      totalPages <= 0
                                          ? '0 / 0'
                                          : (!isPreviewing &&
                                                  widget.isDualPage &&
                                                  endIndex > displayPageIndex
                                              ? '${displayPageIndex + 1}–${endIndex + 1} / $totalPages'
                                              : '${displayPageIndex + 1} / $totalPages'),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: settings.onSurfaceColor,
                                        fontSize: AppTypography.bodyMedium,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  _ComicControlButton(
                                    icon: Icons.chevron_right_rounded,
                                    tooltip:
                                        widget.isRtl
                                            ? l10n.readerPreviousPage
                                            : l10n.readerNextPage,
                                    settings: settings,
                                    onPressed:
                                        widget.isRtl
                                            ? widget.onPrevious
                                            : widget.onNext,
                                  ),
                                  _ComicControlButton(
                                    icon: Icons.toc_rounded,
                                    tooltip: l10n.readerTableOfContents,
                                    settings: settings,
                                    onPressed: widget.onShowContents,
                                  ),
                                  if (widget.onSwitchReadingMode != null)
                                    _ComicControlButton(
                                      icon:
                                          widget.isPageMode
                                              ? Icons.swap_vert_rounded
                                              : Icons.swap_horiz_rounded,
                                      tooltip:
                                          widget.isPageMode
                                              ? l10n.readerComicModeScroll
                                              : l10n.readerComicModePage,
                                      settings: settings,
                                      onPressed: widget.onSwitchReadingMode!,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComicPageSlider extends StatefulWidget {
  const _ComicPageSlider({
    required this.currentPageIndex,
    required this.totalPages,
    required this.maxPage,
    required this.settings,
    required this.onSeek,
    this.onPreviewChanged,
  });

  final int currentPageIndex;
  final int totalPages;
  final double maxPage;
  final ReaderViewSettings settings;
  final ValueChanged<int> onSeek;
  final ValueChanged<int?>? onPreviewChanged;

  @override
  State<_ComicPageSlider> createState() => _ComicPageSliderState();
}

class _ComicPageSliderState extends State<_ComicPageSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final trackInactive =
        widget.settings.usesBookDesk
            ? widget.settings.bookDeskTextColor.withValues(alpha: 0.24)
            : widget.settings.onSurfaceColor.withValues(alpha: 0.24);
    return SizedBox(
      height: 28,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          activeTrackColor: widget.settings.accentColor,
          inactiveTrackColor: trackInactive,
          thumbColor: widget.settings.accentColor,
          overlayColor: widget.settings.accentColor.withValues(alpha: 0.18),
          activeTickMarkColor: Colors.transparent,
          inactiveTickMarkColor: Colors.transparent,
        ),
        child: AppSlider(
          value: (_dragValue ?? widget.currentPageIndex.toDouble()).clamp(
            0,
            widget.maxPage,
          ),
          min: 0,
          max: widget.maxPage,
          divisions: widget.totalPages > 1 ? widget.totalPages - 1 : null,
          onChanged:
              widget.totalPages > 1
                  ? (value) {
                    setState(() => _dragValue = value);
                    widget.onPreviewChanged?.call(value.round());
                  }
                  : null,
          onChangeEnd:
              widget.totalPages > 1
                  ? (value) {
                    setState(() => _dragValue = null);
                    widget.onPreviewChanged?.call(null);
                    widget.onSeek(value.round());
                  }
                  : null,
        ),
      ),
    );
  }
}

/// 控件隐藏时显示的低干扰页码。
class ComicPageIndicator extends StatelessWidget {
  const ComicPageIndicator({
    required this.currentPageIndex,
    required this.totalPages,
    this.visible = true,
    this.visibleEndPageIndex,
    super.key,
  });

  final int currentPageIndex;
  final int totalPages;

  /// 页码显隐：与控件条互斥，子树常驻语义树。
  final bool visible;
  final int? visibleEndPageIndex;

  @override
  Widget build(BuildContext context) {
    final endIndex = visibleEndPageIndex ?? currentPageIndex;
    final label =
        totalPages <= 0
            ? '0 / 0'
            : (endIndex > currentPageIndex
                ? '${currentPageIndex + 1}–${endIndex + 1} / $totalPages'
                : '${currentPageIndex + 1} / $totalPages');
    return Positioned(
      bottom: MediaQuery.paddingOf(context).bottom + 10,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
          alwaysIncludeSemantics: true,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
