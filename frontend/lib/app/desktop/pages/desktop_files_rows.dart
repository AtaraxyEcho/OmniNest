part of 'desktop_files_page.dart';

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.node,
    required this.selected,
    required this.recycle,
    required this.onTap,
    required this.onOpen,
    required this.onMenu,
    this.onFavorite,
    this.onShare,
    this.dragIds = const <String>[],
    this.onDropFiles,
    this.hoveredAsDropTarget = false,
    super.key,
  });

  final FileNode node;
  final bool selected;
  final bool recycle;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;

  /// 行内星标与分享（样例 `.ra` 的 star/share 两个按钮）；回收站等只读分区为空。
  final VoidCallback? onFavorite;
  final VoidCallback? onShare;

  /// 拖动本行时携带的 id 集：选中态拖整组，否则只拖这一行。
  /// 空集表示本行不可拖（回收站等只读分区）。
  final List<String> dragIds;

  /// 落到本行时接收 id 集；只有文件夹行给值（样例 `.f-row` 的 dropProps 同此）。
  final ValueChanged<List<String>>? onDropFiles;

  /// 外部（系统文件）拖入时指针停在本行上；内部拖拽由 `DragTarget` 自己给。
  final bool hoveredAsDropTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);

    /// [highlighted] 来自外层 `DragTarget`：拖拽悬停在本行时按 `.f-row.drop`
    /// 换成 accent 24% 底 + 2px 实描边。描边走 `foregroundDecoration`，
    /// 免得 2px 边宽把固定 58 高的内容挤掉一截。
    Widget buildRow({required bool highlighted}) => AnimatedScale(
      // 样例 `.f-row.drop{transform:scale(1.01)}`：落点行轻微放大。
      scale: highlighted ? 1.01 : 1,
      duration: DesktopMotion.of(context, DesktopMotion.fast),
      curve: DesktopMotion.ease,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              onDoubleTap: onOpen,
              onSecondaryTapDown: (details) => onMenu(details.globalPosition),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                height: 58,
                // 描边占 1px，内距用 11 补回，内容起点与表头的 12 对齐。
                padding: const EdgeInsets.symmetric(horizontal: 11),
                foregroundDecoration:
                    highlighted
                        ? BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radius,
                          ),
                          border: Border.all(color: skin.accent, width: 2),
                        )
                        : selected
                        ? BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radius,
                          ),
                          border: Border.all(color: skin.accentWash(0.35)),
                        )
                        : null,
                decoration: BoxDecoration(
                  // 样例 `.f-row.sel`：accent 14% 底 + 1px accent 35% 描边；
                  // `.f-row.drop` 是 24% 底 + 2px 实描边（走 foregroundDecoration）。
                  // 样例 `extra.css:74`（终值，压过 desktop.css 的 14%）：
                  // 选中 13% 底 + 1px accent 35% 描边。
                  color:
                      highlighted
                          ? skin.accentWash(0.24)
                          : selected
                          ? skin.accentWash(0.13)
                          : hovered
                          ? skin.raise
                          : Colors.transparent,
                  // 样例 `desktop.css:458`：文件行圆角 12。
                  borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                  border: Border.all(
                    color:
                        selected
                            ? skin.accentWash(0.35)
                            : hovered
                            ? skin.line
                            : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _FileColumns.tick,
                      child: Center(child: _SelectionTick(selected: selected)),
                    ),
                    const SizedBox(width: _FileColumns.gap),
                    SizedBox(
                      width: _FileColumns.icon,
                      child: Center(child: _FileIconPlate(node: node)),
                    ),
                    const SizedBox(width: _FileColumns.gap),
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  node.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.rowTitle(
                                    selected ? skin.accent : skin.text,
                                  ),
                                ),
                              ),
                              if (node.favorited) ...[
                                const SizedBox(width: 6),
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
                            style: DesktopType.caption(skin.text3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: _FileColumns.gap),
                    SizedBox(
                      width: _FileColumns.modified,
                      child: Text(
                        _formatModified(context, node.updatedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.numeric(skin.text3),
                      ),
                    ),
                    const SizedBox(width: _FileColumns.gap),
                    SizedBox(
                      width: _FileColumns.size,
                      child: Text(
                        node.isFolder ? '—' : formatFileSize(node.sizeBytes),
                        textAlign: TextAlign.right,
                        style: DesktopType.numeric(skin.text3),
                      ),
                    ),
                    const SizedBox(width: _FileColumns.gap),
                    SizedBox(
                      width: _FileColumns.access,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _AccessTag(
                          label:
                              recycle
                                  ? l10n.desktopFilesRecycle
                                  : node.spaceType == SpaceType.shared
                                  ? node.uploaderName?.trim().isNotEmpty == true
                                      ? node.uploaderName!.trim()
                                      : l10n.desktopFilesSharedBadge
                                  : l10n.desktopFilesPrivate,
                          // 共享空间的 Access 列对应原型中的成员标签；共享链接
                          // 仍由后端的共享信息使用强调色，这里不把空间位置误当链接。
                          accent: false,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _FileColumns.actions,
                      // 样例 `.ra{opacity:0}`：行内动作平时不显示，悬停或选中
                      // 才浮现；控件仍在原位可点，不引起列宽跳动。
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedOpacity(
                          duration: DesktopMotion.of(
                            context,
                            DesktopMotion.fast,
                          ),
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
                                  color:
                                      node.favorited ? skin.warm : skin.text2,
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
                                      size: 26,
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
                    ),
                  ],
                ),
              ),
            ),
      ),
    );

    // 样例 `.drop-veil` 之外的两件事：被拖的行半透明（`.f-row.dragging`），
    // 悬停可接收的文件夹行高亮（`.f-row.drop`）。
    var row =
        onDropFiles == null
            ? buildRow(highlighted: hoveredAsDropTarget)
            : DragTarget<List<String>>(
              onWillAcceptWithDetails:
                  (details) =>
                      details.data.isNotEmpty &&
                      !details.data.contains(node.id),
              onAcceptWithDetails: (details) => onDropFiles!(details.data),
              builder:
                  (context, candidate, rejected) => buildRow(
                    highlighted: candidate.isNotEmpty || hoveredAsDropTarget,
                  ),
            );
    if (dragIds.isEmpty) {
      return row;
    }
    return _AdaptiveFileDraggable(
      data: dragIds,
      feedback: _RowDragGhost(node: node, count: dragIds.length),
      childWhenDragging: Opacity(opacity: 0.45, child: row),
      child: row,
    );
  }
}
