part of 'file_browser_page.dart';

class _ExternalStorageWorkspace extends ConsumerWidget {
  const _ExternalStorageWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final browsingAccountId = state.externalBrowseAccountId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SimpleListSurface(
          title: FileManagerSection.externalStorage.labelOf(l10n),
          subtitle: FileManagerSection.externalStorage.descriptionOf(l10n),
          emptyText: l10n.filesNoExternalStorage,
          actions: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed:
                  enabled
                      ? () => unawaited(
                        _showExternalStorageDialog(
                          context: context,
                          ref: ref,
                          onSubmit: controller.createExternalStorage,
                        ),
                      )
                      : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.filesAddMount),
            ),
          ],
          children:
              state.externalAccounts
                  .map(
                    (account) => _InfoRow(
                      icon: Icons.cloud_queue_rounded,
                      title: account.displayName,
                      subtitle:
                          account.lastErrorCode == null
                              ? '${account.provider} · ${account.status}'
                              : '${account.provider} · ${account.status} · ${account.lastErrorCode}',
                      trailingWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.filesEdit,
                            onPressed:
                                enabled
                                    ? () => _showExternalStorageDialog(
                                      context: context,
                                      ref: ref,
                                      account: account,
                                      onSubmit:
                                          ({
                                            required String provider,
                                            required String displayName,
                                            required String
                                            encryptedCredentials,
                                          }) =>
                                              controller.updateExternalStorage(
                                                accountId: account.id,
                                                displayName: displayName,
                                                encryptedCredentials:
                                                    encryptedCredentials,
                                              ),
                                    )
                                    : null,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: l10n.filesTestConnection,
                            onPressed:
                                enabled
                                    ? () => unawaited(
                                      _runFileAction(
                                        context,
                                        () => controller
                                            .testExternalStorageConnection(
                                              account.id,
                                            ),
                                      ),
                                    )
                                    : null,
                            icon: const Icon(Icons.wifi_tethering_rounded),
                          ),
                          if (_isOAuthProvider(account.provider))
                            IconButton(
                              tooltip: l10n.filesAuthorizeAccount,
                              onPressed:
                                  enabled
                                      ? () => unawaited(
                                        _startOAuthAuthorize(
                                          context,
                                          ref,
                                          controller,
                                          account,
                                        ),
                                      )
                                      : null,
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                          IconButton(
                            tooltip: l10n.filesBrowseRemote,
                            onPressed:
                                enabled
                                    ? () => unawaited(
                                      _runFileAction(
                                        context,
                                        () => controller.browseExternalStorage(
                                          account.id,
                                        ),
                                      ),
                                    )
                                    : null,
                            icon: const Icon(Icons.folder_open_rounded),
                          ),
                          IconButton(
                            tooltip: l10n.filesDisableMount,
                            onPressed:
                                enabled
                                    ? () => _confirmAndRun(
                                      context,
                                      title: l10n.filesDisableMountConfirm,
                                      message: l10n.filesDisableMountMessage(
                                        account.displayName,
                                      ),
                                      confirmLabel: l10n.filesDisableMount,
                                      action:
                                          () => controller
                                              .disableExternalStorage(account),
                                    )
                                    : null,
                            icon: const Icon(Icons.block_rounded),
                          ),
                          IconButton(
                            tooltip: l10n.filesDeleteMount,
                            onPressed:
                                enabled
                                    ? () => _confirmAndRun(
                                      context,
                                      title: l10n.filesDeleteMountConfirm,
                                      message: l10n.filesDeleteMountMessage(
                                        account.displayName,
                                      ),
                                      confirmLabel: l10n.filesDelete,
                                      action:
                                          () => controller
                                              .deleteExternalStorage(account),
                                    )
                                    : null,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: context.filesColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
        if (browsingAccountId != null) ...[
          const SizedBox(height: 20),
          _ExternalBrowsePanel(state: state),
        ],
      ],
    );
  }

  bool _isOAuthProvider(String provider) {
    final code = provider.toUpperCase();
    return code == 'ONEDRIVE' ||
        code == 'GDRIVE' ||
        code == 'GOOGLE_DRIVE' ||
        code == 'DROPBOX';
  }

  Future<void> _startOAuthAuthorize(
    BuildContext context,
    WidgetRef ref,
    FileBrowserController controller,
    ExternalStorageAccount account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await controller.startExternalOAuth(
        connectorCode: account.provider,
        accountId: account.id,
      );
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(l10n.filesAuthorizeAccount),
              content: SelectableText('${l10n.filesAuthorizeHint}\n\n$url'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.filesCancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final copied = await copyTextToClipboard(url);
                    if (!copied) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(l10n.clipboardCopyFailed)),
                        );
                      }
                      return;
                    }
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(l10n.filesCopyLink),
                ),
              ],
            ),
      );
      if (context.mounted) {
        await controller.showExternalStorage();
      }
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeUserFacingError(error).message)),
      );
    }
  }
}

