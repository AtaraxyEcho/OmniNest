part of 'file_browser_page.dart';

class _FileSectionBody extends StatelessWidget {
  const _FileSectionBody({super.key, required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.section) {
      FileManagerSection.allFiles ||
      FileManagerSection.sharedSpace ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin => _FileNodeWorkspace(state: state),
      FileManagerSection.sharedWithMe => _SharedWithMeWorkspace(state: state),
      // 合并分享页：我的创建 / 全部链接（管理员）双作用域；
      // shareManagement 旧入口重定向到同一页面。
      FileManagerSection.myShares ||
      FileManagerSection.shareManagement => _ShareWorkspace(
        title: AppLocalizations.of(context).filesMyShares,
        subtitle: FileManagerSection.myShares.descriptionOf(
          AppLocalizations.of(context),
        ),
        shares: state.shareScopeAll ? state.shareLinks : state.myShares,
        managementMode: state.shareScopeAll,
        state: state,
      ),
      FileManagerSection.storageStats => _FileNodeWorkspace(state: state),
      FileManagerSection.uploadQueue => _UploadQueueWorkspace(state: state),
      FileManagerSection.offlineDownloads => _OfflineDownloadWorkspace(
        state: state,
      ),
      FileManagerSection.externalStorage => _ExternalStorageWorkspace(
        state: state,
      ),
      FileManagerSection.importTasks => _ImportTasksWorkspace(state: state),
    };
  }
}

class _FileNodeWorkspace extends ConsumerWidget {
  const _FileNodeWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final recycle = state.section == FileManagerSection.recycleBin;
    final actionsEnabled = !state.isBusy;
    final isNarrow = MediaQuery.sizeOf(context).width < 900;

