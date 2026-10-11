part of 'file_browser_page.dart';

/// 托管移动态的次级分区通用件：计数眉标行 + 状态丸 + 原型 `.feature-list`
/// 行。覆盖 与我共享 / 离线下载 / 外部存储 / 导入任务 四个原桌面工位分区。
///
/// 分区宿主自带纵向滚动（下发无界高约束），因此各分区体只出非滚动内容：
/// 不用 Expanded，横排也不取 stretch。

/// 次级分区页的 `.feature-hero` 身份块：分区名 + 分区说明 + 样例同源的图标舱。
///
/// 样例把 header 与 hero 的同一份文案渲染两遍，这里 header 留给真实计数
/// （[MobileModuleHeader] 的副题），hero 说明用 `descriptionOf`，两行不再重复。
class _FeatureSectionHero extends StatelessWidget {
  const _FeatureSectionHero({required this.section});

  final FileManagerSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SampleFeatureHero(
        icon: section.featureHeroIcon,
        title: section.labelOf(l10n),
        detail: section.descriptionOf(l10n),
      ),
    );
  }
}

/// 计数眉标行（9px 弱化 + 右侧可选动作胶囊）。
class _HostedSectionMetaRow extends StatelessWidget {
  const _HostedSectionMetaRow({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9, // ignore: font_size_whitelist
                color: context.env.inkMuted,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

/// 通用发丝线信息行（图标盒 + 标题/副题 + 尾部槽）。
///
/// 几何对齐原型 `.feature-list > button`（69 行高、42 r13 图标舱、
/// 11/9 双行文案），与 [MobileFeatureListRow] 同族，差别只在图标源取
/// Material 编码。
class _HostedInfoRow extends StatelessWidget {
  const _HostedInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 69),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.env.line07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.env.accentInk.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 18, color: context.env.accentInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w600,
                        color: context.env.ink,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9, // ignore: font_size_whitelist
                          color: context.env.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区任务状态文案：优先复用工位状态词条，取不到时回显服务端原值。
String _hostedStatusLabel(AppLocalizations l10n, String status) {
  return switch (status.toUpperCase()) {
    'COMPLETED' => l10n.filesStatusCompleted,
    'FAILED' || 'ERROR' => l10n.filesStatusFailed,
    'RUNNING' => l10n.filesStatusRunning,
    'DOWNLOADING' => l10n.filesStatusDownloading,
    'UPLOADING' => l10n.filesStatusUploading,
    'PAUSED' => l10n.filesStatusPaused,
    'PENDING' => l10n.filesStatusPending,
    'QUEUED' => l10n.filesStatusQueued,
    'CANCELLING' => l10n.filesStatusCancelling,
    'CANCELLED' || 'CANCELED' => l10n.filesStatusCancelled,
    'CONNECTED' || 'ONLINE' || 'ACTIVE' => l10n.filesShareActive,
    'EXPIRED' => l10n.filesShareExpired,
    'REVOKED' => l10n.filesShareRevoked,
    _ => status,
  };
}

/// 分区任务状态丸色调：完成/连接=酸绿，排队/暂停=琥珀，失败/撤销=红。
MobileStatusTone _hostedStatusTone(String status) {
  return switch (status.toUpperCase()) {
    'FAILED' ||
    'ERROR' ||
    'REVOKED' ||
    'CANCELLED' ||
    'CANCELED' => MobileStatusTone.danger,
    'PENDING' ||
    'QUEUED' ||
    'PAUSED' ||
    'EXPIRED' ||
    'RETRY' => MobileStatusTone.warning,
    _ => MobileStatusTone.calm,
  };
}

/// 「加载更多（已加载 X / 共 Y）」动作：替代移动可达路径上的工位分页条。
class _HostedLoadMorePill extends StatelessWidget {
  const _HostedLoadMorePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.center,
        child: _HostedPillAction(
          icon: Icons.expand_more_rounded,
          label: label,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// 与我共享（hosted）：文件行列表 + 计数眉标 + 翻页动作。
class _HostedSharedWithMe extends StatelessWidget {
  const _HostedSharedWithMe({
    required this.state,
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadNext,
  });

  final FileBrowserState state;
  final int loadedCount;
  final int totalCount;
  final VoidCallback onLoadNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = state.sharedWithMe;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text: l10n.filesHostedItemCount(items.length),
          action:
              loadedCount < totalCount
                  ? _HostedPillAction(
                    icon: Icons.expand_more_rounded,
                    label: l10n.filesUploadQueueLoadMore(
                      '$loadedCount',
                      '$totalCount',
                    ),
                    onTap: onLoadNext,
                  )
                  : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child:
              items.isEmpty
                  ? EnvEmptyState(
                    icon: OmniIcons.share,
                    title: l10n.filesSharedWithMeEmptyTitle,
                    message: l10n.filesSharedWithMeEmptyMessage,
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in items)
                        FileEnvRow(
                          file: item.file,
                          selected: false,
                          onTap: () => _openFilePreview(context, item.file),
                        ),
                    ],
                  ),
        ),
      ],
    );
  }
}

