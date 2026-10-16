part of 'file_browser_page.dart';

/// 托管移动态的次级分区通用件：计数眉标行 + 状态丸 + 原型 `.feature-list`
/// 行。覆盖 与我共享 / 离线下载 / 外部存储 / 导入任务 四个原桌面工位分区；
/// 与我共享与离线下载已按样例 FeaturePage 收到「页头计数 + 纯列表」形态，
/// 计数眉标行只留给外部存储与导入任务。
///
/// 各区具体以 [ListView] 自带纵向滚动：宿主的正文插槽是 `Expanded` 下的
/// 有界高度，纯 Column 的分区体在条目超过一屏时会 RenderFlex 溢出且无法
/// 滚动（与最近/收藏的 `_HostedFeatureFileList` 同档）。空态与「加载更多」
/// 都作为列表子项随内容滚动。

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

/// 离线任务状态归档：桌面 chips 与托管分段共用同一口径。
///
/// 后端下行的是 `TaskStatus` 值（QUEUED/DOWNLOADING/RETRY_WAIT/COMPLETED/
/// FAILED/CANCELLED），只按字面 'RUNNING' 匹配会把真正在下载的任务全部筛掉。
enum _OfflineBucket { active, completed, failed, other }

_OfflineBucket _offlineBucketOf(String status) {
  return switch (status.toUpperCase()) {
    'COMPLETED' => _OfflineBucket.completed,
    'FAILED' || 'ERROR' || 'DLQ' || 'DISCARDED' => _OfflineBucket.failed,
    'CANCELLED' || 'CANCELED' => _OfflineBucket.other,
    _ => _OfflineBucket.active,
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

/// 与我共享（hosted）：样例 `.feature-list` 文件行 + 列表尾翻页动作。
///
/// 计数在页头副题，正文不再挂计数眉标条（样例 FeaturePage 只有列表）。
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
    final showLoadMore = loadedCount < totalCount;
    // 结构不变：空态一行，或「发丝线 + 行 + 续载胶囊」。行改由 builder 懒建，
    // 因为续载是追加语义，ListView(children:) 会即时构建已加载的每一行。
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount:
          (items.isEmpty ? 1 : items.length + 1) + (showLoadMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (items.isEmpty) {
          if (index == 0) {
            return EnvEmptyState(
              icon: OmniIcons.share,
              title: l10n.filesSharedWithMeEmptyTitle,
              message: l10n.filesSharedWithMeEmptyMessage,
            );
          }
          return _HostedLoadMorePill(
            label: l10n.filesUploadQueueLoadMore('$loadedCount', '$totalCount'),
            onTap: onLoadNext,
          );
        }
        if (index == 0) {
          // 样例 `.feature-list` 上沿一条发丝线。
          return Container(height: 1, color: context.env.line07);
        }
        if (showLoadMore && index == items.length + 1) {
          return _HostedLoadMorePill(
            label: l10n.filesUploadQueueLoadMore('$loadedCount', '$totalCount'),
            onTap: onLoadNext,
          );
        }
        final file = items[index - 1].file;
        return FileEnvRow(
          file: file,
          selected: false,
          onTap: () => _openFilePreview(context, file),
        );
      },
    );
  }
}

/// 样例 FeaturePage 的文件行列表（最近使用 / 我的收藏）：`.feature-list` 行，
/// 点文件夹进目录、点文件开预览；滚到页尾继续翻页（沿用托管态的滚动加载）。
class _HostedFeatureFileList extends ConsumerWidget {
  const _HostedFeatureFileList({
    required this.state,
    required this.actionsEnabled,
  });

  final FileBrowserState state;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final files = state.visibleNodes;
    // 行改由 builder 懒建：滚动续载是追加语义，children 形态会即时构建已加载的每一行。
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: files.isEmpty ? 1 : files.length + 1,
      itemBuilder: (context, index) {
        if (files.isEmpty) {
          return EnvEmptyState(
            icon: state.section.featureHeroIcon,
            title: state.section.labelOf(l10n),
            message: state.section.descriptionOf(l10n),
          );
        }
        if (index == 0) {
          // 样例 `.feature-list` 上沿一条发丝线。
          return Container(height: 1, color: context.env.line07);
        }
        final file = files[index - 1];
        return FileEnvRow(
          file: file,
          // 长按进多选：批量条由 _FileNodeWorkspace 的 Stack 统一挂出，
          // 工位列表换成样例行时不能把多选能力一起换掉。
          selected: state.selectedFileIds.contains(file.id),
          showChevron: true,
          onLongPress:
              actionsEnabled ? () => controller.toggleSelection(file.id) : null,
          onTap:
              () =>
                  unawaited(_openHostedFeatureNode(context, controller, file)),
        );
      },
    );
  }
}

