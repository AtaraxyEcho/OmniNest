part of 'desktop_files_page.dart';

/// 文件页的动作层：取数切片、选中派生、上传/下载/删除/分享。
///
/// 拆成扩展只为让页面文件留在 800 行闸门内——这些方法读写的是同一份
/// State，拆类反而要新建一套转发。
extension _FilesPageActions on _DesktopFilesPageState {
  // ── 数据 ────────────────────────────────────────────────────────────

  List<FileNode> _itemsForSection(
    FileBrowserState? state,
    FileManagerSection section,
    String query,
  ) {
    if (state == null) {
      return const <FileNode>[];
    }
    final pool = switch (section) {
      FileManagerSection.recent => state.recentFiles,
      FileManagerSection.favorites => state.favoriteFiles,
      FileManagerSection.recycleBin => state.recycleBin,
      _ => state.files,
    };
    // 其余分类由服务端收窄，「文件夹」是纯前端分类（后端没有这个参数），
    // 整页数据已在手，就地按节点类型过滤。
    final scoped =
        state.fileCategory == FileBrowserFileCategory.folders
            ? pool.where((node) => node.isFolder).toList(growable: false)
            : pool;
    final keyword = query.trim().toLowerCase();
    final filtered =
        keyword.isEmpty
            ? scoped
            : scoped
                .where((node) => node.name.toLowerCase().contains(keyword))
                .toList(growable: false);
    final sorted = [...filtered];
    sorted.sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      final result = switch (state.sortBy) {
        FileBrowserSortBy.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        FileBrowserSortBy.size => a.sizeBytes.compareTo(b.sizeBytes),
        FileBrowserSortBy.updatedAt => (a.updatedAt ?? DateTime(0)).compareTo(
          b.updatedAt ?? DateTime(0),
        ),
      };
      return state.sortAscending ? result : -result;
    });
    return sorted;
  }

  List<FileNode> _selectedNodes(FileBrowserState state) => [
    for (final node in _itemsForSection(state, state.section, ''))
      if (state.selectedFileIds.contains(node.id)) node,
  ];

  bool _hasMore(
    FileBrowserState state,
    FileManagerSection section,
  ) => switch (section) {
    FileManagerSection.recent => state.recentMeta.hasMore,
    FileManagerSection.favorites => state.favoritesMeta.hasMore,
    FileManagerSection.recycleBin => state.recycleMeta.hasMore,
    FileManagerSection.sharedWithMe => state.sharedWithMeMeta.hasMore,
    FileManagerSection.allFiles => state.filePage + 1 < state.fileTotalPages,
    _ => false,
  };

  int _loadedCount(FileBrowserState state, FileManagerSection section) =>
      switch (section) {
        FileManagerSection.allFiles => state.files.length,
        FileManagerSection.recent => state.recentFiles.length,
        FileManagerSection.favorites => state.favoriteFiles.length,
        FileManagerSection.recycleBin => state.recycleBin.length,
        _ => state.sharedWithMe.length,
      };

  int _totalCount(FileBrowserState state, FileManagerSection section) =>
      switch (section) {
        FileManagerSection.allFiles => state.fileTotalElements,
        FileManagerSection.recent => state.recentMeta.totalElements,
        FileManagerSection.favorites => state.favoritesMeta.totalElements,
        FileManagerSection.recycleBin => state.recycleMeta.totalElements,
        _ => state.sharedWithMeMeta.totalElements,
      };

  List<FileUploadClientTask> _transfers(FileBrowserState state) =>
      state.inlineUploadTasks;

  // ── 动作 ────────────────────────────────────────────────────────────

  void _applyInitialSection(FileManagerSection current) {
    final target = widget.initialSection;
    if (target == null || _appliedSection == target) {
      return;
    }
    _appliedSection = target;
    if (current == target) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(fileBrowserControllerProvider.notifier).loadSection(target),
      );
    });
  }

  void _goSection(FileBrowserController controller, FileManagerSection value) {
    _search.clear();
    controller.setSearchQuery('');
    unawaited(controller.loadSection(value));
  }

  void _openFolder(FileBrowserController controller, FileNode folder) {
    unawaited(controller.openFolder(folder));
  }

  void _select(FileBrowserController controller, FileNode node) {
    controller.clearSelection();
    controller.toggleSelection(node.id);
  }

  void _activate(FileBrowserController controller, FileNode node) {
    if (node.isFolder) {
      unawaited(controller.openFolder(node));
      return;
    }
    desktopPush(context, DesktopRoutes.filePreview(node.id));
  }

  void _sortBy(
    FileBrowserController controller,
    FileBrowserState? state,
    FileBrowserSortBy value,
  ) {
    if (state?.sortBy == value) {
      controller.toggleSortAscending();
      return;
    }
    controller.setSortBy(value);
  }

  Future<void> _loadMore(
    FileBrowserController controller,
    FileBrowserState state,
    FileManagerSection section,
  ) async {
    await switch (section) {
      FileManagerSection.allFiles => controller.loadMoreFiles(),
      FileManagerSection.recent => controller.loadMoreRecentFiles(),
      FileManagerSection.favorites => controller.loadMoreFavoriteFiles(),
      FileManagerSection.recycleBin => controller.loadMoreRecycleBin(),
      _ => controller.loadMoreSharedWithMe(),
    };
  }

  Future<void> _pickAndUpload(
    FileBrowserController controller,
    FileBrowserState? state,
  ) async {
    final files = await FilePick.openMultipleFiles();
    if (files.isEmpty) {
      return;
    }
    await _upload(files, controller, state);
  }

  Future<void> _upload(
    List<XFile> files,
    FileBrowserController controller,
    FileBrowserState? state,
  ) async {
    if (state == null) {
      return;
    }
    final result = await controller.uploadFiles(
      files,
      target: UploadTarget.of(state),
    );
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    showDesktopToast(
      context,
      l10n.desktopFilesUploadDone(result.completed, result.total),
      kind:
          result.failed > 0 ? DesktopToastKind.warn : DesktopToastKind.success,
      icon: result.failed > 0 ? DesktopIcons.info : DesktopIcons.upload,
    );
  }

  Future<void> _downloadSelected(
    FileBrowserState state,
    FileBrowserController controller,
  ) async {
    final nodes = _selectedNodes(state).where((n) => !n.isFolder);
    for (final node in nodes) {
      await _openDownload(controller, node);
    }
  }

  Future<void> _deleteSelected(
    FileBrowserController controller,
    FileBrowserState state,
  ) async {
    if (state.section == FileManagerSection.recycleBin) {
      return;
    }
    final shared = state.section == FileManagerSection.sharedSpace;
    // 删除前留一份 id 快照：批量接口会清空选中集，Undo 拿不到原节点。
    final deletedIds = _selectedNodes(state).map((node) => node.id).toList();
    if (shared) {
      // 共享空间没有批量删除接口：逐个移出，语义与移动页一致。
      for (final node in _selectedNodes(state)) {
        await controller.deleteSharedFile(node);
      }
    } else {
      await controller.batchDeleteFiles();
    }
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    showDesktopToast(
      context,
      l10n.desktopFilesMovedToRecycle,
      icon: DesktopIcons.trash,
      // 移出共享空间不进回收站，没有可还原的对象，别给假 Undo。
      actionLabel: shared ? null : l10n.desktopUndo,
      onAction:
          shared ? null : () => unawaited(controller.undoDelete(deletedIds)),
    );
  }

  Future<void> _restoreSelected(FileBrowserController controller) async {
    final messenger = AppLocalizations.of(context);
    await controller.batchRestoreFiles();
    if (!mounted) {
      return;
    }
    showDesktopToast(
      context,
      messenger.desktopFilesRestored,
      icon: DesktopIcons.undo,
    );
  }

  Future<void> _favoriteSelected(
    FileBrowserState state,
    FileBrowserController controller,
  ) async {
    final nodes = _selectedNodes(state);
    final allFavorited = nodes.every((node) => node.favorited);
    if (allFavorited) {
      await controller.batchRemoveFavorites();
    } else {
      await controller.batchAddFavorites();
    }
  }

  Future<void> _copyShareLink(
    FileBrowserController controller,
    FileShareLink link,
  ) async {
    final messenger = AppLocalizations.of(context);
    String baseUrl;
    try {
      baseUrl = await ref.read(webShareBaseUrlResolverProvider).resolve();
    } on Object {
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        messenger.desktopFilesShareUnavailable,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.info,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    if (link.shareCode.isEmpty) {
      showDesktopToast(
        context,
        messenger.desktopFilesShareUnavailable,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.info,
      );
      return;
    }
    final copied = await copyTextToClipboard('$baseUrl/#/s/${link.shareCode}');
    if (!mounted) {
      return;
    }
    showDesktopToast(
      context,
      copied ? messenger.desktopFilesLinkCopied : messenger.filesCopyLink,
      icon: DesktopIcons.copy,
      kind: copied ? DesktopToastKind.success : DesktopToastKind.warn,
    );
  }

  Future<void> _openDownload(
    FileBrowserController controller,
    FileNode node,
  ) async {
    final messenger = AppLocalizations.of(context);
    try {
      final url = await controller.downloadUrl(node);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) {
        return;
      }
      if (!opened) {
        await copyTextToClipboard(url);
        if (!mounted) {
          return;
        }
        showDesktopToast(
          context,
          messenger.desktopFilesLinkCopied,
          icon: DesktopIcons.copy,
        );
      }
    } on Object {
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        messenger.filesLoadFailed(messenger.filesDownload),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

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
    final sharedSpace = state.section == FileManagerSection.sharedSpace;
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
          onPressed: () => _activate(controller, node),
        ),
      );
      items.add(
        DesktopMenuItem(
          label: l10n.desktopFilesDetails,
          icon: DesktopIcons.info,
          onPressed:
              () => showDesktopDialog<void>(
                context,
                builder:
                    (_) => _DetailsDialog(controller: controller, node: node),
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
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final meta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final selected = _selectedNodes(state);
    if (meta && event.logicalKey == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.clearSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f2 && selected.length == 1) {
      _showRenameDialog(context, controller, selected.first);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && selected.length == 1) {
      _activate(controller, selected.first);
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
      unawaited(controller.goToParent());
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
      for (final node in group) {
        rows.add(
          DesktopStagger(
            index: index++,
            child: _FileRow(
              // 文件夹行要能被外部拖拽命中，锚点供 `_folderAt` 反查。
              key: node.isFolder ? _folderKey(node.id) : null,
              node: node,
              selected: selected.contains(node.id),
              recycle: state.section == FileManagerSection.recycleBin,
              hoveredAsDropTarget: _externalHoverId == node.id,
              onTap: () => _select(controller, node),
              onOpen: () => _activate(controller, node),
              onMenu:
                  (position) =>
                      _openRowMenu(context, controller, state, node, position),
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