/// 离线下载（hosted）：原型 `.feature-list` 行 + 状态丸 + 新建入口。
class _HostedOfflineDownloads extends StatelessWidget {
  const _HostedOfflineDownloads({
    required this.state,
    required this.onCreate,
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadNext,
  });

  final FileBrowserState state;
  final VoidCallback onCreate;
  final int loadedCount;
  final int totalCount;
  final VoidCallback onLoadNext;

  static String _taskName(OfflineDownloadTask task) {
    final fileName = task.fileName;
    if (fileName != null && fileName.isNotEmpty) {
      return fileName;
    }
    final uri = Uri.tryParse(task.sourceUri);
    final last =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : null;
    return (last == null || last.isEmpty) ? task.sourceUri : last;
  }

  String _taskDetail(OfflineDownloadTask task) {
    final error = task.errorSummary;
    if (error != null && error.isNotEmpty) {
      return error;
    }
    if (task.totalBytes > 0) {
      return '${formatFileSize(task.completedBytes)} / '
          '${formatFileSize(task.totalBytes)}';
    }
    return task.sourceUri;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = state.offlineTasks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text: l10n.filesHostedItemCount(tasks.length),
          action: _HostedPillAction(
            icon: Icons.add_rounded,
            label: l10n.filesNewOfflineDownload,
            onTap: onCreate,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tasks.isEmpty)
                EnvEmptyState(
                  icon: OmniIcons.download,
                  title: l10n.filesOfflineEmptyTitle,
                  message: l10n.filesOfflineEmptyMessage,
                )
              else
                for (final task in tasks)
                  MobileFeatureListRow(
                    icon: OmniIcons.download,
                    title: _taskName(task),
                    detail: _taskDetail(task),
                    trailing: MobileStatusPill(
                      label: _hostedStatusLabel(l10n, task.status),
                      tone: _hostedStatusTone(task.status),
                    ),
                  ),
              if (loadedCount < totalCount)
                _HostedLoadMorePill(
                  label: l10n.filesUploadQueueLoadMore(
                    '$loadedCount',
                    '$totalCount',
                  ),
                  onTap: onLoadNext,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 外部存储（hosted）：挂载账户行 + 添加挂载胶囊。
class _HostedExternalStorage extends StatelessWidget {
  const _HostedExternalStorage({
    required this.state,
    required this.onAdd,
    required this.onOpenAccount,
  });

  final FileBrowserState state;
  final VoidCallback onAdd;
  final void Function(String accountId) onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = state.externalAccounts;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text: l10n.filesHostedItemCount(accounts.length),
          action: _HostedPillAction(
            icon: Icons.add_rounded,
            label: l10n.filesAddMount,
            onTap: onAdd,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accounts.isEmpty)
                EnvEmptyState(
                  icon: OmniIcons.device,
                  title: l10n.filesExternalEmptyTitle,
                  message: l10n.filesExternalEmptyMessage,
                )
              else
                for (final account in accounts)
                  MobileFeatureListRow(
                    icon: OmniIcons.device,
                    title: account.displayName,
                    detail:
                        account.credentialsConfigured
                            ? account.provider
                            : '${account.provider} · ${l10n.filesExternalCredentialsMissing}',
                    trailing: MobileStatusPill(
                      label: _hostedStatusLabel(l10n, account.status),
                      tone: _hostedStatusTone(account.status),
                    ),
                    showChevron: true,
                    onTap: () => onOpenAccount(account.id),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 外部存储浏览（hosted）：目录行 + 导入动作 + 加载更多。
///
/// 桌面工位形态的面包屑胶囊、悬停行与分页条不进触屏：路径收进眉标行，
/// 逐级返回与关闭浏览用动作胶囊，翻页改「加载更多」。
class _HostedExternalBrowse extends StatelessWidget {
  const _HostedExternalBrowse({
    required this.state,
    required this.space,
    required this.segments,
    required this.onEnterDirectory,
    required this.onGoUp,
    required this.onClose,
    required this.onImport,
    required this.onLoadNext,
    required this.onRetry,
  });

  final FileBrowserState state;
  final ExternalSpaceUsage? space;
  final List<String> segments;
  final void Function(String path) onEnterDirectory;
  final VoidCallback onGoUp;
  final VoidCallback onClose;
  final void Function(ExternalFileItem item) onImport;
  final VoidCallback onLoadNext;
  final VoidCallback onRetry;

  String get _currentPath {
    return segments.isEmpty ? '/' : '/${segments.join('/')}';
  }

  String _metaText(
    AppLocalizations l10n,
    List<ExternalFileItem> items,
    String? error,
  ) {
    if (error != null) {
      return error;
    }
    if (state.isExternalBrowseLoading) {
      return l10n.importUploading;
    }
    final current =
        '$_currentPath · ${l10n.filesHostedItemCount(items.length)}';
    final usage = space;
    if (usage == null) {
      return current;
    }
    return '$current · '
        '${l10n.externalSpaceUsedOf(formatFileSize(usage.usedBytes), formatFileSize(usage.totalBytes))}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = state.externalFiles;
    final loadedCount = math.min(
      state.externalMeta.totalElements,
      (state.externalMeta.page + 1) * state.externalMeta.size,
    );
    final totalCount = state.externalMeta.totalElements;
    final error = state.externalBrowseError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text: _metaText(l10n, items, error),
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segments.isNotEmpty) ...[
                _HostedPillAction(
                  icon: Icons.expand_less_rounded,
                  label: l10n.videoBackToParentNode,
                  onTap: onGoUp,
                ),
                const SizedBox(width: 8),
              ],
              _HostedPillAction(
                icon: Icons.close_rounded,
                label: l10n.filesCloseBrowse,
                onTap: onClose,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                MobileDisabledCard(
                  icon: OmniIcons.cloud,
                  title: l10n.filesExternalBrowseFailedTitle,
                  message: error,
                  actionLabel: l10n.coreRetry,
                  onAction: onRetry,
                )
              else if (items.isEmpty && !state.isExternalBrowseLoading)
                EnvEmptyState(
                  icon: OmniIcons.folder,
                  title: l10n.filesDirectoryEmpty,
                  message: l10n.filesExternalBrowseEmptyMessage,
                )
              else
                for (final item in items)
                  MobileFeatureListRow(
                    icon: item.isDir ? OmniIcons.folder : OmniIcons.book,
                    neutralIcon: !item.isDir,
                    title: item.name,
                    detail:
                        item.isDir
                            ? l10n.filesFolder
                            : formatFileSize(item.sizeBytes),
                    trailing:
                        item.isDir
                            ? null
                            : _HostedPillAction(
                              icon: Icons.download_rounded,
                              label: l10n.filesImport,
                              onTap: () => onImport(item),
                            ),
                    showChevron: item.isDir,
                    onTap:
                        item.isDir ? () => onEnterDirectory(item.path) : null,
                  ),
              if (!state.isExternalBrowseLoading && loadedCount < totalCount)
                _HostedLoadMorePill(
                  label: l10n.filesUploadQueueLoadMore(
                    '$loadedCount',
                    '$totalCount',
                  ),
                  onTap: onLoadNext,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 导入任务（hosted）：任务行 + 来源路径副题 + 状态丸。
class _HostedImportTasks extends StatelessWidget {
  const _HostedImportTasks({
    required this.state,
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadNext,
  });

  final FileBrowserState state;
  final int loadedCount;
  final int totalCount;
  final VoidCallback onLoadNext;

  String _detail(AppLocalizations l10n, ImportTask task) {
    final error = task.errorSummary;
    if (error != null && error.isNotEmpty) {
      return error;
    }
    if (task.isDirectory && task.totalFiles > 0) {
      return l10n.filesImportFileProgress(task.completedFiles, task.totalFiles);
    }
    if (task.totalBytes > 0) {
      return '${formatFileSize(task.transferredBytes)} / '
          '${formatFileSize(task.totalBytes)}';
    }
    return task.sourcePath;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = state.importTasks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(text: l10n.filesHostedItemCount(tasks.length)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tasks.isEmpty)
                EnvEmptyState(
                  icon: OmniIcons.download,
                  title: l10n.filesImportEmptyTitle,
                  message: l10n.filesImportEmptyMessage,
                )
              else
                for (final task in tasks)
                  MobileFeatureListRow(
                    icon: task.isDirectory ? OmniIcons.folder : OmniIcons.book,
                    neutralIcon: !task.isDirectory,
                    title: task.fileName ?? task.sourcePath,
                    detail: _detail(l10n, task),
                    trailing: MobileStatusPill(
                      label: _hostedStatusLabel(l10n, task.status),
                      tone: _hostedStatusTone(task.status),
                    ),
                  ),
              if (loadedCount < totalCount)
                _HostedLoadMorePill(
                  label: l10n.filesUploadQueueLoadMore(
                    '$loadedCount',
                    '$totalCount',
                  ),
                  onTap: onLoadNext,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 托 hosted 计数行的动作胶囊（r11 白 6% 底描边）。
class _HostedPillAction extends StatelessWidget {
  const _HostedPillAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.env.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: context.env.line09),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 35),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: context.env.ink),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9, // ignore: font_size_whitelist
                  color: context.env.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
