part of 'comic_reader_overlays.dart';

/// 漫画阅读器的统一响应式顶部控制栏。
///
/// 桌面端对齐统一 `.bk-top` 64px 样式（隐藏搜索，展示正确漫画书名 `bookTitle`、
/// 页码副标题、`Book / Swipe / Scroll` 三模式胶囊、目录、书签切换、书签列表计数角标与设置）；
/// 展开右侧 `DesktopReaderPopover` 抽屉时顶栏保持可见支持一键切换面板。
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
    this.visible = true,
    this.bookTitle,
    this.pageSubtitle,
    this.readingMode,
    this.onSelectReadingMode,
    this.isBookmarked = false,
    this.bookmarkCount = 0,
    this.onToggleBookmark,
    this.onShowBookmarks,
    this.activePanel,
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

  /// 控件条显隐：子树常驻语义树，隐藏时仅淡出并屏蔽指针。
  final bool visible;

  /// 漫画正式书名（`item.title`）；缺省时回退 `catalogTitle`。
  final String? bookTitle;

  /// 页码副标题（如 `Page 3 of 42` 或 `Pages 4–5 of 42`）。
  final String? pageSubtitle;

  /// 当前阅读模式键：`book` / `page` / `scroll`。
  final String? readingMode;

  /// 统一三模式切换回调（桌面端优先显示 `Book / Swipe / Scroll` 胶囊）。
  final ValueChanged<String>? onSelectReadingMode;

  /// 当前页是否已加书签。
  final bool isBookmarked;

  /// 漫画书签总数（用于书签列表按钮角标）。
  final int bookmarkCount;

  /// 当前页一键添加/取消书签。
  final VoidCallback? onToggleBookmark;

  /// 打开漫画书签列表抽屉。
  final VoidCallback? onShowBookmarks;

  /// 当前激活的右侧抽屉类型（用于高亮对应顶栏图标）。
  final ReaderPanelType? activePanel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resolvedTitle =
        (bookTitle?.trim().isNotEmpty == true)
            ? bookTitle!.trim()
            : catalogTitle;
    final effectiveMode = readingMode ?? (isPageMode ? 'page' : 'scroll');
    final bookMode = effectiveMode == 'book' || settings.usesBookDesk;
    final foreground =
        bookMode ? settings.bookDeskTextColor : settings.onSurfaceColor;
    final muted =
        bookMode
            ? settings.bookDeskTextColor.withValues(alpha: 0.62)
            : settings.onSurfaceVariantColor;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
          alwaysIncludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient:
                  bookMode
                      ? null
                      : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          settings.surfaceColor.withValues(alpha: 0.96),
                          settings.surfaceColor.withValues(alpha: 0),
                        ],
                        stops: const [0.7, 1],
                      ),
            ),
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
                  final compact =
                      layout.density == ReaderControlDensity.compact;
                  final iconOnlyModes = constraints.maxWidth < 960;

                  return SizedBox(
                    height: 64,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 20,
                      ),
                      child: Row(
                        children: [
                          _ComicDesktopIconButton(
                            icon: Icons.chevron_left_rounded,
                            tooltip: l10n.coreBack,
                            foreground: foreground,
                            accent: settings.accentColor,
                            bookMode: bookMode,
                            large: true,
                            onPressed: onBack,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DesktopWindowDragRegion(
                              child: SizedBox(
                                height: 64,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: iconOnlyModes ? 200 : 320,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          resolvedTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: foreground,
                                            fontFamily:
                                                AppTypography.serifFamily,
                                            fontFamilyFallback:
                                                AppTypography
                                                    .serifFamilyFallback,
                                            fontSize:
                                                17, // ignore: font_size_whitelist
                                            fontWeight: FontWeight.w400,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (pageSubtitle != null &&
                                            pageSubtitle!.isNotEmpty)
                                          Text(
                                            pageSubtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: muted,
                                              fontSize:
                                                  12, // ignore: font_size_whitelist
                                              height: 1.3,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!compact && onSelectReadingMode != null) ...[
                            _ComicModeCapsule(
                              mode: effectiveMode,
                              foreground: foreground,
                              bookMode: bookMode,
                              iconOnly: iconOnlyModes,
                              onSelected: onSelectReadingMode!,
                            ),
                            const SizedBox(width: 10),
                          ] else if (onSwitchReadingMode != null) ...[
                            _ComicDesktopIconButton(
                              icon:
                                  isPageMode
                                      ? Icons.swap_vert_rounded
                                      : Icons.swap_horiz_rounded,
                              tooltip:
                                  isPageMode
                                      ? l10n.readerComicModeScroll
                                      : l10n.readerComicModePage,
                              foreground: foreground,
                              accent: settings.accentColor,
                              bookMode: bookMode,
                              onPressed: onSwitchReadingMode,
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (!compact) ...[
                            _ComicDesktopIconButton(
                              icon: Icons.toc_rounded,
                              tooltip: '${l10n.readerTableOfContents} (T)',
                              foreground: foreground,
                              accent: settings.accentColor,
                              bookMode: bookMode,
                              selected: activePanel == ReaderPanelType.contents,
                              onPressed: onShowContents,
                            ),
                            if (onToggleBookmark != null) ...[
                              const SizedBox(width: 4),
                              _ComicDesktopIconButton(
                                icon:
                                    isBookmarked
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                tooltip:
                                    isBookmarked
                                        ? l10n.readerRemoveBookmark
                                        : l10n.readerAddBookmark,
                                foreground: foreground,
                                accent: settings.accentColor,
                                bookMode: bookMode,
                                selected: isBookmarked,
                                onPressed: onToggleBookmark,
                              ),
                            ],
                            if (onShowBookmarks != null) ...[
                              const SizedBox(width: 4),
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _ComicDesktopIconButton(
                                    icon: Icons.bookmarks_outlined,
                                    tooltip: l10n.readerBookmarksTab(
                                      bookmarkCount,
                                    ),
                                    foreground: foreground,
                                    accent: settings.accentColor,
                                    bookMode: bookMode,
                                    selected:
                                        activePanel ==
                                        ReaderPanelType.annotations,
                                    onPressed: onShowBookmarks,
                                  ),
                                  if (bookmarkCount > 0)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: IgnorePointer(
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minWidth: 16,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: settings.accentColor,
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                          child: Text(
                                            bookmarkCount > 99
                                                ? '99+'
                                                : '$bookmarkCount',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color:
                                                  ReaderReadingPalette
                                                      .onAccentInk,
                                              fontSize:
                                                  10, // ignore: font_size_whitelist
                                              fontWeight: FontWeight.w700,
                                              height: 1.15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(width: 4),
                            _ComicDesktopIconButton(
                              icon: Icons.tune_rounded,
                              tooltip: l10n.readerSettingsTitle,
                              foreground: foreground,
                              accent: settings.accentColor,
                              bookMode: bookMode,
                              selected: activePanel == ReaderPanelType.settings,
                              onPressed: onShowSettings,
                            ),
                            if (layout.density ==
                                    ReaderControlDensity.expanded &&
                                PlatformCapabilities.current()
                                    .supportsPhysicalKeyboard) ...[
                              const SizedBox(width: 4),
                              _ComicDesktopIconButton(
                                icon: Icons.keyboard_rounded,
                                tooltip: l10n.readerShortcutsTitle,
                                foreground: foreground,
                                accent: settings.accentColor,
                                bookMode: bookMode,
                                selected:
                                    activePanel == ReaderPanelType.shortcuts,
                                onPressed: onShowShortcuts,
                              ),
                            ],
                          ],
                          if (compact)
                            PopupMenuButton<_ComicTopAction>(
                              tooltip:
                                  MaterialLocalizations.of(
                                    context,
                                  ).moreButtonTooltip,
                              color: settings.controlSurfaceColor,
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: foreground,
                              ),
                              onSelected: (action) {
                                switch (action) {
                                  case _ComicTopAction.contents:
                                    onShowContents();
                                    return;
                                  case _ComicTopAction.bookmark:
                                    onToggleBookmark?.call();
                                    return;
                                  case _ComicTopAction.bookmarks:
                                    onShowBookmarks?.call();
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
                                    if (onToggleBookmark != null)
                                      _menuItem(
                                        _ComicTopAction.bookmark,
                                        isBookmarked
                                            ? Icons.bookmark_rounded
                                            : Icons.bookmark_border_rounded,
                                        isBookmarked
                                            ? l10n.readerRemoveBookmark
                                            : l10n.readerAddBookmark,
                                      ),
                                    if (onShowBookmarks != null)
                                      _menuItem(
                                        _ComicTopAction.bookmarks,
                                        Icons.bookmarks_outlined,
                                        l10n.readerBookmarksTab(bookmarkCount),
                                      ),
                                    _menuItem(
                                      _ComicTopAction.settings,
                                      Icons.tune_rounded,
                                      l10n.readerSettingsTitle,
                                    ),
                                    if (PlatformCapabilities.current()
                                        .supportsPhysicalKeyboard)
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

enum _ComicTopAction { contents, bookmark, bookmarks, settings, shortcuts }

/// 统一三模式滑动胶囊（Book / Swipe / Scroll）。
class _ComicModeCapsule extends StatelessWidget {
  const _ComicModeCapsule({
    required this.mode,
    required this.foreground,
    required this.bookMode,
    required this.iconOnly,
    required this.onSelected,
  });

  final String mode;
  final Color foreground;
  final bool bookMode;
  final bool iconOnly;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final background =
        bookMode
            ? Colors.white.withValues(alpha: 0.08)
            : foreground.withValues(alpha: 0.08);
    final line =
        bookMode
            ? Colors.white.withValues(alpha: 0.12)
            : foreground.withValues(alpha: 0.12);
    final activeBg =
        bookMode
            ? Colors.white.withValues(alpha: 0.20)
            : foreground.withValues(alpha: 0.14);
    final options = [
      ('book', l10n.readerModeBook, Icons.auto_stories_outlined),
      ('page', l10n.readerModeSwipe, Icons.swap_horiz_rounded),
      ('scroll', l10n.readerModeScroll, Icons.view_stream_outlined),
    ];
    final activeIndex = mode == 'scroll' ? 2 : (mode == 'page' ? 1 : 0);
    final tabWidth = iconOnly ? 34.0 : 72.0;
    final slideDur = MotionToken.reduced(
      context,
      const Duration(milliseconds: 220),
    );

    return AnimatedContainer(
      duration: slideDur,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: SizedBox(
        width: tabWidth * options.length,
        height: 28,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: slideDur,
              curve: const Cubic(0.22, 1.0, 0.36, 1.0),
              left: activeIndex * tabWidth,
              top: 0,
              bottom: 0,
              width: tabWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: activeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Row(
              children: [
                for (final (id, label, icon) in options)
                  SizedBox(
                    width: tabWidth,
                    child: Tooltip(
                      message: label,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => onSelected(id),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            height: 28,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  icon,
                                  size: 14,
                                  color:
                                      mode == id
                                          ? foreground
                                          : foreground.withValues(alpha: 0.65),
                                ),
                                if (!iconOnly) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color:
                                          mode == id
                                              ? foreground
                                              : foreground.withValues(
                                                alpha: 0.65,
                                              ),
                                      fontSize:
                                          12.5, // ignore: font_size_whitelist
                                      fontWeight:
                                          mode == id
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicDesktopIconButton extends StatefulWidget {
  const _ComicDesktopIconButton({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    required this.accent,
    required this.bookMode,
    required this.onPressed,
    this.selected = false,
    this.large = false,
  });

  final IconData icon;
  final String tooltip;
  final Color foreground;
  final Color accent;
  final bool bookMode;
  final VoidCallback? onPressed;
  final bool selected;
  final bool large;

  @override
  State<_ComicDesktopIconButton> createState() =>
      _ComicDesktopIconButtonState();
}

class _ComicDesktopIconButtonState extends State<_ComicDesktopIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final hoverBg =
        widget.bookMode
            ? Colors.white.withValues(alpha: 0.12)
            : widget.foreground.withValues(alpha: 0.10);
    final selectedBg =
        widget.bookMode
            ? widget.accent.withValues(alpha: 0.18)
            : widget.accent.withValues(alpha: 0.14);
    final bg =
        !enabled
            ? Colors.transparent
            : widget.selected
            ? selectedBg
            : _hovered
            ? hoverBg
            : Colors.transparent;
    final fg =
        !enabled
            ? widget.foreground.withValues(alpha: 0.35)
            : widget.selected
            ? widget.accent
            : _hovered
            ? widget.foreground
            : widget.foreground.withValues(alpha: 0.84);
    final side = widget.large ? 40.0 : 34.0;
    final radius = widget.large ? 12.0 : 9.0;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.resolve(context, MotionToken.fast),
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Center(
                child: Icon(
                  widget.icon,
                  size: widget.large ? 22 : 18,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
