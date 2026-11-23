part of 'desktop_files_page.dart';

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.node,
    required this.selected,
    required this.recycle,
    required this.onTap,
    required this.onOpen,
    required this.onMenu,
    this.onToggleSelect,
    this.onFavorite,
    this.onShare,
    this.dragIds = const <String>[],
    this.onDropFiles,
    this.hoveredAsDropTarget = false,
    this.selectedPrev = false,
    this.selectedNext = false,
    super.key,
  });

  final FileNode node;
  final bool selected;
  final bool recycle;
  final VoidCallback onTap;
  final VoidCallback? onToggleSelect;
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

  /// 相邻选中行融合圆角（`.sel-p / .sel-n`）。
  final bool selectedPrev;
  final bool selectedNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final secondaryTextColor = skin.isDark ? skin.text3 : skin.text2;
    const corner = Radius.circular(DesktopMetrics.radius);
    final rowRadius =
        selected
            ? BorderRadius.only(
              topLeft: selectedPrev ? Radius.zero : corner,
              topRight: selectedPrev ? Radius.zero : corner,
              bottomLeft: selectedNext ? Radius.zero : corner,
              bottomRight: selectedNext ? Radius.zero : corner,
            )
            : BorderRadius.circular(DesktopMetrics.radius);

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
                        : null,
                decoration: BoxDecoration(
                  // 选中态单层 accent 42% 描边 + 相邻融合圆角；浅色默认态透明底 + 发丝底边线（polish.css:516-519）。
                  color:
                      highlighted
                          ? skin.accentWash(0.24)
                          : selected
                          ? skin.accentWash(0.13)
                          : hovered
                          ? skin.raise
                          : Colors.transparent,
                  borderRadius:
                      !selected && !hovered && !highlighted && !skin.isDark
                          ? BorderRadius.zero
                          : rowRadius,
                  border:
                      selected
                          ? Border(
                            top:
                                selectedPrev
                                    ? BorderSide.none
                                    : BorderSide(color: skin.accentWash(0.42)),
                            bottom:
                                selectedNext
                                    ? BorderSide.none
                                    : BorderSide(color: skin.accentWash(0.42)),
                            left: BorderSide(color: skin.accentWash(0.42)),
                            right: BorderSide(color: skin.accentWash(0.42)),
                          )
                          : hovered
                          ? Border.all(color: skin.line)
                          : !skin.isDark
                          ? Border(bottom: BorderSide(color: skin.line))
                          : Border.all(color: Colors.transparent),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _FileColumns.tick,
                      child: GestureDetector(
                        onTap: onToggleSelect ?? onTap,
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: _SelectionTick(selected: selected),
                        ),
                      ),
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
                            style: DesktopType.caption(secondaryTextColor),
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
                        style: DesktopType.numeric(secondaryTextColor),
                      ),
                    ),
                    const SizedBox(width: _FileColumns.gap),
                    SizedBox(
                      width: _FileColumns.size,
                      child: Text(
                        node.isFolder ? '—' : formatFileSize(node.sizeBytes),
                        textAlign: TextAlign.right,
                        style: DesktopType.numeric(secondaryTextColor),
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
                          alwaysIncludeSemantics: true,
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
      childWhenDragging: Opacity(
        opacity: 0.45,
        alwaysIncludeSemantics: true,
        child: row,
      ),
      child: row,
    );
  }
}

class _FileInspectorPreview extends ConsumerWidget {
  const _FileInspectorPreview({required this.node});

  final FileNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final icon = _fileIcon(node);
    final fallback = ColoredBox(
      color: skin.raise2,
      child: Center(child: Icon(icon, size: 46, color: skin.accent)),
    );
    if (node.isFolder) {
      return fallback;
    }
    final coverFileId = node.coverFileId;
    final isImage = node.mimeType?.toLowerCase().startsWith('image/') == true;
    final targetId =
        coverFileId != null && coverFileId.isNotEmpty
            ? coverFileId
            : (isImage ? node.id : null);
    if (targetId == null) {
      return fallback;
    }
    final url = ref.watch(fileDownloadUrlProvider(targetId)).asData?.value;
    if (url == null || url.isEmpty) {
      return fallback;
    }
    return DesktopCover(
      url: url,
      kind: DesktopCoverKind.network,
      fallback: fallback,
      fallbackIcon: icon,
      cacheKey: 'desktop-file-inspector-$targetId',
      iconSize: 46,
    );
  }
}

