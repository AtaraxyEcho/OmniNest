part of 'desktop_files_page.dart';

class _FileGrid extends StatelessWidget {
  const _FileGrid({
    required this.items,
    this.draftFolderName,
    this.onDraftSubmit,
    this.onDraftCancel,
    required this.selected,
    required this.onTap,
    required this.onSelect,
    this.onToggleSelect,
    required this.onMenu,
    this.onFavorite,
    this.onShare,
    this.draggable = false,
    this.externalHoverId,
    this.folderKeyBuilder,
    this.onDropFiles,
  });

  final List<FileNode> items;
  final String? draftFolderName;
  final ValueChanged<String>? onDraftSubmit;
  final VoidCallback? onDraftCancel;
  final Set<String> selected;
  final ValueChanged<FileNode> onTap;
  final ValueChanged<FileNode> onSelect;
  final ValueChanged<FileNode>? onToggleSelect;
  final void Function(FileNode node, Offset position) onMenu;
  final ValueChanged<FileNode>? onFavorite;
  final ValueChanged<FileNode>? onShare;
  final bool draggable;
  final String? externalHoverId;
  final GlobalKey Function(String id)? folderKeyBuilder;
  final void Function(List<String> ids, String targetFolderId)? onDropFiles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final folders = items
        .where((node) => node.isFolder)
        .toList(growable: false);
    final files = items.where((node) => !node.isFolder).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        // `extra.css:88` 终值：repeat(auto-fill,minmax(168px,1fr))，gap 12px。
        final columns = ((constraints.maxWidth + 12) / (168 + 12))
            .floor()
            .clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        var staggerIndex = 0;

        Widget buildTile(FileNode node) {
          final isSelected = selected.contains(node.id);
          final dragIds =
              draggable
                  ? (isSelected
                      ? selected.toList(growable: false)
                      : <String>[node.id])
                  : const <String>[];
          return SizedBox(
            width: width,
            child: DesktopStagger(
              index: staggerIndex++,
              child: _FileTile(
                key:
                    node.isFolder && folderKeyBuilder != null
                        ? folderKeyBuilder!(node.id)
                        : null,
                node: node,
                selected: isSelected,
                hoveredAsDropTarget: externalHoverId == node.id,
                onTap: () => onSelect(node),
                onOpen: () => onTap(node),
                onMenu: (position) => onMenu(node, position),
                onToggleSelect: () => (onToggleSelect ?? onSelect)(node),
                onFavorite: onFavorite == null ? null : () => onFavorite!(node),
                onShare: onShare == null ? null : () => onShare!(node),
                dragIds: dragIds,
                onDropFiles:
                    draggable && node.isFolder && onDropFiles != null
                        ? (ids) => onDropFiles!(ids, node.id)
                        : null,
              ),
            ),
          );
        }

        final showFoldersGroup = folders.isNotEmpty || draftFolderName != null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showFoldersGroup) ...[
              _RowGroupLabel(
                label: l10n.desktopFilesFilterFolders,
                count: folders.length,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (draftFolderName != null)
                    SizedBox(
                      width: width,
                      child: _DesktopDraftFolderTile(
                        defaultName: draftFolderName!,
                        onSubmit: onDraftSubmit!,
                        onCancel: onDraftCancel!,
                      ),
                    ),
                  for (final node in folders) buildTile(node),
                ],
              ),
            ],
            if (files.isNotEmpty) ...[
              _RowGroupLabel(
                label:
                    folders.isEmpty
                        ? l10n.desktopFilesItemsGroup
                        : l10n.desktopFilesFilesGroup,
                count: files.length,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final node in files) buildTile(node)],
              ),
            ],
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
    this.dragIds = const <String>[],
    this.onDropFiles,
    this.hoveredAsDropTarget = false,
    super.key,
  });

  final FileNode node;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onFavorite;
  final VoidCallback? onShare;
  final List<String> dragIds;
  final ValueChanged<List<String>>? onDropFiles;
  final bool hoveredAsDropTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);

    Widget buildTile({required bool highlighted}) => AnimatedScale(
      scale: highlighted ? 1.02 : 1,
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
                curve: DesktopMotion.ease,
                transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
                constraints: const BoxConstraints(minHeight: 176),
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
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
                  // 样例 `.f-body.grid .f-row`：raise 底、悬停 raise2 并上浮。
                  color:
                      highlighted
                          ? skin.accentWash(0.24)
                          : selected
                          ? skin.accentWash(0.13)
                          : hovered
                          ? skin.raise2
                          : skin.raise,
                  borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                  border: Border.all(
                    color: selected ? skin.accentWash(0.42) : skin.line,
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
                          duration: DesktopMotion.of(
                            context,
                            DesktopMotion.fast,
                          ),
                          opacity: hovered || selected ? 1 : 0,
                          alwaysIncludeSemantics: true,
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
      ),
    );

    final tile =
        onDropFiles == null
            ? buildTile(highlighted: hoveredAsDropTarget)
            : DragTarget<List<String>>(
              onWillAcceptWithDetails:
                  (details) =>
                      details.data.isNotEmpty &&
                      !details.data.contains(node.id),
              onAcceptWithDetails: (details) => onDropFiles!(details.data),
              builder:
                  (context, candidate, rejected) => buildTile(
                    highlighted: candidate.isNotEmpty || hoveredAsDropTarget,
                  ),
            );
    if (dragIds.isEmpty) {
      return tile;
    }
    return _AdaptiveFileDraggable(
      data: dragIds,
      feedback: _RowDragGhost(node: node, count: dragIds.length),
      childWhenDragging: Opacity(
        opacity: 0.45,
        alwaysIncludeSemantics: true,
        child: tile,
      ),
      child: tile,
    );
  }
}

