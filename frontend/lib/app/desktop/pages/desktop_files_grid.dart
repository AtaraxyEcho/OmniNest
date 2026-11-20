part of 'desktop_files_page.dart';

class _FileGrid extends StatelessWidget {
  const _FileGrid({
    required this.items,
    required this.selected,
    required this.onTap,
    required this.onSelect,
    required this.onMenu,
    this.onFavorite,
    this.onShare,
  });

  final List<FileNode> items;
  final Set<String> selected;
  final ValueChanged<FileNode> onTap;
  final ValueChanged<FileNode> onSelect;
  final void Function(FileNode node, Offset position) onMenu;
  final ValueChanged<FileNode>? onFavorite;
  final ValueChanged<FileNode>? onShare;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // `extra.css:88` 终值：repeat(auto-fill,minmax(168px,1fr))，gap 12px。
        final columns = ((constraints.maxWidth + 12) / (168 + 12))
            .floor()
            .clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _FileTile(
                    node: items[i],
                    selected: selected.contains(items[i].id),
                    onTap: () => onSelect(items[i]),
                    onOpen: () => onTap(items[i]),
                    onMenu: (position) => onMenu(items[i], position),
                    onToggleSelect: () => onSelect(items[i]),
                    onFavorite:
                        onFavorite == null ? null : () => onFavorite!(items[i]),
                    onShare: onShare == null ? null : () => onShare!(items[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FileGridSkeleton extends StatelessWidget {
  const _FileGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + 12) / (168 + 12))
            .floor()
            .clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 18,
          children: [
            for (var i = 0; i < columns * 2; i++)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopSkeletonBox(height: 128, radius: 12, index: i * 3),
                    const SizedBox(height: 10),
                    FractionallySizedBox(
                      widthFactor: 0.72,
                      child: DesktopSkeletonBox(
                        height: 11,
                        radius: 5.5,
                        index: i * 3 + 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.42,
                      child: DesktopSkeletonBox(
                        height: 9,
                        radius: 4.5,
                        index: i * 3 + 2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.node,
    required this.selected,
    required this.onTap,
    required this.onOpen,
    required this.onMenu,
    this.onToggleSelect,
    this.onFavorite,
    this.onShare,
  });

  final FileNode node;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onFavorite;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            onDoubleTap: onOpen,
            onSecondaryTapDown: (details) => onMenu(details.globalPosition),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: DesktopMotion.of(context, DesktopMotion.fast),
              curve: DesktopMotion.ease,
              transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
              constraints: const BoxConstraints(minHeight: 176),
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
              decoration: BoxDecoration(
                // 样例 `.f-body.grid .f-row`：raise 底、悬停 raise2 并上浮。
                color:
                    selected
                        ? skin.accentWash(0.13)
                        : hovered
                        ? skin.raise2
                        : skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                border: Border.all(
                  color: selected ? skin.accentWash(0.35) : skin.line,
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color:
                              _hasFileThumbnail(node)
                                  ? Colors.transparent
                                  : _fileTone(
                                    node,
                                    skin,
                                  ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        clipBehavior: Clip.antiAlias,
                        child:
                            _hasFileThumbnail(node)
                                ? FileThumbnail(
                                  file: node,
                                  size: 84,
                                  borderRadius: BorderRadius.circular(18),
                                  zoomOnHover: true,
                                )
                                : Icon(
                                  _fileIcon(node),
                                  size: 36,
                                  color: _fileTone(node, skin),
                                ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: DesktopType.rowTitle(
                                selected ? skin.accent : skin.text,
                              ),
                            ),
                          ),
                          if (node.favorited) ...[
                            const SizedBox(width: 5),
                            Icon(
                              DesktopIcons.starFilled,
                              size: 11,
                              color: skin.warm,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fileSubtitle(l10n, node),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ),
                  if (onToggleSelect != null)
                    Positioned(
                      key: const ValueKey<String>('files-grid-tick'),
                      left: -6,
                      top: -8,
                      child: AnimatedOpacity(
                        duration: DesktopMotion.of(context, DesktopMotion.fast),
                        opacity: hovered || selected ? 1 : 0,
                        child: GestureDetector(
                          onTap: onToggleSelect,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: _SelectionTick(selected: selected),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    key: const ValueKey<String>('files-grid-actions'),
                    right: -6,
                    top: -8,
                    child: AnimatedOpacity(
                      duration: DesktopMotion.of(context, DesktopMotion.fast),
                      opacity: hovered || selected ? 1 : 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onFavorite != null)
                            DesktopIconButton(
                              icon:
                                  node.favorited
                                      ? DesktopIcons.starFilled
                                      : DesktopIcons.star,
                              size: 24,
                              iconSize: 14,
                              color: node.favorited ? skin.warm : skin.text2,
                              tooltip:
                                  node.favorited
                                      ? l10n.filesRemoveFavorite
                                      : l10n.filesAddFavorite,
                              onPressed: onFavorite,
                            ),
                          if (onShare != null)
                            DesktopIconButton(
                              icon: DesktopIcons.share,
                              size: 24,
                              iconSize: 14,
                              tooltip: l10n.filesShare,
                              onPressed: onShare,
                            ),
                          Builder(
                            builder:
                                (buttonContext) => DesktopIconButton(
                                  icon: DesktopIcons.more,
                                  size: 24,
                                  iconSize: 14,
                                  tooltip: l10n.filesOpenFileMenu,
                                  onPressed: () {
                                    final box =
                                        buttonContext.findRenderObject()
                                            as RenderBox?;
                                    final origin =
                                        box == null
                                            ? Offset.zero
                                            : box.localToGlobal(
                                              Offset(0, box.size.height),
                                            );
                                    onMenu(origin);
                                  },
                                ),
                          ),
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
}
