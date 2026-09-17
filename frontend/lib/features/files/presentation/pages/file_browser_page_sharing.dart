part of 'file_browser_page.dart';

class _SharedWithMeWorkspace extends ConsumerStatefulWidget {
  const _SharedWithMeWorkspace({required this.state});

  final FileBrowserState state;

  @override
  ConsumerState<_SharedWithMeWorkspace> createState() =>
      _SharedWithMeWorkspaceState();
}

class _SharedWithMeWorkspaceState
    extends ConsumerState<_SharedWithMeWorkspace> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(myShareLinksProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sharesAsync = ref.watch(myShareLinksProvider);
    final enabled = !widget.state.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 共享给我的文件
        _SimpleListSurface(
          title: FileManagerSection.sharedWithMe.labelOf(l10n),
          subtitle: FileManagerSection.sharedWithMe.descriptionOf(l10n),
          emptyText: l10n.filesNoSharedFiles,
          children:
              widget.state.sharedWithMe
                  .map(
                    (item) => _InfoRow(
                      icon: Icons.insert_drive_file_outlined,
                      title: item.file.name,
                      subtitle:
                          '${l10n.filesFromUser(item.ownerUserId)} · ${item.expiresAt == null ? l10n.filesLongTerm : l10n.filesHasExpiry}',
                      trailing: formatFileSize(item.file.sizeBytes),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 24),
        // 我的分享管理
        _SimpleListSurface(
          title: l10n.filesShareMgmt,
          subtitle: l10n.filesShareMgmtDesc,
          emptyText: l10n.filesNoShareLinks,
          children: sharesAsync.when(
            loading:
                () => [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ],
            error:
                (e, _) => [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.filesLoadFailed(e.toString()),
                      style: TextStyle(
                        fontSize: AppTypography.bodyMedium,
                        color: context.filesColors.error,
                      ),
                    ),
                  ),
                ],
            data:
                (shares) =>
                    shares
                        .map(
                          (share) => _InfoRow(
                            icon: Icons.link_rounded,
                            title: share.resourceName,
                            subtitle:
                                '${_shareStatusText(share.status, l10n)} · ${share.accessCount}/${share.maxAccessCount ?? l10n.filesAccessUnlimited} · ${share.shareCode}',
                            trailingWidget:
                                share.status.toUpperCase() == 'ACTIVE' &&
                                        enabled
                                    ? IconButton(
                                      tooltip: l10n.filesRevokeShare,
                                      onPressed:
                                          () => _confirmAndRun(
                                            context,
                                            title: l10n.filesRevokeShareConfirm,
                                            message: l10n
                                                .filesRevokeShareMessage(
                                                  share.resourceName,
                                                ),
                                            confirmLabel: l10n.filesRevokeShare,
                                            action:
                                                () => ref
                                                    .read(
                                                      myShareLinksProvider
                                                          .notifier,
                                                    )
                                                    .revokeShare(share.id),
                                          ),
                                      icon: const Icon(Icons.link_off_rounded),
                                    )
                                    : null,
                          ),
                        )
                        .toList(),
          ),
        ),
      ],
    );
  }
}

String _shareStatusText(String status, AppLocalizations l10n) {
  return switch (status.toUpperCase()) {
    'ACTIVE' => l10n.filesShareActive,
    'REVOKED' => l10n.filesShareRevoked,
    'EXPIRED' => l10n.filesShareExpired,
    'EXHAUSTED' => l10n.filesShareExhausted,
    _ => status,
  };
}

class _ShareWorkspace extends ConsumerWidget {
  const _ShareWorkspace({
    required this.title,
    required this.subtitle,
    required this.shares,
    required this.state,
    this.managementMode = false,
  });

  final String title;
  final String subtitle;
  final List<FileShareLink> shares;
  final FileBrowserState state;
  final bool managementMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    return _SimpleListSurface(
      title: title,
      subtitle: subtitle,
      emptyText: l10n.filesNoShareLinks,
      children:
          shares
              .map(
                (share) => _InfoRow(
                  icon: Icons.link_rounded,
                  title: share.resourceName,
                  subtitle:
                      '${_shareStatusText(share.status, l10n)} · ${share.accessCount}/${share.maxAccessCount ?? l10n.filesAccessUnlimited} · ${share.shareCode}',
                  trailingWidget:
                      managementMode && enabled
                          ? IconButton(
                            tooltip: l10n.filesRevokeShare,
                            onPressed:
                                () => _confirmAndRun(
                                  context,
                                  title: l10n.filesRevokeShareConfirm,
                                  message: l10n.filesRevokeShareMessage(
                                    share.resourceName,
                                  ),
                                  confirmLabel: l10n.filesRevokeShare,
                                  action: () => controller.revokeShare(share),
                                ),
                            icon: const Icon(Icons.link_off_rounded),
                          )
                          : null,
                ),
              )
              .toList(),
    );
  }
}

