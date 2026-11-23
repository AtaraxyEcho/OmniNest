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

  bool _isPagedSection(FileManagerSection section) => switch (section) {
    FileManagerSection.allFiles ||
    FileManagerSection.sharedSpace ||
    FileManagerSection.recent ||
    FileManagerSection.favorites ||
    FileManagerSection.recycleBin ||
    FileManagerSection.sharedWithMe => true,
    _ => false,
  };

  int _currentPage(FileBrowserState state, FileManagerSection section) =>
      switch (section) {
        FileManagerSection.allFiles ||
        FileManagerSection.sharedSpace => state.filePage,
        FileManagerSection.recent => state.recentMeta.page,
        FileManagerSection.favorites => state.favoritesMeta.page,
        FileManagerSection.recycleBin => state.recycleMeta.page,
        _ => state.sharedWithMeMeta.page,
      };

  int _pageSize(FileBrowserState state, FileManagerSection section) =>
      switch (section) {
        FileManagerSection.allFiles ||
        FileManagerSection.sharedSpace => state.filePageSize,
        FileManagerSection.recent => state.recentMeta.size,
        FileManagerSection.favorites => state.favoritesMeta.size,
        FileManagerSection.recycleBin => state.recycleMeta.size,
        _ => state.sharedWithMeMeta.size,
      };

  int _totalCount(FileBrowserState state, FileManagerSection section) =>
      switch (section) {
        FileManagerSection.allFiles ||
        FileManagerSection.sharedSpace => state.fileTotalElements,
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
      final controller = ref.read(fileBrowserControllerProvider.notifier);
      unawaited(
        target == FileManagerSection.sharedSpace
            ? controller.switchSpace('SHARED')
            : controller.loadSection(target),
      );
    });
  }

  void _goSection(FileBrowserController controller, FileManagerSection value) {
    _search.clear();
    controller.setSearchQuery('');
    ref.read(desktopShellProvider.notifier).clearDetail();
    unawaited(controller.loadSection(value));
  }

  /// 原型侧栏的 Personal / Shared space 分段切换使用同一个工作区列表，
  /// 不能只切换一个导航分区，否则树、面包屑和拖放目标仍停留在旧空间。
  void _switchSpace(FileBrowserController controller, String spaceType) {
    _search.clear();
    controller.setSearchQuery('');
    ref.read(desktopShellProvider.notifier).clearDetail();
    unawaited(controller.switchSpace(spaceType));
  }

  void _beginNewFolder(
    FileBrowserController controller,
    FileBrowserState? state,
  ) {
    if (state == null || state.draftFolderName != null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    controller.beginFolderCreation(
      dedupeFolderName(l10n.filesNewFolderDefault, state.files),
    );
  }

  void _openFolder(
    FileBrowserController controller,
    FileNode folder, {
    bool shared = false,
    List<FileNode>? breadcrumbs,
  }) {
    ref.read(desktopShellProvider.notifier).clearDetail();
    unawaited(
      shared
          ? controller.openSharedSpaceFolder(folder, breadcrumbs: breadcrumbs)
          : controller.openFolder(folder, breadcrumbs: breadcrumbs),
    );
  }

  DesktopDetailData _buildFileDetailData(
    AppLocalizations l10n,
    FileNode node, {
    required bool sharedSpace,
    FileBrowserController? controller,
    bool recycle = false,
  }) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final isShared = sharedSpace || node.spaceType == SpaceType.shared;
    final FileBrowserController activeController =
        controller ?? ref.read(fileBrowserControllerProvider.notifier);
    final updatedAt = node.updatedAt?.toLocal();
    final modifiedText =
        updatedAt == null
            ? '—'
            : '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')} '
                '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}';

    final extraActions = <DesktopDetailAction>[
      if (!recycle && !node.isFolder && !isShared)
        DesktopDetailAction(
          label: l10n.filesDownload,
          icon: DesktopIcons.download,
          onPressed: (_, _) => unawaited(_openDownload(activeController, node)),
        ),
      if (!recycle && !isShared)
        DesktopDetailAction(
          label:
              node.favorited ? l10n.filesRemoveFavorite : l10n.filesAddFavorite,
          icon: node.favorited ? DesktopIcons.starFilled : DesktopIcons.star,
          onPressed:
              (_, _) => unawaited(_toggleFavorite(activeController, node)),
        ),
      if (!recycle)
        DesktopDetailAction(
          label: l10n.filesRename,
          icon: DesktopIcons.edit,
          onPressed: (ctx, _) => _showRenameDialog(ctx, activeController, node),
        ),
    ];

    return DesktopDetailData(
      id: 'file:${node.id}',
      kind: 'file',
      title: node.name,
      subtitle:
          node.isFolder
              ? l10n.desktopFilesKindFolder
              : formatFileSize(node.sizeBytes),
      isFolder: node.isFolder,
      fallbackIcon: _fileIcon(node),
      badge: isShared ? l10n.desktopFilesSharedBadge : null,
      squareArt: true,
      customPreview: _FileInspectorPreview(node: node),
      factsLabel: l10n.desktopFileSection,
      facts: [
        MapEntry(
          l10n.filesColumnType,
          node.isFolder
              ? l10n.desktopFilesKindFolder
              : (node.mimeType ?? node.nodeType),
        ),
        MapEntry(
          l10n.desktopFilesSize,
          node.isFolder ? '—' : formatFileSize(node.sizeBytes),
        ),
        MapEntry(l10n.desktopFilesModified, modifiedText),
        MapEntry(
          isZh ? '完整路径' : 'Path',
          node.normalizedPath.isEmpty ? '/' : node.normalizedPath,
        ),
        MapEntry(
          l10n.filesGroupSharing,
          isShared ? l10n.desktopFilesSharedBadge : l10n.desktopFilesPrivate,
        ),
      ],
      primary: DesktopDetailAction(
        label: l10n.desktopFilesOpen,
        icon: node.isFolder ? DesktopIcons.folder : DesktopIcons.eye,
        onPressed: (ctx, r) {
          if (node.isFolder) {
            final ctrl = r.read(fileBrowserControllerProvider.notifier);
            unawaited(
              isShared
                  ? ctrl.openSharedSpaceFolder(node)
                  : ctrl.openFolder(node),
            );
            return;
          }
          desktopPush(ctx, DesktopRoutes.filePreview(node.id));
        },
      ),
      secondary:
          !recycle && !isShared
              ? DesktopDetailAction(
                label: l10n.filesShare,
                icon: DesktopIcons.share,
                onPressed:
                    (ctx, _) => _showShareDialog(ctx, activeController, node),
              )
              : !recycle && !node.isFolder
              ? DesktopDetailAction(
                label: l10n.filesDownload,
                icon: DesktopIcons.download,
                onPressed:
                    (_, _) => unawaited(_openDownload(activeController, node)),
              )
              : null,
      extraActions: extraActions,
      extraSection:
          recycle
              ? null
              : _FileInspectorExtraSection(
                key: ValueKey<String>('file-inspector-extra-${node.id}'),
                node: node,
                controller: activeController,
                sharedSpace: isShared,
              ),
    );
  }

  DesktopDetailData _buildMultiSelectionDetailData(
    AppLocalizations l10n,
    List<FileNode> nodes, {
    required FileBrowserState state,
    required FileBrowserController controller,
  }) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final recycle = state.section == FileManagerSection.recycleBin;
    final sharedSpace =
        state.spaceType == 'SHARED' ||
        state.section == FileManagerSection.sharedSpace;
    final folderCount = nodes.where((n) => n.isFolder).length;
    final fileCount = nodes.length - folderCount;
    final totalBytes = nodes.fold<int>(
      0,
      (sum, node) => sum + (node.isFolder ? 0 : node.sizeBytes),
    );

    final extraActions = <DesktopDetailAction>[
      if (!recycle)
        DesktopDetailAction(
          label:
              sharedSpace ? l10n.filesMoveToPersonal : l10n.filesMoveToShared,
          icon: DesktopIcons.moveRight,
          onPressed:
              (_, _) => unawaited(
                _moveSelectedToSpace(controller, state, toShared: !sharedSpace),
              ),
        ),
      if (!recycle)
        DesktopDetailAction(
          label: l10n.desktopFilesMoveToRecycle,
          icon: DesktopIcons.trash,
          danger: true,
          onPressed: (_, _) => unawaited(_deleteSelected(controller, state)),
        ),
    ];

    return DesktopDetailData(
      id: 'files-multi:${nodes.map((n) => n.id).join(",")}',
      kind: 'file',
      title: isZh ? '已选 ${nodes.length} 项' : '${nodes.length} items selected',
      subtitle:
          isZh
              ? '总大小 ${formatFileSize(totalBytes)}'
              : 'Total ${formatFileSize(totalBytes)}',
      fallbackIcon: DesktopIcons.check,
      badge: '${nodes.length}',
      squareArt: true,
      factsLabel: isZh ? '批量汇总' : 'SELECTION SUMMARY',
      facts: [
        MapEntry(l10n.desktopFilesFilterFolders, '$folderCount'),
        MapEntry(l10n.desktopFilesFilesGroup, '$fileCount'),
        MapEntry(l10n.desktopFilesSize, formatFileSize(totalBytes)),
        MapEntry(
          l10n.filesGroupSharing,
          sharedSpace ? l10n.importToSharedSpace : l10n.importToPersonalSpace,
        ),
      ],
      primary:
          recycle
              ? DesktopDetailAction(
                label: l10n.filesRestore,
                icon: DesktopIcons.undo,
                onPressed: (_, _) => unawaited(_restoreSelected(controller)),
              )
              : fileCount > 0
              ? DesktopDetailAction(
                label: l10n.filesDownload,
                icon: DesktopIcons.download,
                onPressed:
                    (_, _) => unawaited(_downloadSelected(state, controller)),
              )
              : null,
      secondary:
          recycle
              ? DesktopDetailAction(
                label: l10n.desktopFilesDeleteForever,
                icon: DesktopIcons.trash,
                danger: true,
                onPressed: (ctx, _) => _showPurgeDialog(ctx, controller, nodes),
              )
              : DesktopDetailAction(
                label: l10n.filesCancel,
                icon: DesktopIcons.close,
                onPressed: (_, r) {
                  controller.clearSelection();
                  r.read(desktopShellProvider.notifier).clearDetail();
                },
              ),
      extraActions: extraActions,
    );
  }

  void _syncSelectionDetail({FileNode? fallbackNode}) {
    if (!mounted) {
      return;
    }
    final state = ref.read(fileBrowserControllerProvider).asData?.value;
    if (state == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final selectedNodes = _selectedNodes(state);
    final shell = ref.read(desktopShellProvider.notifier);
    if (selectedNodes.isEmpty) {
      if (fallbackNode != null &&
          state.selectedFileIds.contains(fallbackNode.id)) {
        final sharedSpace =
            state.spaceType == 'SHARED' ||
            state.section == FileManagerSection.sharedSpace;
        shell.selectDetail(
          _buildFileDetailData(
            l10n,
            fallbackNode,
            sharedSpace: sharedSpace,
            controller: controller,
            recycle: state.section == FileManagerSection.recycleBin,
          ),
        );
        return;
      }
      shell.clearDetail();
      return;
    }
    if (selectedNodes.length == 1) {
      final sharedSpace =
          state.spaceType == 'SHARED' ||
          state.section == FileManagerSection.sharedSpace;
      shell.selectDetail(
        _buildFileDetailData(
          l10n,
          selectedNodes.first,
          sharedSpace: sharedSpace,
          controller: controller,
          recycle: state.section == FileManagerSection.recycleBin,
        ),
      );
      return;
    }
    shell.selectDetail(
      _buildMultiSelectionDetailData(
        l10n,
        selectedNodes,
        state: state,
        controller: controller,
      ),
    );
  }

  void _select(
    FileBrowserController controller,
    FileNode node, {
    List<FileNode>? orderedItems,
  }) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed &&
        _selectionAnchorId != null &&
        orderedItems != null &&
        orderedItems.isNotEmpty) {
      controller.selectRange(
        orderedItems.map((item) => item.id).toList(growable: false),
        _selectionAnchorId!,
        node.id,
      );
      _syncSelectionDetail(fallbackNode: node);
      return;
    }
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      controller.toggleSelection(node.id);
      _selectionAnchorId = node.id;
      _syncSelectionDetail(fallbackNode: node);
      return;
    }
    controller.clearSelection();
    controller.toggleSelection(node.id);
    _selectionAnchorId = node.id;
    _syncSelectionDetail(fallbackNode: node);
  }

  void _toggleSelect(FileBrowserController controller, FileNode node) {
    controller.toggleSelection(node.id);
    _selectionAnchorId = node.id;
    _syncSelectionDetail(fallbackNode: node);
  }

  void _toggleSelectAll(
    FileBrowserController controller,
    List<FileNode> items,
    Set<String> selected,
  ) {
    if (items.isEmpty) {
      return;
    }
    final allSelected = items.every((node) => selected.contains(node.id));
    if (allSelected) {
      controller.clearSelection();
      _selectionAnchorId = null;
      _syncSelectionDetail();
      return;
    }
    controller.selectAll(items.map((node) => node.id));
    _selectionAnchorId = items.first.id;
    _syncSelectionDetail();
  }

  void _activate(
    FileBrowserController controller,
    FileNode node, {
    bool shared = false,
  }) {
    if (node.isFolder) {
      ref.read(desktopShellProvider.notifier).clearDetail();
      unawaited(
        shared
            ? controller.openSharedSpaceFolder(node)
            : controller.openFolder(node),
      );
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
    final shared =
        state.spaceType == 'SHARED' ||
        state.section == FileManagerSection.sharedSpace;
    final nodes = _selectedNodes(state);
    if (nodes.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            eyebrow: l10n.filesFileActions,
            title:
                shared
                    ? l10n.filesRemoveSharedConfirmTitle
                    : l10n.filesDeleteConfirmTitle(nodes.first.name),
            lead: Icon(DesktopIcons.trash, size: 20, color: DesktopPalette.bad),
            content: Text(
              shared
                  ? l10n.filesRemoveSharedConfirmMessage
                  : l10n.filesDeleteConfirmMessage(nodes.first.name),
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.filesCancel,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label:
                    shared
                        ? l10n.filesRemoveSharedConfirmAction
                        : l10n.filesMoveToRecycleBin,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true) {
      return;
    }
    // 删除前留一份 id 快照：批量接口会清空选中集，Undo 拿不到原节点。
    final deletedIds = nodes.map((node) => node.id).toList();
    if (shared) {
      // 共享空间没有批量删除接口：逐个移出，语义与移动页一致。
      for (final node in nodes) {
        await controller.deleteSharedFile(node);
      }
    } else {
      await controller.batchDeleteFiles();
    }
    if (!mounted) {
      return;
    }
    ref.read(desktopShellProvider.notifier).clearDetail();
    showDesktopToast(
      context,
      shared
          ? l10n.desktopFilesRemovedFromSharedSpace
          : l10n.desktopFilesMovedToRecycle,
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
    ref.read(desktopShellProvider.notifier).clearDetail();
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

  Future<void> _moveSelectedToSpace(
    FileBrowserController controller,
    FileBrowserState state, {
    required bool toShared,
  }) async {
    final nodes = _selectedNodes(state);
    if (nodes.isEmpty) {
      return;
    }
    for (final node in nodes) {
      if (toShared) {
        await controller.moveToSharedSpace(node);
      } else {
        await controller.moveToPersonalSpace(node);
      }
    }
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    showDesktopToast(
      context,
      toShared
          ? l10n.filesMoveToSharedSuccess
          : l10n.filesMoveToPersonalSuccess,
      icon: DesktopIcons.moveRight,
    );
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
}