/// 文件行上下文菜单、收藏切换与分组行构建（从 desktop_files_actions.dart 拆出）。
extension _FilesPageRowActions on _DesktopFilesPageState {
  void _openRowMenu(
    BuildContext context,
    FileBrowserController controller,
    FileBrowserState? state,
    FileNode node,
    Offset position,
  ) {
    if (state == null) {
      return;
    }
    if (!state.selectedFileIds.contains(node.id)) {
      _select(controller, node);
    }
    final l10n = AppLocalizations.of(context);
    final recycle = state.section == FileManagerSection.recycleBin;
    final sharedSpace =
        state.spaceType == 'SHARED' ||
        state.section == FileManagerSection.sharedSpace;
    final items = <DesktopMenuItem>[];
    if (recycle) {
      items.add(
        DesktopMenuItem(
          label: l10n.filesRestore,
          icon: DesktopIcons.undo,
          onPressed: () => unawaited(_restoreSelected(controller)),
        ),
      );
      items.add(
        DesktopMenuItem(
          label: l10n.desktopFilesDeleteForever,
          icon: DesktopIcons.trash,
          danger: true,
          onPressed:
              () =>
                  _showPurgeDialog(context, controller, _selectedNodes(state)),
        ),
      );
    } else {
      items.add(
        DesktopMenuItem(
          label: l10n.desktopFilesOpen,
          icon: DesktopIcons.eye,
          onPressed: () => _activate(controller, node, shared: sharedSpace),
        ),
      );
      items.add(
        DesktopMenuItem(
          label: l10n.desktopQuickLook,
          icon: DesktopIcons.panel,
          onPressed:
              () => ref
                  .read(desktopShellProvider.notifier)
                  .showDetail(
                    _buildFileDetailData(
                      l10n,
                      node,
                      sharedSpace: sharedSpace,
                      controller: controller,
                      recycle: recycle,
                    ),
                  ),
        ),
      );
      items.add(
        DesktopMenuItem(
          label: l10n.desktopFilesDetails,
          icon: DesktopIcons.info,
          onPressed:
              () => ref
                  .read(desktopShellProvider.notifier)
                  .showDetail(
                    _buildFileDetailData(
                      l10n,
                      node,
                      sharedSpace: sharedSpace,
                      controller: controller,
                      recycle: recycle,
                    ),
                  ),
        ),
      );
      if (!sharedSpace) {
        items.add(
          DesktopMenuItem(
            label: l10n.filesShare,
            icon: DesktopIcons.share,
            onPressed: () => _showShareDialog(context, controller, node),
          ),
        );
      }
      items.add(
        DesktopMenuItem(
          label: l10n.filesDownload,
          icon: DesktopIcons.download,
          onPressed: () => unawaited(_openDownload(controller, node)),
        ),
      );
      if (!sharedSpace) {
        items.add(
          DesktopMenuItem(
            label:
                node.favorited
                    ? l10n.filesRemoveFavorite
                    : l10n.filesAddFavorite,
            icon: node.favorited ? DesktopIcons.starFilled : DesktopIcons.star,
            onPressed: () => unawaited(_toggleFavorite(controller, node)),
          ),
        );
      }
      items.add(const DesktopMenuItem.separator());
      items.add(
        DesktopMenuItem(
          label: l10n.filesRename,
          icon: DesktopIcons.edit,
          shortcut: 'F2',
          onPressed: () => _showRenameDialog(context, controller, node),
        ),
      );
      items.add(
        DesktopMenuItem(
          label:
              sharedSpace ? l10n.filesMoveToPersonal : l10n.filesMoveToShared,
          icon: DesktopIcons.moveRight,
          onPressed:
              () => unawaited(
                sharedSpace
                    ? controller.moveToPersonalSpace(node)
                    : controller.moveToSharedSpace(node),
              ),
        ),
      );
      items.add(const DesktopMenuItem.separator());
      items.add(
        DesktopMenuItem(
          label: l10n.desktopFilesMoveToRecycle,
          icon: DesktopIcons.trash,
          danger: true,
          shortcut: 'Del',
          onPressed: () => unawaited(_deleteSelected(controller, state)),
        ),
      );
    }
    ref.read(desktopShellProvider.notifier).openMenu(position, items);
  }

