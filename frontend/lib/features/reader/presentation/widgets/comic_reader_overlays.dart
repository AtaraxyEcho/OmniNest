import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_catalog_tree.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_settings_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_adaptive_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcut_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 漫画阅读器的响应式顶部控制栏。
class ComicReaderTopBar extends StatelessWidget {
  const ComicReaderTopBar({
    required this.catalogTitle,
    required this.isPageMode,
    required this.settings,
    required this.onBack,
    required this.onShowContents,
    required this.onShowSettings,
    required this.onShowShortcuts,
    this.onSwitchReadingMode,
    super.key,
  });

  final String catalogTitle;
  final bool isPageMode;
  final ReaderViewSettings settings;
  final VoidCallback onBack;
  final VoidCallback onShowContents;
  final VoidCallback onShowSettings;
  final VoidCallback onShowShortcuts;
  final VoidCallback? onSwitchReadingMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: settings.controlSurfaceColor.withValues(alpha: 0.94),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = ReaderControlLayout.resolve(
                viewport: Size(
                  constraints.maxWidth,
                  MediaQuery.sizeOf(context).height,
                ),
                fontSize: AppTypography.titleMedium,
              );
              return SizedBox(
                height: 56,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        layout.density == ReaderControlDensity.compact ? 4 : 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: l10n.coreBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: settings.onSurfaceColor,
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          catalogTitle,
                          style: TextStyle(
                            color: settings.onSurfaceColor,
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (layout.density != ReaderControlDensity.compact)
                        _ComicControlButton(
                          icon: Icons.toc_rounded,
                          tooltip: l10n.readerTableOfContents,
                          settings: settings,
                          onPressed: onShowContents,
                        ),
                      if (onSwitchReadingMode != null)
                        _ComicControlButton(
                          icon:
                              isPageMode
                                  ? Icons.swap_vert_rounded
                                  : Icons.swap_horiz_rounded,
                          tooltip:
                              isPageMode
                                  ? l10n.readerComicModeScroll
                                  : l10n.readerComicModePage,
                          settings: settings,
                          onPressed: onSwitchReadingMode!,
                        ),
                      if (layout.density != ReaderControlDensity.compact)
                        _ComicControlButton(
                          icon: Icons.tune_rounded,
                          tooltip: l10n.readerSettingsTitle,
                          settings: settings,
                          onPressed: onShowSettings,
                        ),
                      if (layout.density == ReaderControlDensity.expanded)
                        _ComicControlButton(
                          icon: Icons.keyboard_rounded,
                          tooltip: l10n.readerShortcutsTitle,
                          settings: settings,
                          onPressed: onShowShortcuts,
                        ),
                      if (layout.density == ReaderControlDensity.compact)
                        PopupMenuButton<_ComicTopAction>(
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).moreButtonTooltip,
                          color: settings.controlSurfaceColor,
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: settings.onSurfaceVariantColor,
                          ),
                          onSelected: (action) {
                            switch (action) {
                              case _ComicTopAction.contents:
                                onShowContents();
                                return;
                              case _ComicTopAction.settings:
                                onShowSettings();
                                return;
                              case _ComicTopAction.shortcuts:
                                onShowShortcuts();
                                return;
                            }
                          },
                          itemBuilder:
                              (context) => [
                                _menuItem(
                                  _ComicTopAction.contents,
                                  Icons.toc_rounded,
                                  l10n.readerTableOfContents,
                                ),
                                _menuItem(
                                  _ComicTopAction.settings,
                                  Icons.tune_rounded,
                                  l10n.readerSettingsTitle,
                                ),
                                _menuItem(
                                  _ComicTopAction.shortcuts,
                                  Icons.keyboard_rounded,
                                  l10n.readerShortcutsTitle,
                                ),
                              ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_ComicTopAction> _menuItem(
    _ComicTopAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: settings.onSurfaceVariantColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: settings.onSurfaceColor),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ComicTopAction { contents, settings, shortcuts }

/// 漫画阅读器的响应式底部翻页与进度控制栏。
class ComicReaderBottomBar extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxPage = totalPages <= 1 ? 1.0 : (totalPages - 1).toDouble();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: settings.controlSurfaceColor.withValues(alpha: 0.94),
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
              final compact = layout.density == ReaderControlDensity.compact;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 6 : 16,
                  0,
                  compact ? 6 : 16,
                  4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ComicPageSlider(
                      currentPageIndex: currentPageIndex,
                      totalPages: totalPages,
                      maxPage: maxPage,
                      settings: settings,
                      onSeek: onSeek,
                    ),
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          _ComicControlButton(
                            icon: Icons.chevron_left_rounded,
                            tooltip: l10n.readerPreviousPage,
                            settings: settings,
                            onPressed: onPrevious,
                          ),
                          Expanded(
                            child: Text(
                              totalPages <= 0
                                  ? '0 / 0'
                                  : '${currentPageIndex + 1} / $totalPages',
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
                            tooltip: l10n.readerNextPage,
                            settings: settings,
                            onPressed: onNext,
                          ),
                          _ComicControlButton(
                            icon: Icons.toc_rounded,
                            tooltip: l10n.readerTableOfContents,
                            settings: settings,
                            onPressed: onShowContents,
                          ),
                          if (!compact && onSwitchReadingMode != null)
                            _ComicControlButton(
                              icon:
                                  isPageMode
                                      ? Icons.swap_vert_rounded
                                      : Icons.swap_horiz_rounded,
                              tooltip:
                                  isPageMode
                                      ? l10n.readerComicModeScroll
                                      : l10n.readerComicModePage,
                              settings: settings,
                              onPressed: onSwitchReadingMode!,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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
  });

  final int currentPageIndex;
  final int totalPages;
  final double maxPage;
  final ReaderViewSettings settings;
  final ValueChanged<int> onSeek;

  @override
  State<_ComicPageSlider> createState() => _ComicPageSliderState();
}

class _ComicPageSliderState extends State<_ComicPageSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          activeTrackColor: widget.settings.accentColor,
          inactiveTrackColor: widget.settings.onSurfaceColor.withValues(
            alpha: 0.18,
          ),
          thumbColor: widget.settings.accentColor,
          overlayColor: widget.settings.accentColor.withValues(alpha: 0.18),
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
                  ? (value) => setState(() => _dragValue = value)
                  : null,
          onChangeEnd:
              widget.totalPages > 1
                  ? (value) {
                    setState(() => _dragValue = null);
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
    super.key,
  });