class _ExternalBrowsePanel extends ConsumerWidget {
  const _ExternalBrowsePanel({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final browsePath = state.externalBrowsePath ?? '/';
    final accountId = state.externalBrowseAccountId!;
    final segments = browsePath.split('/').where((s) => s.isNotEmpty).toList();
    final space = state.externalSpace;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(20),
      backgroundColor: context.filesColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 面包屑导航行
          Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [
                    _BreadcrumbChip(
                      label: '/',
                      onTap:
                          enabled
                              ? () => unawaited(
                                _runFileAction(
                                  context,
                                  () => controller.browseExternalSubdirectory(
                                    accountId,
                                    '/',
                                  ),
                                ),
                              )
                              : null,
                    ),
                    for (var i = 0; i < segments.length; i++)
                      _BreadcrumbChip(
                        label: segments[i],
                        onTap:
                            enabled
                                ? () => unawaited(
                                  _runFileAction(
                                    context,
                                    () => controller.browseExternalSubdirectory(
                                      accountId,
                                      '/${segments.take(i + 1).join('/')}',
                                    ),
                                  ),
                                )
                                : null,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.filesCloseBrowse,
                onPressed: controller.closeExternalBrowse,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          // 空间用量卡片
          if (space != null) ...[
            const SizedBox(height: 12),
            _ExternalSpaceCard(space: space, l10n: l10n),
          ],
          const SizedBox(height: 16),
          if (state.isExternalBrowseLoading)
            const _ExternalBrowseLoading()
          else if (state.externalBrowseError case final message?)
            _ExternalBrowseFailure(
              message: message,
              onRetry:
                  () => unawaited(
                    _runFileAction(
                      context,
                      () => controller.browseExternalStorage(
                        accountId,
                        path: browsePath,
                      ),
                    ),
                  ),
            )
          else if (state.externalFiles.isEmpty)
            _EmptyPanel(text: l10n.filesDirectoryEmpty)
          else
            for (final item in state.externalFiles)
              _InfoRow(
                icon:
                    item.isDir
                        ? Icons.folder_rounded
                        : Icons.insert_drive_file_outlined,
                title: item.name,
                subtitle:
                    item.isDir
                        ? l10n.filesFolder
                        : formatFileSize(item.sizeBytes),
                trailingWidget: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.isDir) ...[
                      IconButton(
                        tooltip: l10n.filesEnterFolder,
                        onPressed:
                            enabled
                                ? () => unawaited(
                                  _runFileAction(
                                    context,
                                    () => controller.browseExternalSubdirectory(
                                      accountId,
                                      item.path,
                                    ),
                                  ),
                                )
                                : null,
                        icon: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.filesImportFolder,
                        onPressed:
                            enabled
                                ? () => _importExternalItem(
                                  context,
                                  controller,
                                  accountId,
                                  item.path,
                                  item.name,
                                  sourceKind: 'DIRECTORY',
                                )
                                : null,
                        icon: const Icon(
                          Icons.drive_folder_upload_outlined,
                          size: 18,
                        ),
                      ),
                    ] else
                      IconButton(
                        tooltip: l10n.filesImportFile,
                        onPressed:
                            enabled
                                ? () => _importExternalItem(
                                  context,
                                  controller,
                                  accountId,
                                  item.path,
                                  item.name,
                                  sourceKind: 'FILE',
                                )
                                : null,
                        icon: const Icon(Icons.download_rounded, size: 18),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// 导入外部文件，先弹出空间选择器。
  Future<void> _importExternalItem(
    BuildContext context,
    FileBrowserController controller,
    String accountId,
    String path,
    String fileName, {
    required String sourceKind,
  }) async {
    final l10n = AppLocalizations.of(context);

    final spaceSelection = await showSpaceSelectorSheet(context);
    if (spaceSelection == null || !context.mounted) return;

    final spaceType =
        spaceSelection == SpaceSelection.shared ? 'SHARED' : 'PERSONAL';

    await _confirmAndRun(
      context,
      title: l10n.filesImportConfirm,
      message:
          '${l10n.filesImportMessage(fileName)}\n${l10n.filesImportSizeGuardHint}',
      confirmLabel: l10n.filesImport,
      action:
          () => controller.createImportTask(
            accountId,
            path,
            sourceKind: sourceKind,
            spaceType: spaceType,
          ),
    );
  }
}

class _ExternalBrowseLoading extends StatelessWidget {
  const _ExternalBrowseLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 144,
      child: Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: context.filesColors.primary,
          ),
        ),
      ),
    );
  }
}