    if (isNarrow) {
      return Stack(
        children: [
          FileDropUploadSurface(
            enabled:
                state.section == FileManagerSection.allFiles && actionsEnabled,
            onFilesDropped: (files) => _uploadFiles(context, controller, files),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.section == FileManagerSection.allFiles) ...[
                  Row(
                    children: [
                      Expanded(child: _Breadcrumbs(state: state)),
                      _FileFilterButton(state: state),
                      _FileViewToggleButton(state: state),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                if (state.section == FileManagerSection.allFiles &&
                    state.inlineUploadTasks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _InlineUploadQueueCard(
                    tasks: state.inlineUploadTasks,
                    onOpenQueue:
                        () => unawaited(
                          _runFileAction(
                            context,
                            () => controller.loadSection(
                              FileManagerSection.uploadQueue,
                            ),
                          ),
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: _FileViewSwitcher(
                    state: state,
                    narrow: true,
                    actionsEnabled: actionsEnabled,
                    recycle: recycle,
                  ),
                ),
              ],
            ),
          ),
          if (state.hasSelection)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _MobileStickyBatchBar(state: state),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return _StatsRow(state: state, maxWidth: constraints.maxWidth);
          },
        ),
        const SizedBox(height: 14),
        _BreadcrumbActionStrip(state: state, actionsEnabled: actionsEnabled),
        // 全部列表分区（最近/收藏/回收站/共享空间等）统一提供分类筛选 +
        // 排序条，与全部文件同语言，避免各分区工具能力不一致。
        const SizedBox(height: 10),
        _CategoryFilterBar(state: state, actionsEnabled: actionsEnabled),
        if (state.section == FileManagerSection.allFiles &&
            state.inlineUploadTasks.isNotEmpty) ...[
          const SizedBox(height: 14),
          _InlineUploadQueueCard(
            tasks: state.inlineUploadTasks,
            onOpenQueue:
                () => unawaited(
                  _runFileAction(
                    context,
                    () =>
                        controller.loadSection(FileManagerSection.uploadQueue),
                  ),
                ),
          ),
        ],
        const SizedBox(height: 14),
        Expanded(
          child: FileDropUploadSurface(
            enabled:
                state.section == FileManagerSection.allFiles && actionsEnabled,
            onFilesDropped: (files) => _uploadFiles(context, controller, files),
            child: Column(
              children: [
                if (state.viewMode == FileBrowserViewMode.grid) ...[
                  _GridBatchToolbar(state: state),
                  const SizedBox(height: 12),
                ] else if (state.hasSelection) ...[
                  _TableBatchBar(state: state),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: _FileViewSwitcher(
                    state: state,
                    narrow: false,
                    actionsEnabled: actionsEnabled,
                    recycle: recycle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 面包屑与顶部操作条：左侧目录路径，右侧 上传 / 新建文件夹 / 视图切换，
/// 底部 1px 细线收束（模板 Breadcrumb & Top Action Strip）。
class _BreadcrumbActionStrip extends ConsumerWidget {
  const _BreadcrumbActionStrip({
    required this.state,
    required this.actionsEnabled,
  });

  final FileBrowserState state;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final isAllFiles = state.section == FileManagerSection.allFiles;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.filesColors.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: _Breadcrumbs(state: state)),
          if (isAllFiles) ...[
            FilesActionButton(
              label: l10n.filesUploadFile,
              icon: Icons.upload_file_rounded,
              variant: FilesActionButtonVariant.primary,
              onPressed:
                  actionsEnabled
                      ? () => _pickAndUploadFiles(context, controller)
                      : null,
            ),
            const SizedBox(width: 8),
            FilesActionButton(
              label: l10n.filesNewFolder,
              icon: Icons.create_new_folder_outlined,
              onPressed:
                  actionsEnabled
                      ? () => controller.beginFolderCreation(
                        dedupeFolderName(
                          l10n.filesNewFolderDefault,
                          state.files,
                        ),
                      )
                      : null,
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: context.filesColors.outlineVariant,
            ),
            const SizedBox(width: 8),
          ],
          FilesToolbarSegmented<FileBrowserViewMode>(
            height: 28,
            selected: state.viewMode,
            onSelected:
                actionsEnabled
                    ? controller.setViewMode
                    : (_) {
                      // 禁用态不响应。
                    },
            segments: [
              FilesToolbarSegment(
                value: FileBrowserViewMode.list,
                tooltip: l10n.filesToolbarTableView,
                icon: Icons.format_list_bulleted,
              ),
              FilesToolbarSegment(
                value: FileBrowserViewMode.grid,
                tooltip: l10n.filesToolbarGridView,
                icon: Icons.grid_view_rounded,
              ),
            ],
          ),
          if (MediaQuery.sizeOf(context).width >=
                  FilesInspectorAdaptive.dockMinWidth &&
              FilesInspectorAdaptive.sectionHasFileList(state.section)) ...[
            const SizedBox(width: 8),
            FilesToolbarIconButton(
              tooltip: l10n.filesToggleInspector,
              icon: Icons.view_sidebar_outlined,
              active: state.inspectorOpen,
              onPressed:
                  () => controller.setInspectorOpen(!state.inspectorOpen),
            ),
          ],
        ],
      ),
    );
  }
}

/// 分类筛选条：全部/图片/视频/音频/文档/小说/漫画/压缩包 chips（带计数），
/// 右侧排序小链接（模板 Category Filter Bar）。
class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar({required this.state, required this.actionsEnabled});

  final FileBrowserState state;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final counts = <FileBrowserFileCategory, int>{
      for (final category in FileBrowserFileCategory.values)
        category:
            category == FileBrowserFileCategory.all
                ? state.files.length
                : state.files
                    .where((node) => _categoryOfNode(node) == category)
                    .length,
    };
    final sortByLabel = switch (state.sortBy) {
      FileBrowserSortBy.name => l10n.filesSortName,
      FileBrowserSortBy.updatedAt => l10n.filesSortTime,
      FileBrowserSortBy.size => l10n.filesSortSize,
    };
    return Row(
      children: [
        Expanded(
          // 窄窗口下 chips 溢出：悬停区域时纵向滚轮驱动横向滚动。
          child: HoverHorizontalScroll(
            child: Row(
              children: [
                for (final category in FileBrowserFileCategory.values) ...[
                  _CategoryCapsule(
                    label: '${category.labelOf(l10n)} (${counts[category]})',
                    icon: category.icon,
                    isActive: state.fileCategory == category,
                    enabled: actionsEnabled,
                    onTap:
                        () => unawaited(
                          _runFileAction(
                            context,
                            () => controller.setFileCategory(category),
                          ),
                        ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _SortCycleButton(
          label: sortByLabel,
          enabled: actionsEnabled,
          onTap: () => controller.setSortBy(_nextSortBy(state.sortBy)),
        ),
      ],
    );
  }
}

FileBrowserSortBy _nextSortBy(FileBrowserSortBy current) {
  return switch (current) {
    FileBrowserSortBy.name => FileBrowserSortBy.updatedAt,
    FileBrowserSortBy.updatedAt => FileBrowserSortBy.size,
    FileBrowserSortBy.size => FileBrowserSortBy.name,
  };
}

/// 客户端近似分类（委托共享实现，供筛选计数复用）。
FileBrowserFileCategory _categoryOfNode(FileNode node) {
  return switch (fileCategoryOfNode(node)) {
    FileCategoryLabel.all => FileBrowserFileCategory.all,
    FileCategoryLabel.image => FileBrowserFileCategory.image,
    FileCategoryLabel.video => FileBrowserFileCategory.video,
    FileCategoryLabel.audio => FileBrowserFileCategory.audio,
    FileCategoryLabel.document => FileBrowserFileCategory.document,
    FileCategoryLabel.novel => FileBrowserFileCategory.novel,
    FileCategoryLabel.comic => FileBrowserFileCategory.comic,
    FileCategoryLabel.archive => FileBrowserFileCategory.archive,
    FileCategoryLabel.other => FileBrowserFileCategory.other,
  };
}

/// 排序小链接：点击轮换排序字段（模板 排序: 修改时间 ↓ 形态）。
class _SortCycleButton extends StatefulWidget {
  const _SortCycleButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SortCycleButton> createState() => _SortCycleButtonState();
}

class _SortCycleButtonState extends State<_SortCycleButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final foreground = _hovering ? colors.onSurface : colors.onSurfaceVariant;
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.filesSortBy,
      child: MouseRegion(
        cursor:
            widget.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${l10n.filesSortBy}:',
                style: TextStyle(
                  fontSize: AppTypography.labelMedium,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  decoration: _hovering ? TextDecoration.underline : null,
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
              Icon(Icons.arrow_downward, size: 12, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

/// 视图切换容器：180ms 淡入微移，起点 0.35 opacity 消除黑白闪现。
class _FileViewSwitcher extends ConsumerWidget {
  const _FileViewSwitcher({
    required this.state,
    required this.narrow,
    required this.actionsEnabled,
    required this.recycle,
  });

  final FileBrowserState state;
  final bool narrow;
  final bool actionsEnabled;
  final bool recycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    // 后台（实时触发）刷新不切换 loading 占位符：内容原地换新，
    // 消除自操作与他端变更带来的“闪烁刷新”。
    final showLoading =
        state.isBusy &&
        !state.backgroundRefresh &&
        state.section == FileManagerSection.allFiles;
    final child =
        showLoading
            ? KeyedSubtree(
              key: const ValueKey('_loading'),
              child: _buildLoadingPlaceholder(context),
            )
            : KeyedSubtree(
              key: ValueKey(
                '${state.spaceType}_${state.parentId}_${state.viewMode.name}_$narrow',
              ),
              child: _buildFileView(context, ref, controller),
            );
    return AnimatedSwitcher(
      duration: MotionToken.resolve(context, MotionToken.pageSwitch),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: excludeExitingSemanticsStack,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(animation),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _withFilePagination(context, controller, child),
    );
  }

  /// 加载占位符，空间切换时显示。
  Widget _buildLoadingPlaceholder(BuildContext context) {
    final c = context.filesColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context).importUploading,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileView(
    BuildContext context,
    WidgetRef ref,
    FileBrowserController controller,
  ) {
    final favorites = state.section == FileManagerSection.favorites;
    final actions = _buildFileNodeActions(
      context,
      ref,
      controller,
      recycle: recycle,
      favorites: favorites,
    );

    if (!narrow && state.viewMode == FileBrowserViewMode.list) {
      return FileTableView(
        files: state.visibleNodes,
        showingRecycleBin: recycle,
        enabled: actionsEnabled,
        actions: actions,
        sortBy: state.sortBy,
        sortAscending: state.sortAscending,
        onSortByChanged: actionsEnabled ? controller.setSortBy : null,
        onToggleSortAscending:
            actionsEnabled ? controller.toggleSortAscending : null,
        selectedFileIds: state.selectedFileIds,
        inspectedFileId: state.inspectedFileId,
        selectionActive: state.hasSelection,
        showingFavorites: favorites,
        favoriteIds: state.favoriteIdSet,
        draftFolderName: state.draftFolderName,
        onDraftFolderSubmit:
            actionsEnabled ? controller.commitFolderCreation : null,
        onDraftFolderCancel: controller.cancelFolderCreation,
        onToggleSelectAll:
            actionsEnabled && state.visibleNodes.isNotEmpty
                ? () {
                  state.selectedFileIds.length >= state.visibleNodes.length
                      ? controller.clearSelection()
                      : controller.selectAll();
                }
                : null,
      );
    }
    if (state.viewMode == FileBrowserViewMode.grid) {
      return FileGrid(
        files: state.visibleNodes,
        showingRecycleBin: recycle,
        enabled: actionsEnabled,
        actions: actions,
        selectedFileIds: state.selectedFileIds,
        inspectedFileId: state.inspectedFileId,
        selectionActive: state.hasSelection,
        showingFavorites: favorites,
        favoriteIds: state.favoriteIdSet,
        draftFolderName: state.draftFolderName,
        onDraftFolderSubmit:
            actionsEnabled ? controller.commitFolderCreation : null,
        onDraftFolderCancel: controller.cancelFolderCreation,
      );
    }
    return FileList(
      files: state.visibleNodes,
      showingRecycleBin: recycle,
      enabled: actionsEnabled,
      actions: actions,
      selectedFileIds: state.selectedFileIds,
      inspectedFileId: state.inspectedFileId,
      selectionActive: state.hasSelection,
      favoriteIds: state.favoriteIdSet,
      showingFavorites: favorites,
      draftFolderName: state.draftFolderName,
      onDraftFolderSubmit:
          actionsEnabled ? controller.commitFolderCreation : null,
      onDraftFolderCancel: controller.cancelFolderCreation,
    );
  }

  Widget _withFilePagination(
    BuildContext context,
    FileBrowserController controller,
    Widget child,
  ) {
    // 按分区分派分页条：主列表（全部文件/共享空间）与最近/收藏/回收站
    // 三分区各自携带分页元数据；跳页即按目标页重拉当前分区。分页条
    // 与子页/Admin 一致常驻渲染：单页时仅导航钮禁用，总数与每页条数
    // 始终可见。各分区默认与候选统一为组件默认（10/20/50/100）。
    final (meta, onPage, onPageSize) = switch (state.section) {
      FileManagerSection.allFiles || FileManagerSection.sharedSpace => (
        FilesSubPageMeta(
          page: state.filePage,
          size: state.filePageSize,
          totalElements: state.fileTotalElements,
          totalPages: state.fileTotalPages,
        ),
        (int page) => controller.goToFilePage(page),
        (int size) => controller.setFilePageSize(size),
      ),
      FileManagerSection.recent => (
        state.recentMeta,
        (int page) => controller.showRecentFiles(page: page),
        (int size) => controller.showRecentFiles(page: 0, size: size),
      ),
      FileManagerSection.favorites => (
        state.favoritesMeta,
        (int page) => controller.showFavoriteFiles(page: page),
        (int size) => controller.showFavoriteFiles(page: 0, size: size),
      ),
      FileManagerSection.recycleBin => (
        state.recycleMeta,
        (int page) => controller.showRecycleBin(page: page),
        (int size) => controller.showRecycleBin(page: 0, size: size),
      ),
      _ => (null, null, null),
    };
    if (meta == null) {
      return child;
    }
    return Column(
      children: [
        Expanded(child: child),
        WorkstationPaginationBar(
          currentPage: meta.page,
          totalPages: meta.totalPages,
          totalElements: meta.totalElements,
          rowsPerPage: meta.size,
          busy: state.isBusy,
          onPageChanged:
              (page) => unawaited(_runFileAction(context, () => onPage!(page))),
          onRowsPerPageChanged:
              (size) =>
                  unawaited(_runFileAction(context, () => onPageSize!(size))),
        ),
      ],
    );
  }
}

/// 指标卡条：模板四卡形态（label 10px mono / 值 24px headline / 说明行）。
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state, required this.maxWidth});

  final FileBrowserState state;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.filesColors;
    final stats = state.stats;
    final cards = [
      _MetricCard(
        label: l10n.filesFolders,
        value: stats.folderCount.toString(),
        detail: l10n.filesCurrentView,
        color: colors.onSurface,
      ),
      _MetricCard(
        label: l10n.filesFiles,
        value: stats.fileCount.toString(),
        detail: l10n.filesCurrentView,
        color: colors.onSurface,
      ),
      _MetricCard(
        label: l10n.filesCapacity,
        value: formatFileSize(stats.totalSizeBytes),
        detail: l10n.filesCurrentViewTotal,
        color: colors.onSurface,
      ),
      _MetricCard(
        label: l10n.filesRecycleBin,
        value: state.recycleBin.length.toString(),
        detail: l10n.filesSoftDeleted,
        color: colors.error,
      ),
    ];
    final columns = maxWidth >= 920 ? 4 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                child: card,
              ),
          ],
        );
      },
    );
  }
}

/// 构造三视图与 Inspector 共用的节点操作回调集合。
FileNodeActionCallbacks _buildFileNodeActions(
  BuildContext context,
  WidgetRef ref,
  FileBrowserController controller, {
  required bool recycle,
  required bool favorites,
}) {
  final l10n = AppLocalizations.of(context);
  final isShared =
      ref.read(fileBrowserControllerProvider).asData?.value.spaceType ==
      'SHARED';
  final canManageActivity =
      ref.watch(userCapabilitiesProvider).canManageOwnActivity;
  final favoriteIds =
      ref.read(fileBrowserControllerProvider).asData?.value.favoriteIdSet ??
      const <String>{};
  return FileNodeActionCallbacks(
    onOpen:
        (file) => unawaited(
          _runFileAction(context, () => controller.openFolder(file)),
        ),
    onRename:
        (file) => _showNameDialog(
          context: context,
          title: l10n.filesRename,
          actionLabel: l10n.filesSave,
          labelText: l10n.filesFileName,
          initialValue: file.name,
          onSubmit: (name) => controller.renameFile(file, name),
        ),
    onDelete:
        (file) => _confirmAndRun(
          context,
          title: l10n.filesDeleteConfirmTitle(file.name),
          message: l10n.filesDeleteConfirmMessage(file.name),
          confirmLabel: l10n.filesMoveToRecycleBin,
          action: () => controller.deleteFile(file),
        ),
    onPurge:
        (file) => _confirmTypedAndRun(
          context,
          title: l10n.filesPurgeConfirmTitle(file.name),
          message: l10n.filesPurgeConfirmMessage(file.name),
          confirmPhrase: file.name,
          confirmLabel: l10n.filesPurge,
          action: () => controller.purgeFile(file),
        ),
    onRestore:
        (file) => unawaited(
          _runFileAction(context, () => controller.restoreFile(file)),
        ),
    onCopy:
        recycle || isShared
            ? null
            : (file) => _showCopyDialog(
              context: context,
              controller: controller,
              file: file,
            ),
    onShowVersions:
        recycle || isShared
            ? null
            : (file) => _showVersionsDialog(
              context: context,
              controller: controller,
              file: file,
            ),
    onMove:
        recycle
            ? null
            : (file) => _showMoveDialog(
              context: context,
              controller: controller,
              file: file,
            ),
    onMoveToSharedSpace:
        recycle || isShared
            ? null
            : (file) => _confirmAndRun(
              context,
              title: l10n.filesMoveToSharedConfirm,
              message: l10n.filesMoveToSharedMessage(file.name),
              confirmLabel: l10n.filesMoveToShared,
              action: () => controller.moveToSharedSpace(file),
            ),
    onMoveToPersonalSpace:
        recycle || !isShared
            ? null
            : (file) => _confirmAndRun(
              context,
              title: l10n.filesMoveToPersonalConfirm,
              message: l10n.filesMoveToPersonalMessage(file.name),
              confirmLabel: l10n.filesMoveToPersonalLabel,
              action: () => controller.moveToPersonalSpace(file),
            ),
    onDownload:
        recycle
            ? null
            : (file) => unawaited(_downloadFile(context, controller, file)),
    onShare:
        recycle ? null : (file) => ShareLinkSheet.show(context, file: file),
    onToggleFavorite:
        recycle || !canManageActivity
            ? null
            : (file) => unawaited(() async {
              // 按实际收藏态切换，而非分区：全部文件里已收藏的行再点
              // 必须走取消收藏，分区判断会让二次点击永远重复收藏。
              final removing = favoriteIds.contains(file.id);
              final ok = await _runFileAction(
                context,
                removing
                    ? () => controller.removeFavorite(file)
                    : () => controller.addFavorite(file),
              );
              if (!ok || !context.mounted) {
                return;
              }
              showOmniFeedback(
                context,
                removing ? l10n.favoriteRemoved : l10n.favoriteAdded,
                severity: OmniFeedbackSeverity.success,
              );
            }()),
    onPreview: recycle ? null : (file) => _openFilePreview(context, file),
    onToggleSelection: controller.toggleSelection,
    onInspect: controller.inspectNode,
  );
}

/// 桌面端文件预览以大尺寸居中弹窗呈现（模板弹窗形态）；
/// 移动/托管端保持全屏页面。
void _openFilePreview(BuildContext context, FileNode file) {
  final desktop =
      MediaQuery.sizeOf(context).width >= 600 &&
      !MobileShellScope.isHosted(context);
  if (!desktop) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FilePreviewPage(file: file)));
    return;
  }
  unawaited(
    showFilesDialog<void>(
      context: context,
      builder: (dialogContext) => _FilePreviewDialog(file: file),
    ),
  );
}