  final int currentPageIndex;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.paddingOf(context).bottom + 10,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                totalPages <= 0
                    ? '0 / 0'
                    : '${currentPageIndex + 1} / $totalPages',
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
    );
  }
}

/// 漫画阅读器目录内容，由外层自适应面板提供标题和关闭操作。
class ComicCatalogPanel extends StatelessWidget {
  const ComicCatalogPanel({
    required this.manifest,
    required this.currentPageIndex,
    required this.settings,
    required this.onNodeTap,
    super.key,
  });

  final ComicManifest manifest;
  final int currentPageIndex;
  final ReaderViewSettings settings;
  final ValueChanged<ComicCatalogNode> onNodeTap;

  @override
  Widget build(BuildContext context) {
    final hasCurrentPage =
        manifest.pages.isNotEmpty && currentPageIndex < manifest.pages.length;
    final currentNodeId =
        hasCurrentPage ? manifest.pages[currentPageIndex].catalogNodeId : null;
    final currentPageId =
        hasCurrentPage ? manifest.pages[currentPageIndex].id : null;
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(
          surface: settings.controlSurfaceColor,
          onSurface: settings.onSurfaceColor,
          onSurfaceVariant: settings.onSurfaceVariantColor,
          primary: settings.accentColor,
        ),
      ),
      child: ComicCatalogTree(
        nodes: manifest.catalog,
        currentNodeId: currentNodeId,
        currentPageId: currentPageId,
        pages: manifest.pages,
        sources: manifest.sources,
        onNodeTap: onNodeTap,
      ),
    );
  }
}

class _ComicControlButton extends StatelessWidget {
  const _ComicControlButton({
    required this.icon,
    required this.tooltip,
    required this.settings,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final ReaderViewSettings settings;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      color: settings.onSurfaceColor,
      disabledColor: settings.onSurfaceVariantColor.withValues(alpha: 0.45),
      icon: Icon(icon, size: 22),
    );
  }
}

/// 漫画阅读器面板浮层：按当前激活面板类型组装目录/设置/快捷键内容。
class ComicReaderPanelOverlay extends StatelessWidget {
  const ComicReaderPanelOverlay({
    required this.active,
    required this.layout,
    required this.settings,
    required this.manifest,
    required this.currentPageIndex,
    required this.displaySettings,
    required this.volumeKeyPaging,
    required this.onClose,
    required this.onCatalogNodeTap,
    required this.onDisplaySettingsChanged,
    required this.onVolumeKeyPagingChanged,
    super.key,
  });

  final ReaderPanelType active;
  final ReaderControlLayout layout;
  final ReaderViewSettings settings;
  final ComicManifest manifest;
  final int currentPageIndex;
  final ComicReaderDisplaySettings displaySettings;
  final bool volumeKeyPaging;
  final VoidCallback onClose;
  final ValueChanged<ComicCatalogNode> onCatalogNodeTap;
  final ValueChanged<ComicReaderDisplaySettings> onDisplaySettingsChanged;
  final ValueChanged<bool> onVolumeKeyPagingChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (active) {
      ReaderPanelType.contents => l10n.readerTableOfContents,
      ReaderPanelType.settings => l10n.readerSettingsTitle,
      _ => l10n.readerShortcutsTitle,
    };
    final child = switch (active) {
      ReaderPanelType.contents => ComicCatalogPanel(
        manifest: manifest,
        currentPageIndex: currentPageIndex,
        settings: settings,
        onNodeTap: onCatalogNodeTap,
      ),
      ReaderPanelType.settings => ComicReaderSettingsPanel(
        displaySettings: displaySettings,
        themeSettings: settings,
        onChanged: onDisplaySettingsChanged,
        volumeKeyPaging: volumeKeyPaging,
        onVolumeKeyPagingChanged: onVolumeKeyPagingChanged,
      ),
      _ => ReaderShortcutPanel(settings: settings, isComic: true),
    };
    return ReaderAdaptivePanelOverlay(
      title: title,
      settings: settings,
      layout: layout,
      onClose: onClose,
      child: child,
    );
  }
}