class _ExternalBrowseFailure extends StatelessWidget {
  const _ExternalBrowseFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 124),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  color: context.filesColors.error,
                  size: 28,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.filesColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.coreRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 外部存储空间用量卡片
class _ExternalSpaceCard extends StatelessWidget {
  const _ExternalSpaceCard({required this.space, required this.l10n});

  final ExternalSpaceUsage space;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_outline_rounded,
                size: 16,
                color: context.filesColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.externalStorageSpace,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: space.usagePercent,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.externalSpaceUsedOf(
              formatFileSize(space.usedBytes),
              formatFileSize(space.totalBytes),
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.filesColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color:
                onTap != null
                    ? context.filesColors.primary
                    : context.filesColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ImportTasksWorkspace extends ConsumerWidget {
  const _ImportTasksWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    return _SimpleListSurface(
      title: FileManagerSection.importTasks.labelOf(l10n),
      subtitle: FileManagerSection.importTasks.descriptionOf(l10n),
      emptyText: l10n.filesNoImportTasks,
      children:
          state.importTasks
              .map(
                (task) => _ImportTaskTile(
                  task: task,
                  enabled: enabled,
                  onCancel:
                      () => _confirmAndRun(
                        context,
                        title: l10n.filesCancelImportConfirm,
                        message: l10n.filesCancelImportMessage(
                          task.fileName ?? task.sourcePath,
                        ),
                        confirmLabel: l10n.filesCancel,
                        action: () => controller.cancelImportTask(task),
                      ),
                  onDelete:
                      () => _confirmAndRun(
                        context,
                        title: l10n.filesDeleteImportConfirm,
                        message: l10n.filesDeleteImportMessage(
                          task.fileName ?? task.sourcePath,
                        ),
                        confirmLabel: l10n.filesDelete,
                        action: () => controller.deleteImportTask(task),
                      ),
                ),
              )
              .toList(),
    );
  }
}

String _importTaskSubtitle(ImportTask task, AppLocalizations l10n) {
  final status = switch (task.status.toUpperCase()) {
    'QUEUED' => l10n.filesImportQueued,
    'SCANNING' => l10n.filesImportScanning,
    'TRANSFERRING' => l10n.filesImportTransferring,
    'IMPORTING' => l10n.filesImportWriting,
    'RUNNING' => l10n.filesImportRunning,
    'CANCELLING' => l10n.filesImportCancelling,
    'CANCELLED' => l10n.filesImportCancelled,
    'COMPLETED' => l10n.filesStatusCompleted,
    'FAILED' => l10n.filesStatusFailed,
    _ => task.status,
  };
  final errorText =
      task.errorSummary == null || task.errorSummary!.isEmpty
          ? ''
          : ' · ${task.errorSummary}';
  final waitingForWorker =
      task.status.toUpperCase() == 'QUEUED' &&
      task.updatedAt != null &&
      DateTime.now().difference(task.updatedAt!).inSeconds >= 20;
  final waitingText =
      waitingForWorker ? ' · ${l10n.filesImportWaitingWorker}' : '';
  return '$status$waitingText$errorText';
}

String _importTaskTrailing(ImportTask task) {
  final speed =
      task.speedBytes > 0 ? ' · ${formatFileSize(task.speedBytes)}/s' : '';
  if (task.totalBytes <= 0) {
    return speed.isEmpty ? '' : '${formatFileSize(task.speedBytes)}/s';
  }
  return '${(task.progress * 100).toStringAsFixed(0)}% · '
      '${formatFileSize(task.transferredBytes)} / ${formatFileSize(task.totalBytes)}'
      '$speed';
}

class _ImportTaskTile extends StatelessWidget {
  const _ImportTaskTile({
    required this.task,
    required this.enabled,
    required this.onCancel,
    required this.onDelete,
  });

