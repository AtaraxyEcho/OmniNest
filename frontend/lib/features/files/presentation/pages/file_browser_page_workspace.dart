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
      FileManagerSection.myShares => _ShareWorkspace(
        title: AppLocalizations.of(context).filesMyShares,
        subtitle: FileManagerSection.myShares.descriptionOf(
          AppLocalizations.of(context),
        ),
        shares: state.myShares,
        state: state,
      ),
      FileManagerSection.shareManagement => _ShareWorkspace(
        title: AppLocalizations.of(context).filesShareManagement,
        subtitle: FileManagerSection.shareManagement.descriptionOf(
          AppLocalizations.of(context),
        ),
        shares: state.shareLinks,
        managementMode: true,
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
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final recycle = state.section == FileManagerSection.recycleBin;
    final actionsEnabled = !state.isBusy;
    final isNarrow = MediaQuery.of(context).size.width < 900;

    // ── 窄屏布局 ──
    if (isNarrow) {
      return FileDropUploadSurface(
        enabled: state.section == FileManagerSection.allFiles && actionsEnabled,
        onFilesDropped: (files) => _uploadFiles(context, controller, files),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.section == FileManagerSection.allFiles) ...[
              // 极简工具区：面包屑内联空间切换，排序/类型筛选收进面板，
              // 视图切换为单钮（原 4 行工具区压缩为 1 行）。
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
            if (state.hasSelection) ...[
              const SizedBox(height: 10),
              _BatchSelectionBar(state: state),
            ],
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: MotionToken.resolve(context, MotionToken.normal),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child:
                  state.isBusy && state.section == FileManagerSection.allFiles
                      ? KeyedSubtree(
                        key: const ValueKey('_loading'),
                        child: _buildLoadingPlaceholder(context),
                      )
                      : KeyedSubtree(
                        key: ValueKey(
                          '${state.spaceType}_${state.parentId}_${state.viewMode.name}',
                        ),
                        child: _buildFileView(
                          context,
                          controller,
                          l10n,
                          recycle,
                          actionsEnabled,
                        ),
                      ),
            ),
          ],
        ),
      );
    }

    // ── 宽屏布局（原有） ──
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeader(
          title: state.section.labelOf(l10n),
          subtitle: state.section.descriptionOf(l10n),
          actions: [
            if (state.section == FileManagerSection.allFiles) ...[
              FilledButton.icon(
                style: _fileHeaderActionButtonStyle(),
                onPressed:
                    actionsEnabled
                        ? () => _pickAndUploadFiles(context, controller)
                        : null,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(AppLocalizations.of(context).filesUploadFile),
              ),
              OutlinedButton.icon(
                style: _fileHeaderActionButtonStyle(),
                onPressed:
                    actionsEnabled
                        ? () => unawaited(
                          _showNameDialog(
                            context: context,
                            title: AppLocalizations.of(context).filesNewFolder,
                            actionLabel:
                                AppLocalizations.of(context).filesCreate,
                            labelText:
                                AppLocalizations.of(context).filesFolderName,
                            onSubmit: controller.createFolder,
                          ),
                        )
                        : null,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text(AppLocalizations.of(context).filesNewFolder),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 920) {
              return _StatsRow(state: state);
            }
            return _StorageProminentCard(stats: state.storageStats);
          },
        ),
        if (state.section == FileManagerSection.allFiles &&
            state.inlineUploadTasks.isNotEmpty) ...[
          const SizedBox(height: 18),
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
        const SizedBox(height: 18),
        FileDropUploadSurface(
          enabled:
              state.section == FileManagerSection.allFiles && actionsEnabled,
          onFilesDropped: (files) => _uploadFiles(context, controller, files),
          child: WorkbenchPanel(
            padding: const EdgeInsets.all(20),
            backgroundColor: context.filesColors.surfaceContainer,
            child: Column(
              children: [
                _FileToolbar(state: state),
                if (state.section == FileManagerSection.allFiles) ...[
                  const SizedBox(height: 14),
                  _Breadcrumbs(state: state),
                  const SizedBox(height: 14),
                  _FileCategoryFilter(state: state),
                ],
                const SizedBox(height: 20),
                if (state.hasSelection) ...[
                  _BatchSelectionBar(state: state),
                  const SizedBox(height: 14),
                ],
                AnimatedSwitcher(
                  duration: MotionToken.resolve(context, MotionToken.normal),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child:
                      state.isBusy &&
                              state.section == FileManagerSection.allFiles
                          ? KeyedSubtree(
                            key: const ValueKey('_loading'),
                            child: _buildLoadingPlaceholder(context),
                          )
                          : KeyedSubtree(
                            key: ValueKey(
                              '${state.spaceType}_${state.parentId}_${state.viewMode.name}',
                            ),
                            child: _buildFileView(
                              context,
                              controller,
                              l10n,
                              recycle,
                              actionsEnabled,
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ],
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
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: c.primary,
              ),
            ),
            const SizedBox(height: 16),
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

  /// 根据用户选择构建列表或网格文件视图。
  Widget _buildFileView(
    BuildContext context,
    FileBrowserController controller,
    AppLocalizations l10n,
    bool recycle,
    bool actionsEnabled,
  ) {
    final isShared = state.spaceType == 'SHARED';
    final favorites = state.section == FileManagerSection.favorites;
    if (state.viewMode == FileBrowserViewMode.list) {
      return _withFilePagination(
        context,
        controller,
        FileList(
          files: state.visibleNodes,
          showingRecycleBin: recycle,
          enabled: actionsEnabled,
          selectedFileIds: state.selectedFileIds,
          onToggleSelection: controller.toggleSelection,
          selectionActive: state.hasSelection,
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
              (file) => _confirmAndRun(
                context,
                title: l10n.filesPurgeConfirmTitle(file.name),
                message: l10n.filesPurgeConfirmMessage(file.name),
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
                  : (file) =>
                      unawaited(_downloadFile(context, controller, file)),
          onShare:
              recycle
                  ? null
                  : (file) => ShareLinkSheet.show(context, file: file),
          onToggleFavorite:
              recycle
                  ? null
                  : (file) => unawaited(
                    _runFileAction(
                      context,
                      favorites
                          ? () => controller.removeFavorite(file)
                          : () => controller.addFavorite(file),
                    ),
                  ),
          showingFavorites: favorites,
          onPreview:
              recycle
                  ? null
                  : (file) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FilePreviewPage(file: file),
                    ),
                  ),
        ),
      );
    }
    return _withFilePagination(
      context,
      controller,
      FileGrid(
        files: state.visibleNodes,
        showingRecycleBin: recycle,
        enabled: actionsEnabled,
        selectedFileIds: state.selectedFileIds,
        onToggleSelection: controller.toggleSelection,
        selectionActive: state.hasSelection,
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
            (file) => _confirmAndRun(
              context,
              title: l10n.filesPurgeConfirmTitle(file.name),
              message: l10n.filesPurgeConfirmMessage(file.name),
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
            recycle
                ? null
                : (file) => unawaited(
                  _runFileAction(
                    context,
                    favorites
                        ? () => controller.removeFavorite(file)
                        : () => controller.addFavorite(file),
                  ),
                ),
        showingFavorites: favorites,
        onPreview:
            recycle
                ? null
                : (file) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FilePreviewPage(file: file),
                  ),
                ),
      ),
    );
  }

  Widget _withFilePagination(
    BuildContext context,
    FileBrowserController controller,
    Widget child,
  ) {
    if (!state.hasMoreFiles && !state.isLoadingMoreFiles) {
      return child;
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        child,
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed:
              state.isLoadingMoreFiles
                  ? null
                  : () => unawaited(
                    _runFileAction(context, controller.loadMoreFiles),
                  ),
          icon:
              state.isLoadingMoreFiles
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.expand_more_rounded, size: 20),
          label: Text(
            l10n.filesLoadMore(state.files.length, state.fileTotalElements),
          ),
        ),
      ],
    );
  }
}