/// 桌面预览弹窗：86vw×88vh 常规形态与整窗全屏形态间切换；
/// Esc 任何时候直接关闭（播放器不吞键），全屏切换钮常驻右上角。
class _FilePreviewDialog extends StatefulWidget {
  const _FilePreviewDialog({required this.file});

  final FileNode file;

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = _expanded ? size.width : size.width * 0.86;
    final height = _expanded ? size.height : size.height * 0.88;
    final colors = context.filesColors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: colors.surfaceContainer,
          child: AnimatedContainer(
            duration: MotionToken.fast,
            width: width,
            height: height,
            decoration: BoxDecoration(
              border:
                  _expanded ? null : Border.all(color: colors.selectedBorder),
            ),
            child: Column(
              children: [
                // 紧凑头部：名称+大小居左，全屏与关闭钮居右，36px 高，
                // 取代旧 AppBar（返回钮过大/标题过大/大小与悬浮钮重叠）。
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppTypography.bodyMedium,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatFileSize(widget.file.sizeBytes),
                              style: TextStyle(
                                fontFamily: AppTypography.monoFamily,
                                fontFamilyFallback:
                                    AppTypography.monoFamilyFallback,
                                fontSize: AppTypography.labelSmall,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilesToolbarIconButton(
                        tooltip:
                            _expanded
                                ? l10n.filesPreviewExitFullscreen
                                : l10n.filesPreviewFullscreen,
                        icon:
                            _expanded
                                ? Icons.fullscreen_exit_rounded
                                : Icons.open_in_full_rounded,
                        onPressed: () => setState(() => _expanded = !_expanded),
                      ),
                      FilesToolbarIconButton(
                        tooltip:
                            MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: FilePreviewPage(file: widget.file, embedded: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
