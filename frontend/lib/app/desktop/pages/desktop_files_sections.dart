part of 'desktop_files_page.dart';

/// 分享链接列表（我的分享 / 链接管理共用一份）。
class _SharesSection extends StatelessWidget {
  const _SharesSection({
    required this.state,
    required this.controller,
    required this.onCopy,
  });

  final FileBrowserState? state;
  final FileBrowserController controller;
  final ValueChanged<FileShareLink> onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final links = <FileShareLink>[];
    final seen = <String>{};
    for (final link in [...?state?.myShares, ...?state?.shareLinks]) {
      if (seen.add(link.id)) {
        links.add(link);
      }
    }
    if (links.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: DesktopEmpty(
          icon: DesktopIcons.link,
          message: l10n.filesSharesEmptyMessage,
          actionLabel: null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < links.length; i++)
          DesktopStagger(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
                border: Border.all(color: skin.line),
              ),
              child: Row(
                children: [
                  Icon(DesktopIcons.link, size: 15, color: skin.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: Text(
                      links[i].resourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.rowTitle(skin.text),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      links[i].shareCode.isEmpty ? '—' : links[i].shareCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.mono(skin.text3),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      l10n.desktopFilesShareVisits(links[i].accessCount),
                      style: DesktopType.caption(skin.text3),
                    ),
                  ),
                  SizedBox(
                    width: 104,
                    child: Text(
                      _formatDate(links[i].expiresAt),
                      style: DesktopType.numeric(skin.text3),
                    ),
                  ),
                  DesktopButton(
                    label: l10n.filesCopyLink,
                    icon: DesktopIcons.copy,
                    variant: DesktopButtonVariant.ghost,
                    onPressed:
                        links[i].shareCode.isEmpty
                            ? null
                            : () => onCopy(links[i]),
                  ),
                  const SizedBox(width: 6),
                  DesktopButton(
                    label: l10n.desktopFilesRevoke,
                    icon: DesktopIcons.close,
                    variant: DesktopButtonVariant.ghost,
                    onPressed: () async {
                      await controller.revokeShare(links[i]);
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 别人分享给我的文件（只读列表，打开即预览）。
class _WithMeSection extends StatelessWidget {
  const _WithMeSection({required this.state, required this.controller});

  final FileBrowserState? state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final items = state?.sharedWithMe ?? const <SharedFileItem>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: DesktopEmpty(
          icon: DesktopIcons.user,
          message: l10n.filesSharedWithMeEmptyMessage,
          actionLabel: null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          DesktopStagger(
            index: i,
            child: DesktopHover(
              builder:
                  (context, hovered) => GestureDetector(
                    onTap:
                        () => desktopPush(
                          context,
                          DesktopRoutes.filePreview(items[i].file.id),
                        ),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 46,
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: hovered ? skin.raise : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusSmall,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _fileIcon(items[i].file),
                            size: 16,
                            color: skin.text3,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 4,
                            child: Text(
                              items[i].file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.rowTitle(skin.text),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              l10n.desktopFilesOwner(items[i].ownerUserId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.caption(skin.text3),
                            ),
                          ),
                          SizedBox(
                            width: 104,
                            child: Text(
                              items[i].file.isFolder
                                  ? '—'
                                  : formatFileSize(items[i].file.sizeBytes),
                              textAlign: TextAlign.right,
                              style: DesktopType.numeric(skin.text3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
        if (state?.sharedWithMeMeta.hasMore ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DesktopButton(
                label: l10n.desktopFilesLoadMore(
                  items.length,
                  state!.sharedWithMeMeta.totalElements,
                ),
                variant: DesktopButtonVariant.ghost,
                onPressed: () => unawaited(controller.loadMoreSharedWithMe()),
              ),
            ),
          ),
      ],
    );
  }
}

/// 外部存储连接器：只做"测活/停用"，挂载向导仍在移动页。
class _ExternalSection extends StatelessWidget {
  const _ExternalSection({required this.state, required this.controller});

  final FileBrowserState? state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final accounts =
        state?.externalAccounts ?? const <ExternalStorageAccount>[];
    if (accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: DesktopEmpty(
          icon: DesktopIcons.server,
          message: l10n.filesExternalEmptyMessage,
          actionLabel: null,
        ),
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (var i = 0; i < accounts.length; i++)
          DesktopStagger(
            index: i,
            child: SizedBox(
              width: 340,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: skin.raise,
                  borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                  border: Border.all(color: skin.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(DesktopIcons.cloud, size: 18, color: skin.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            accounts[i].displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.cardTitle(skin.text),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      accounts[i].provider,
                      style: DesktopType.caption(skin.text3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accounts[i].status,
                      style: DesktopType.nano(
                        accounts[i].status.toUpperCase() == 'CONNECTED'
                            ? skin.accent
                            : skin.text3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        DesktopButton(
                          label: l10n.filesTestConnection,
                          icon: DesktopIcons.check,
                          variant: DesktopButtonVariant.ghost,
                          onPressed: () async {
                            await controller.testExternalStorageConnection(
                              accounts[i].id,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        DesktopButton(
                          label: l10n.desktopFilesDisable,
                          icon: DesktopIcons.close,
                          variant: DesktopButtonVariant.ghost,
                          onPressed: () async {
                            await controller.disableExternalStorage(
                              accounts[i],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 上传队列（服务端会话）：续传入口仍在移动页，这里给进度与清理。
class _UploadQueueSection extends StatelessWidget {
  const _UploadQueueSection({required this.state, required this.controller});

  final FileBrowserState? state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final items = state?.uploadQueue ?? const <FileUploadQueueItem>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: DesktopEmpty(
          icon: DesktopIcons.upload,
          message: l10n.filesUploadQueueEmptyMessage,
          actionLabel: null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: Text(
                    items[i].fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.rowTitle(skin.text),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DesktopProgress(
                    fraction:
                        items[i].totalParts <= 0
                            ? 0
                            : items[i].uploadedParts / items[i].totalParts,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    items[i].status,
                    style: DesktopType.nano(skin.text3),
                  ),
                ),
                DesktopButton(
                  label: l10n.filesDelete,
                  icon: DesktopIcons.trash,
                  variant: DesktopButtonVariant.ghost,
                  onPressed: () async {
                    await controller.deleteServerUploadSession(items[i]);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ImportTasksSection extends StatelessWidget {
  const _ImportTasksSection({required this.state});

  final FileBrowserState? state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final tasks = state?.importTasks ?? const <ImportTask>[];
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: DesktopEmpty(
          icon: DesktopIcons.download,
          message: l10n.filesImportEmptyMessage,
          actionLabel: null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tasks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(DesktopIcons.download, size: 15, color: skin.text3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tasks[i].fileName ?? tasks[i].sourcePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.rowTitle(skin.text),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    tasks[i].status,
                    style: DesktopType.nano(skin.text3),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatFileSize(tasks[i].transferredBytes),
                    textAlign: TextAlign.right,
                    style: DesktopType.numeric(skin.text3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 存储统计：总量 + 类型分布。
class _StorageSection extends StatelessWidget {
  const _StorageSection({required this.stats});

  final FileStorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final value = stats;
    if (value == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: DesktopEmpty(
          icon: DesktopIcons.panel,
          message: l10n.filesStorageEmptyMessage,
          actionLabel: null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StorageStat(
                label: l10n.filesCurrentViewTotal,
                value: '${value.totalFiles}',
              ),
            ),
            Expanded(
              child: _StorageStat(
                label: l10n.filesStorageSummaryFolders,
                value: '${value.totalFolders}',
              ),
            ),
            Expanded(
              child: _StorageStat(
                label: l10n.desktopFilesGroupStorage,
                value: formatFileSize(value.usedBytes),
              ),
            ),
            Expanded(
              child: _StorageStat(
                label: l10n.desktopFilesSize,
                value: formatFileSize(value.quotaBytes),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DesktopProgress(
          fraction:
              value.quotaBytes <= 0
                  ? 0
                  : (value.usedBytes / value.quotaBytes).clamp(0.0, 1.0),
          label: l10n.desktopFilesStorageUsed(
            formatFileSize(value.usedBytes),
            formatFileSize(value.quotaBytes),
          ),
          large: true,
        ),
        if (value.typeDistribution.isNotEmpty) ...[
          const SizedBox(height: 18),
          for (final entry in value.typeDistribution)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      entry.category,
                      style: DesktopType.caption(skin.text2),
                    ),
                  ),
                  Expanded(
                    child: DesktopProgress(
                      fraction:
                          value.usedBytes <= 0
                              ? 0
                              : (entry.sizeBytes / value.usedBytes).clamp(
                                0.0,
                                1.0,
                              ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 90,
                    child: Text(
                      formatFileSize(entry.sizeBytes),
                      textAlign: TextAlign.right,
                      style: DesktopType.numeric(skin.text3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _StorageStat extends StatelessWidget {
  const _StorageStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DesktopType.caption(skin.text3)),
        const SizedBox(height: 4),
        Text(value, style: DesktopType.statValue(skin.text)),
      ],
    );
  }
}

/// 传输浮层（样例 `.xfers`）：贴在右下角，只列在途任务。
class _TransfersCard extends StatelessWidget {
  const _TransfersCard({required this.state, required this.controller});

  final FileBrowserState state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final tasks = state.inlineUploadTasks;
    return SizedBox(
      width: 320,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: skin.pop,
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusLarge),
          border: Border.all(color: skin.line),
          boxShadow: skin.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  l10n.desktopFilesTransfers,
                  style: DesktopType.bodyStrong(skin.text),
                ),
                const Spacer(),
                Text(
                  l10n.desktopFilesActiveTransfers(
                    tasks.where((task) => task.progress < 1).length,
                  ),
                  style: DesktopType.nano(skin.text3),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final task in tasks.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(DesktopIcons.upload, size: 13, color: skin.text3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            task.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(skin.text2),
                          ),
                          const SizedBox(height: 4),
                          DesktopProgress(fraction: task.progress),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(task.progress * 100).round()}%',
                      style: DesktopType.nano(skin.text3),
                    ),
                    DesktopIconButton(
                      icon:
                          task.status.toUpperCase() == 'PAUSED'
                              ? DesktopIcons.play
                              : DesktopIcons.pause,
                      size: 24,
                      iconSize: 12,
                      onPressed: () {
                        if (task.status.toUpperCase() == 'PAUSED') {
                          unawaited(controller.resumeLocalUploadTask(task.id));
                        } else {
                          controller.pauseLocalUploadTask(task.id);
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