class _BatchSelectionBar extends ConsumerWidget {
  const _BatchSelectionBar({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final recycle = state.section == FileManagerSection.recycleBin;
    final favorites = state.section == FileManagerSection.favorites;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.filesColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.filesColors.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 选择信息行
          Row(
            children: [
              Text(
                l10n.filesSelectedCount(state.selectionCount),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTypography.bodyLarge,
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: enabled ? controller.selectAll : null,
                child: Text(l10n.filesSelectAll),
              ),
              TextButton(
                onPressed: enabled ? controller.clearSelection : null,
                child: Text(l10n.filesDeselect),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 操作按钮行（可换行）
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (recycle) ...[
                  _BatchActionButton(
                    label: l10n.filesBatchRestore,
                    icon: Icons.restore_rounded,
                    enabled: enabled,
                    onTap:
                        () => _confirmAndRun(
                          context,
                          title: l10n.filesBatchRestoreTitle,
                          message: l10n.filesBatchRestoreMessage(
                            state.selectionCount,
                          ),
                          confirmLabel: l10n.filesRestore,
                          action: controller.batchRestoreFiles,
                        ),
                  ),
                  _BatchActionButton(
                    label: l10n.filesBatchPurge,
                    icon: Icons.delete_forever_outlined,
                    enabled: enabled,
                    destructive: true,
                    onTap:
                        () => _confirmAndRun(
                          context,
                          title: l10n.filesBatchPurgeTitle,
                          message: l10n.filesBatchPurgeMessage(
                            state.selectionCount,
                          ),
                          confirmLabel: l10n.filesPurge,
                          action: controller.batchPurgeFiles,
                        ),
                  ),
                ] else ...[
                  _BatchActionButton(
                    label: l10n.filesBatchMove,
                    icon: Icons.drive_file_move_outlined,
                    enabled: enabled,
                    onTap:
                        () => _showBatchMoveDialog(
                          context: context,
                          controller: controller,
                          count: state.selectionCount,
                          excludeIds: state.selectedFileIds,
                        ),
                  ),
                  _BatchActionButton(
                    label: l10n.filesBatchDelete,
                    icon: Icons.delete_outline_rounded,
                    enabled: enabled,
                    destructive: true,
                    onTap:
                        () => _confirmAndRun(
                          context,
                          title: l10n.filesBatchDeleteTitle,
                          message: l10n.filesBatchDeleteMessage(
                            state.selectionCount,
                          ),
                          confirmLabel: l10n.filesMoveToRecycleBin,
                          action: controller.batchDeleteFiles,
                        ),
                  ),
                  _BatchActionButton(
                    label:
                        favorites
                            ? l10n.filesBatchRemoveFavorite
                            : l10n.filesBatchAddFavorite,
                    icon:
                        favorites
                            ? Icons.star_border_rounded
                            : Icons.star_rounded,
                    enabled: enabled,
                    onTap:
                        () => unawaited(
                          _runFileAction(
                            context,
                            favorites
                                ? controller.batchRemoveFavorites
                                : controller.batchAddFavorites,
                          ),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive
            ? context.filesColors.error
            : context.filesColors.onSurfaceVariant;
    return TextButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18, color: enabled ? color : null),
      label: Text(label, style: TextStyle(color: enabled ? color : null)),
    );
  }
}

/// 移动端突出显示的存储卡片，展示已用空间和剩余空间。
class _StorageProminentCard extends StatelessWidget {
  const _StorageProminentCard({required this.stats});

  final FileStorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = stats?.usageRatio ?? 0;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(16),
      backgroundColor: context.filesColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, color: context.filesColors.primary),
              const SizedBox(width: 12),
              Text(
                l10n.filesStorageSpace,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            stats == null ? '---' : formatFileSize(stats!.usedBytes),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: value, minHeight: 8),
          const SizedBox(height: 8),
          Text(
            stats == null
                ? l10n.filesWaitingStats
                : stats!.isQuotaUnlimited
                ? '${formatFileSize(stats!.usedBytes)} · ${l10n.filesUnlimitedQuota}'
                : l10n.filesUsedPercent(
                  (value * 100).round(),
                  formatFileSize(stats!.quotaBytes - stats!.usedBytes),
                ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats = state.stats;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _MetricCard(
            label: l10n.filesFolders,
            value: stats.folderCount.toString(),
            detail: l10n.filesCurrentView,
            icon: Icons.folder_outlined,
            color: context.filesColors.tertiary,
          ),
          _MetricCard(
            label: l10n.filesFiles,
            value: stats.fileCount.toString(),
            detail: l10n.filesCurrentView,
            icon: Icons.insert_drive_file_outlined,
            color: context.filesColors.primary,
          ),
          _MetricCard(
            label: l10n.filesCapacity,
            value: formatFileSize(stats.totalSizeBytes),
            detail: l10n.filesCurrentViewTotal,
            icon: Icons.donut_large_rounded,
            color: context.filesColors.storageAccent,
          ),
          _MetricCard(
            label: l10n.filesRecycleBin,
            value: state.recycleBin.length.toString(),
            detail: l10n.filesSoftDeleted,
            icon: Icons.delete_sweep_outlined,
            color: context.filesColors.error,
          ),
        ];
        if (constraints.maxWidth >= 920) {
          return Row(
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 14),
              ],
            ],
          );
        }
        return Wrap(spacing: 14, runSpacing: 14, children: cards);
      },
    );
  }
}