  final ImportTask task;
  final bool enabled;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = task.status.toUpperCase();
    final hasByteProgress = task.totalBytes > 0;
    final isIndeterminate = task.isActive && !hasByteProgress;
    final currentFile = task.currentFileName;
    final fileProgress =
        task.totalFiles > 0
            ? l10n.filesImportFileProgress(task.completedFiles, task.totalFiles)
            : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            task.isDirectory
                ? Icons.folder_copy_outlined
                : Icons.cloud_download_outlined,
            color: context.filesColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName ?? task.sourcePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _importTaskSubtitle(task, l10n),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        status == 'FAILED'
                            ? context.filesColors.error
                            : context.filesColors.onSurfaceVariant,
                  ),
                ),
                if (task.isActive || hasByteProgress) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: isIndeterminate ? null : task.progress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
                if (fileProgress != null || currentFile != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (fileProgress != null) fileProgress,
                      if (currentFile != null && currentFile.isNotEmpty)
                        l10n.filesImportCurrentFile(currentFile),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.filesColors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_importTaskTrailing(task).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _importTaskTrailing(task),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip:
                task.canCancel ? l10n.filesCancelTask : l10n.filesDeleteRecord,
            onPressed: enabled ? (task.canCancel ? onCancel : onDelete) : null,
            icon: Icon(
              task.canCancel ? Icons.close_rounded : Icons.delete_outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleListSurface extends StatelessWidget {
  const _SimpleListSurface({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeader(title: title, subtitle: subtitle, actions: actions),
        const SizedBox(height: 20),
        WorkbenchPanel(
          backgroundColor: context.filesColors.surfaceContainer,
          padding: const EdgeInsets.all(20),
          child:
              children.isEmpty
                  ? _EmptyPanel(text: emptyText)
                  : Column(children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatefulWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingWidget,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final Widget? trailingWidget;

  @override
  State<_InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<_InfoRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              _hovering
                  ? Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.06)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: context.filesColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.filesColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.trailingWidget != null)
              widget.trailingWidget!
            else if (widget.trailing != null)
              Text(
                widget.trailing!,
                style: Theme.of(context).textTheme.labelMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: context.filesColors.primary,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(text),
        ],
      ),
    );
  }
}