/// 文件检查器底部扩展区：展示共享状态入口并收编历史版本记录（原 `_DetailsDialog` 能力）。
class _FileInspectorExtraSection extends StatefulWidget {
  const _FileInspectorExtraSection({
    super.key,
    required this.node,
    required this.controller,
    required this.sharedSpace,
  });

  final FileNode node;
  final FileBrowserController controller;
  final bool sharedSpace;

  @override
  State<_FileInspectorExtraSection> createState() =>
      _FileInspectorExtraSectionState();
}

class _FileInspectorExtraSectionState
    extends State<_FileInspectorExtraSection> {
  List<FileVersion>? _versions;
  bool _loadingVersions = false;
  Object? _versionsError;

  @override
  void initState() {
    super.initState();
    if (!widget.node.isFolder) {
      _loadingVersions = true;
      unawaited(_loadVersions());
    }
  }

  @override
  void didUpdateWidget(covariant _FileInspectorExtraSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _versions = null;
      _versionsError = null;
      if (!widget.node.isFolder) {
        _loadingVersions = true;
        unawaited(_loadVersions());
      } else {
        _loadingVersions = false;
      }
    }
  }

  Future<void> _loadVersions() async {
    try {
      final versions = await widget.controller.listFileVersions(widget.node.id);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _loadingVersions = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _versionsError = error;
        _loadingVersions = false;
      });
    }
  }

  Future<void> _restore(FileVersion version) async {
    final l10n = AppLocalizations.of(context);
    try {
      await widget.controller.restoreFileVersion(widget.node, version.id);
      if (!mounted) return;
      showDesktopToast(context, l10n.filesRestore, icon: DesktopIcons.undo);
      setState(() {
        _loadingVersions = true;
        _versionsError = null;
      });
      unawaited(_loadVersions());
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesRestore, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.sharedSpace) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: skin.raise,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
              border: Border.all(color: skin.line),
            ),
            child: Row(
              children: [
                Icon(DesktopIcons.share, size: 15, color: skin.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '外链与协作者共享' : 'Link & collaborator sharing',
                    style: DesktopType.caption(skin.text2),
                  ),
                ),
                DesktopLink(
                  label: l10n.filesShare,
                  onPressed:
                      () => _showShareDialog(
                        context,
                        widget.controller,
                        widget.node,
                      ),
                ),
              ],
            ),
          ),
        ],
        if (!widget.node.isFolder) ...[
          const SizedBox(height: 14),
          DesktopEyebrow(l10n.desktopFilesVersions),
          const SizedBox(height: 8),
          if (_loadingVersions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: DesktopSkeletonBox(
                width: double.infinity,
                height: 28,
                radius: 8,
              ),
            )
          else if (_versionsError != null)
            Text(
              failureToast(l10n, l10n.desktopFilesVersions, _versionsError!),
              style: DesktopType.caption(DesktopPalette.bad),
            )
          else if (_versions == null || _versions!.isEmpty)
            Text(
              isZh ? '暂无历史版本记录' : 'No version history yet',
              style: DesktopType.caption(skin.text3),
            )
          else
            for (final version in _versions!)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            version.isCurrent
                                ? skin.accentWash(0.14)
                                : skin.raise,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusPill,
                        ),
                      ),
                      child: Text(
                        'v${version.versionNo}',
                        style: DesktopType.nano(
                          version.isCurrent ? skin.accent : skin.text3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${formatFileSize(version.sizeBytes)} · ${_formatDate(version.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text2),
                      ),
                    ),
                    if (!version.isCurrent)
                      DesktopLink(
                        label: l10n.filesRestore,
                        trailing: false,
                        onPressed: () => unawaited(_restore(version)),
                      ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}