Future<void> _openHostedFeatureNode(
  BuildContext context,
  FileBrowserController controller,
  FileNode file,
) async {
  if (file.isFolder) {
    await _runFileAction(context, () => controller.openFolder(file));
    return;
  }
  _openFilePreview(context, file);
}

/// 离线下载（hosted）：样例 `.segmented` 状态档 + `.feature-list` 行 + 状态丸。
///
/// 计数在页头副题、「新建离线下载」在页头右钮，正文不再挂工作区计数条。
/// 状态档与桌面页共用 [_offlineBucketOf] 归档；分段吸顶、列表在其下滚动，
/// 对应样例 `.segmented { position: sticky; top: 0 }`。
///
/// 档内筛选走客户端：`GET /api/v1/offline-downloads` 当前整表返回任务
/// （page/size 不参与切片），所以列表里的就是全部任务。后端一旦改成真
/// 分页，这里必须换成带状态参数的服务端筛选，否则切档只会覆盖已载入页。
class _HostedOfflineDownloads extends StatefulWidget {
  const _HostedOfflineDownloads({
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
  State<_HostedOfflineDownloads> createState() =>
      _HostedOfflineDownloadsState();
}

class _HostedOfflineDownloadsState extends State<_HostedOfflineDownloads> {
  /// 档序与桌面 chips 一致；null 表示「全部」。
  static const List<_OfflineBucket?> _buckets = <_OfflineBucket?>[
    null,
    _OfflineBucket.active,
    _OfflineBucket.completed,
    _OfflineBucket.failed,
  ];

  _OfflineBucket? _bucket;

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

  String _bucketLabel(AppLocalizations l10n, _OfflineBucket? bucket) {
    return switch (bucket) {
      null => l10n.filesStatusFilterAll,
      _OfflineBucket.active => l10n.filesStatusDownloading,
      _OfflineBucket.completed => l10n.filesStatusCompleted,
      _OfflineBucket.failed || _OfflineBucket.other => l10n.filesStatusFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = widget.state.offlineTasks;
    final visible =
        _bucket == null
            ? tasks
            : tasks
                .where((task) => _offlineBucketOf(task.status) == _bucket)
                .toList(growable: false);
    final showLoadMore = widget.loadedCount < widget.totalCount;
    // 行改由 builder 懒建：续载是追加语义，children 形态会即时构建已加载的每一行。
    final list = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount:
          (visible.isEmpty ? 1 : visible.length + 1) + (showLoadMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (visible.isEmpty) {
          if (index == 0) {
            return EnvEmptyState(
              icon: OmniIcons.download,
              title:
                  tasks.isEmpty
                      ? l10n.filesOfflineEmptyTitle
                      : l10n.filesOfflineFilterEmpty,
              message: tasks.isEmpty ? l10n.filesOfflineEmptyMessage : null,
            );
          }
          return _HostedLoadMorePill(
            label: l10n.filesUploadQueueLoadMore(
              '${widget.loadedCount}',
              '${widget.totalCount}',
            ),
            onTap: widget.onLoadNext,
          );
        }
        if (index == 0) {
          // 样例 `.feature-list` 上沿一条发丝线。
          return Container(height: 1, color: context.env.line07);
        }
        if (showLoadMore && index == visible.length + 1) {
          return _HostedLoadMorePill(
            label: l10n.filesUploadQueueLoadMore(
              '${widget.loadedCount}',
              '${widget.totalCount}',
            ),
            onTap: widget.onLoadNext,
          );
        }
        final task = visible[index - 1];
        return MobileFeatureListRow(
          icon: OmniIcons.download,
          title: _taskName(task),
          detail: _taskDetail(task),
          trailing: MobileStatusPill(
            label: _hostedStatusLabel(l10n, task.status),
            tone: _hostedStatusTone(task.status),
          ),
        );
      },
    );
    if (tasks.isEmpty) {
      // 一条任务都没有时不给筛选段。
      return list;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: MobileSegmentedControl<_OfflineBucket?>(
              values: _buckets,
              selected: _bucket,
              labelBuilder: (bucket) => _bucketLabel(l10n, bucket),
              onSelected: (bucket) => setState(() => _bucket = bucket),
            ),
          ),
        ),
        Expanded(child: list),
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
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _HostedSectionMetaRow(
            text: l10n.filesHostedItemCount(accounts.length),
            action: _HostedPillAction(
              icon: Icons.add_rounded,
              label: l10n.filesAddMount,
              onTap: onAdd,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          sliver: SliverList.builder(
            itemCount: accounts.isEmpty ? 1 : accounts.length,
            itemBuilder: (context, index) {
              if (accounts.isEmpty) {
                return EnvEmptyState(
                  icon: OmniIcons.device,
                  title: l10n.filesExternalEmptyTitle,
                  message: l10n.filesExternalEmptyMessage,
                );
              }
              final account = accounts[index];
              return MobileFeatureListRow(
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
              );
            },
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
    // 续载是追加语义：「已加载」直接取在列条数，不按页窗推算。
    final loadedCount = items.length;
    final totalCount = state.externalMeta.totalElements;
    final error = state.externalBrowseError;
    final loading = state.isExternalBrowseLoading;
    final showLoadMore = !loading && loadedCount < totalCount;
    final hasSingleBody = error != null || (items.isEmpty && !loading);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _HostedSectionMetaRow(
            text: _metaText(l10n, items, error),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (segments.isNotEmpty) ...[
                  _HostedPillAction(
                    icon: Icons.expand_less_rounded,
                    label: l10n.videoBackToParentNode,
                    minHeight: MobileLayoutTokens.minimumTarget,
                    onTap: onGoUp,
                  ),
                  const SizedBox(width: 8),
                ],
                _HostedPillAction(
                  icon: Icons.close_rounded,
                  label: l10n.filesCloseBrowse,
                  minHeight: MobileLayoutTokens.minimumTarget,
                  onTap: onClose,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          sliver: SliverList.builder(
            // 目录条目改由 builder 懒建：浏览是追加语义，Column 形态会即时
            // 构建已加载的每一行。
            itemCount:
                (hasSingleBody ? 1 : items.length) + (showLoadMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (showLoadMore && index == (hasSingleBody ? 1 : items.length)) {
                return _HostedLoadMorePill(
                  label: l10n.filesUploadQueueLoadMore(
                    '$loadedCount',
                    '$totalCount',
                  ),
                  onTap: onLoadNext,
                );
              }
              if (hasSingleBody) {
                if (error != null) {
                  return MobileDisabledCard(
                    icon: OmniIcons.cloud,
                    title: l10n.filesExternalBrowseFailedTitle,
                    message: error,
                    actionLabel: l10n.coreRetry,
                    onAction: onRetry,
                  );
                }
                return EnvEmptyState(
                  icon: OmniIcons.folder,
                  title: l10n.filesDirectoryEmpty,
                  message: l10n.filesExternalBrowseEmptyMessage,
                );
              }
              final item = items[index];
              return MobileFeatureListRow(
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
                onTap: item.isDir ? () => onEnterDirectory(item.path) : null,
              );
            },
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
    final showLoadMore = loadedCount < totalCount;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _HostedSectionMetaRow(
            text: l10n.filesHostedItemCount(tasks.length),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          sliver: SliverList.builder(
            itemCount:
                (tasks.isEmpty ? 1 : tasks.length) + (showLoadMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (showLoadMore && index == (tasks.isEmpty ? 1 : tasks.length)) {
                return _HostedLoadMorePill(
                  label: l10n.filesUploadQueueLoadMore(
                    '$loadedCount',
                    '$totalCount',
                  ),
                  onTap: onLoadNext,
                );
              }
              if (tasks.isEmpty) {
                return EnvEmptyState(
                  icon: OmniIcons.download,
                  title: l10n.filesImportEmptyTitle,
                  message: l10n.filesImportEmptyMessage,
                );
              }
              final task = tasks[index];
              return MobileFeatureListRow(
                icon: task.isDirectory ? OmniIcons.folder : OmniIcons.book,
                neutralIcon: !task.isDirectory,
                title: task.fileName ?? task.sourcePath,
                detail: _detail(l10n, task),
                trailing: MobileStatusPill(
                  label: _hostedStatusLabel(l10n, task.status),
                  tone: _hostedStatusTone(task.status),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 托 hosted 计数行的动作胶囊（r11 白 6% 底描边）。
///
/// 返回上级与关闭浏览属于逃生控件，取下限 48；其余动作沿用样例的 35 档。
class _HostedPillAction extends StatelessWidget {
  const _HostedPillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.minHeight = 35,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double minHeight;

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
          constraints: BoxConstraints(minHeight: minHeight),
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