  Future<void> _toggleFavorite(
    FileBrowserController controller,
    FileNode node,
  ) async {
    if (node.favorited) {
      await controller.removeFavorite(node);
    } else {
      await controller.addFavorite(node);
    }
  }

  KeyEventResult _handleKey(
    KeyEvent event,
    FileBrowserController controller,
    FileBrowserState? state,
    FileManagerSection section,
  ) {
    if (event is! KeyDownEvent || state == null) {
      return KeyEventResult.ignored;
    }
    // 输入框获得焦点时不抢键：删除/重命名要留给文本框自己。
    // 注意：全局 Space 归音乐播放/暂停，Files 页不拦截 Space。
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final meta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final selected = _selectedNodes(state);
    if (meta && event.logicalKey == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      _syncSelectionDetail();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.clearSelection();
      ref.read(desktopShellProvider.notifier).clearDetail();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f2 && selected.length == 1) {
      _showRenameDialog(context, controller, selected.first);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && selected.length == 1) {
      _activate(
        controller,
        selected.first,
        shared: state.spaceType == 'SHARED',
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete && selected.isNotEmpty) {
      if (section == FileManagerSection.recycleBin) {
        _showPurgeDialog(context, controller, selected);
      } else {
        unawaited(_deleteSelected(controller, state));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        section == FileManagerSection.allFiles) {
      if (state.spaceType == 'SHARED') {
        final breadcrumbs = state.sharedSpaceBreadcrumbs;
        unawaited(
          breadcrumbs.isEmpty
              ? controller.goToSharedSpaceRoot()
              : breadcrumbs.length == 1
              ? controller.goToSharedSpaceRoot()
              : controller.goToSharedSpaceBreadcrumb(breadcrumbs.length - 2),
        );
      } else {
        unawaited(controller.goToParent());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<Widget> _groupedRows(
    FileBrowserState? state,
    FileBrowserController controller,
    List<FileNode> items,
    Set<String> selected,
  ) {
    if (state == null || items.isEmpty) {
      return const <Widget>[];
    }
    final l10n = AppLocalizations.of(context);
    final folders = items
        .where((node) => node.isFolder)
        .toList(growable: false);
    final files = items.where((node) => !node.isFolder).toList(growable: false);
    // 回收站与共享空间只读：不给拖拽与落点，免得拖出一次注定失败的移动。
    final draggable = state.section != FileManagerSection.recycleBin;
    final rows = <Widget>[];
    var index = 0;
    void addGroup(String label, List<FileNode> group) {
      if (group.isEmpty) {
        return;
      }
      rows.add(_RowGroupLabel(label: label, count: group.length));
      for (var i = 0; i < group.length; i++) {
        final node = group[i];
        final isSelected = selected.contains(node.id);
        final selectedPrev =
            isSelected && i > 0 && selected.contains(group[i - 1].id);
        final selectedNext =
            isSelected &&
            i + 1 < group.length &&
            selected.contains(group[i + 1].id);
        rows.add(
          DesktopStagger(
            index: index++,
            child: _FileRow(
              // 文件夹行要能被外部拖拽命中，锚点供 `_folderAt` 反查。
              key: node.isFolder ? _folderKey(node.id) : null,
              node: node,
              selected: isSelected,
              selectedPrev: selectedPrev,
              selectedNext: selectedNext,
              recycle: state.section == FileManagerSection.recycleBin,
              hoveredAsDropTarget: _externalHoverId == node.id,
              onTap: () => _select(controller, node, orderedItems: items),
              onToggleSelect: () => _toggleSelect(controller, node),
              onOpen:
                  () => _activate(
                    controller,
                    node,
                    shared: state.spaceType == 'SHARED',
                  ),
              onMenu:
                  (position) =>
                      _openRowMenu(context, controller, state, node, position),
              onFavorite:
                  state.section == FileManagerSection.recycleBin ||
                          state.spaceType == 'SHARED'
                      ? null
                      : () => unawaited(
                        node.favorited
                            ? controller.removeFavorite(node)
                            : controller.addFavorite(node),
                      ),
              onShare:
                  state.section == FileManagerSection.recycleBin ||
                          state.spaceType == 'SHARED'
                      ? null
                      : () => _showShareDialog(context, controller, node),
              // 选中态拖整组，否则只拖按下的这一行（样例 `dragIds` 同此）。
              dragIds:
                  draggable
                      ? (selected.contains(node.id)
                          ? selected.toList(growable: false)
                          : <String>[node.id])
                      : const <String>[],
              onDropFiles:
                  draggable && node.isFolder
                      ? (ids) => unawaited(controller.moveFilesTo(ids, node.id))
                      : null,
            ),
          ),
        );
      }
    }

    addGroup(l10n.desktopFilesFilterFolders, folders);
    addGroup(
      folders.isEmpty
          ? l10n.desktopFilesItemsGroup
          : l10n.desktopFilesFilesGroup,
      files,
    );
    return rows;
  }
}
