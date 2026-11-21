part of 'comic_reader_overlays.dart';

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
    final inDarkGlass = ReaderPanelSurfaceScope.isDarkGlass(context);

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(
          surface:
              inDarkGlass
                  ? ReaderReadingPalette.desktopPopoverGlass
                  : settings.controlSurfaceColor,
          onSurface:
              inDarkGlass
                  ? ReaderReadingPalette.desktopPopoverOnSurface
                  : settings.onSurfaceColor,
          onSurfaceVariant:
              inDarkGlass
                  ? ReaderReadingPalette.desktopPopoverMuted
                  : settings.onSurfaceVariantColor,
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

/// 漫画书签列表抽屉内容。
class ComicBookmarksPanel extends StatelessWidget {
  const ComicBookmarksPanel({
    required this.bookmarks,
    required this.currentPageIndex,
    required this.totalPages,
    required this.settings,
    required this.onBookmarkTap,
    required this.onBookmarkDelete,
    super.key,
  });

  final List<ReaderBookmark> bookmarks;
  final int currentPageIndex;
  final int totalPages;
  final ReaderViewSettings settings;
  final ValueChanged<ReaderBookmark> onBookmarkTap;
  final ValueChanged<ReaderBookmark> onBookmarkDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inDarkGlass = ReaderPanelSurfaceScope.isDarkGlass(context);
    final fg =
        inDarkGlass
            ? ReaderReadingPalette.desktopPopoverOnSurface
            : settings.onSurfaceColor;
    final muted =
        inDarkGlass
            ? ReaderReadingPalette.desktopPopoverMuted
            : settings.onSurfaceVariantColor;

    if (bookmarks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 32,
                color: muted.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.readerBookmarksTab(0),
                style: TextStyle(
                  color: muted,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bookmarks.length,
      separatorBuilder:
          (_, _) => Divider(height: 1, color: fg.withValues(alpha: 0.08)),
      itemBuilder: (context, index) {
        final bm = bookmarks[index];
        final pageNumber = bm.charOffset + 1;
        final isCurrent = bm.charOffset == currentPageIndex;
        final title =
            (bm.note?.trim().isNotEmpty == true)
                ? bm.note!.trim()
                : (totalPages > 0
                    ? l10n.readerPageOf(pageNumber, totalPages)
                    : l10n.readerBookmarkFallback(pageNumber));
        final percent = (bm.progressPercent.clamp(0.0, 1.0) * 100).round();
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 2,
          ),
          leading: Icon(
            isCurrent ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
            size: 18,
            color: isCurrent ? settings.accentColor : muted,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? settings.accentColor : fg,
              fontSize: AppTypography.bodyMedium,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          subtitle: Text(
            '${l10n.readerPageNumber(pageNumber)} · ${l10n.readerProgressPercent(percent)}',
            style: TextStyle(
              color: muted,
              fontSize: AppTypography.bodySmall,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          trailing: IconButton(
            tooltip: l10n.readerRemoveBookmark,
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: muted),
            onPressed: () => onBookmarkDelete(bm),
          ),
          onTap: () => onBookmarkTap(bm),
        );
      },
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

/// 漫画阅读器面板浮层：桌面端复用统一磨砂抽屉 `DesktopReaderPopover`（保持顶栏可见支持一键切换），
/// 窄屏回退 `ReaderAdaptivePanelOverlay`。
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
    this.bookmarks = const [],
    this.onBookmarkTap,
    this.onBookmarkDelete,
    this.effectiveRtl,
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
  final List<ReaderBookmark> bookmarks;
  final ValueChanged<ReaderBookmark>? onBookmarkTap;
  final ValueChanged<ReaderBookmark>? onBookmarkDelete;
  final bool? effectiveRtl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (active) {
      ReaderPanelType.contents => l10n.readerTableOfContents,
      ReaderPanelType.annotations => l10n.readerBookmarksTab(bookmarks.length),
      ReaderPanelType.settings => l10n.readerSettingsTitle,
      _ => l10n.readerShortcutsTitle,
    };
    final child = switch (active) {
      ReaderPanelType.contents => ComicCatalogPanel(
        key: const ValueKey('comic-panel-contents'),
        manifest: manifest,
        currentPageIndex: currentPageIndex,
        settings: settings,
        onNodeTap: onCatalogNodeTap,
      ),
      ReaderPanelType.annotations => ComicBookmarksPanel(
        key: const ValueKey('comic-panel-bookmarks'),
        bookmarks: bookmarks,
        currentPageIndex: currentPageIndex,
        totalPages: manifest.totalPages,
        settings: settings,
        onBookmarkTap: onBookmarkTap ?? (_) {},
        onBookmarkDelete: onBookmarkDelete ?? (_) {},
      ),
      ReaderPanelType.settings => ComicReaderSettingsPanel(
        key: const ValueKey('comic-panel-settings'),
        displaySettings: displaySettings,
        themeSettings: settings,
        onChanged: onDisplaySettingsChanged,
        volumeKeyPaging: volumeKeyPaging,
        onVolumeKeyPagingChanged: onVolumeKeyPagingChanged,
        effectiveRtl: effectiveRtl,
        mobile: shouldUseResponsiveMobileShell(
          mobilePlatform: isMobilePlatform,
          width: MediaQuery.sizeOf(context).width,
        ),
      ),
      _ => ReaderShortcutPanel(
        key: const ValueKey('comic-panel-shortcuts'),
        settings: settings,
        isComic: true,
      ),
    };

    if (layout.density != ReaderControlDensity.compact) {
      final width = switch (active) {
        ReaderPanelType.contents => 340.0,
        ReaderPanelType.annotations => 340.0,
        ReaderPanelType.settings => 340.0,
        _ => 380.0,
      };
      return DesktopReaderPopover(
        width: width,
        eyebrow: title,
        onDismissOutside: onClose,
        child: child,
      );
    }

    return ReaderAdaptivePanelOverlay(
      title: title,
      settings: settings,
      layout: layout,
      onClose: onClose,
      child: child,
    );
  }
}