class _UploadQueueWorkspace extends ConsumerWidget {
  const _UploadQueueWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeader(
          title: FileManagerSection.uploadQueue.labelOf(l10n),
          subtitle: FileManagerSection.uploadQueue.descriptionOf(l10n),
        ),
        const SizedBox(height: 20),
        UploadPanel(
          localTasks: state.localUploadTasks,
          enabled: enabled,
          onPauseLocalTask: controller.pauseLocalUploadTask,
          onResumeLocalTask:
              (taskId) => _runFileAction(
                context,
                () => controller.resumeLocalUploadTask(taskId),
              ),
          onRemoveLocalTask:
              (taskId) => _confirmAndRun(
                context,
                title: l10n.filesDeleteUploadTask,
                message: l10n.filesDeleteUploadTaskMessage,
                confirmLabel: l10n.filesDeleteTask,
                action: () => controller.removeLocalUploadTask(taskId),
              ),
          onResolveConflict:
              (taskId) => _confirmAndRun(
                context,
                title: l10n.filesCleanupConflict,
                message: l10n.filesCleanupMessage,
                confirmLabel: l10n.filesCleanAndRetry,
                action: () => controller.resolveConflictAndRetry(taskId),
              ),
        ),
      ],
    );
  }
}

class _OfflineDownloadWorkspace extends ConsumerWidget {
  const _OfflineDownloadWorkspace({required this.state});

  final FileBrowserState state;

  Future<void> _createOfflineDownloadWithSpace(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final spaceSelection = await showSpaceSelectorSheet(context);
    if (spaceSelection == null || !context.mounted) {
      return;
    }
    final spaceType =
        spaceSelection == SpaceSelection.shared ? 'SHARED' : 'PERSONAL';
    await _showNameDialog(
      context: context,
      title: l10n.filesNewOfflineDownload,
      actionLabel: l10n.filesCreate,
      labelText: l10n.filesDownloadLink,
      hintText: l10n.filesOfflineDownloadHint,
      onSubmit:
          (uri) => controller.createOfflineDownload(uri, spaceType: spaceType),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    return _SimpleListSurface(
      title: FileManagerSection.offlineDownloads.labelOf(l10n),
      subtitle: FileManagerSection.offlineDownloads.descriptionOf(l10n),
      emptyText: l10n.filesOfflineEmpty,
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
                  ? () =>
                      unawaited(_createOfflineDownloadWithSpace(context, ref))
                  : null,
          icon: const Icon(Icons.add_link_rounded, size: 18),
          label: Text(l10n.filesNewTask),
        ),
      ],
      children:
          state.offlineTasks
              .map(
                (task) => _InfoRow(
                  icon: Icons.download_for_offline_outlined,
                  title:
                      task.fileName?.isNotEmpty == true
                          ? task.fileName!
                          : task.sourceUri,
                  subtitle: _offlineDownloadSubtitle(task, l10n),
                  trailingWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _offlineDownloadTrailing(task),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        tooltip:
                            task.canCancel
                                ? l10n.filesCancelTask
                                : l10n.filesTaskEnded,
                        onPressed:
                            enabled && task.canCancel
                                ? () => _confirmAndRun(
                                  context,
                                  title: l10n.filesCancelOfflineConfirm,
                                  message: l10n.filesCancelOfflineMessage(
                                    task.fileName ?? task.sourceUri,
                                  ),
                                  confirmLabel: l10n.filesCancelTask,
                                  action:
                                      () => controller.cancelOfflineDownload(
                                        task,
                                      ),
                                )
                                : null,
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}

String _offlineDownloadSubtitle(
  OfflineDownloadTask task,
  AppLocalizations l10n,
) {
  final status = switch (task.status.toUpperCase()) {
    'QUEUED' => l10n.filesOfflineQueued,
    'RUNNING' => l10n.filesOfflineRunning,
    'DOWNLOADING' => l10n.filesOfflineRunning,
    'CANCELLING' => l10n.filesOfflineCancelling,
    'CANCELLED' => l10n.filesOfflineCancelled,
    'COMPLETED' => l10n.filesStatusCompleted,
    'FAILED' => l10n.filesStatusFailed,
    _ => task.status,
  };
  final errorText =
      task.errorSummary == null || task.errorSummary!.isEmpty
          ? ''
          : ' · ${task.errorSummary}';
  final timeText =
      task.updatedAt == null ? '' : ' · ${task.updatedAt!.toLocal()}';
  return '$status$errorText$timeText';
}

String _offlineDownloadTrailing(OfflineDownloadTask task) {
  if (task.totalBytes <= 0) {
    return task.downloadSpeedBytes <= 0
        ? ''
        : '${formatFileSize(task.downloadSpeedBytes)}/s';
  }
  return '${(task.progress * 100).toStringAsFixed(0)}% · '
      '${formatFileSize(task.completedBytes)} / ${formatFileSize(task.totalBytes)}';
}
