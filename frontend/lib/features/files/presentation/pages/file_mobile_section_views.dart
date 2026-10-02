part of 'file_browser_page.dart';

/// 托管移动态的次级分区通用件：计数眉标行 + 状态胶囊 + 发丝线行。
/// 覆盖 与我共享 / 离线下载 / 外部存储 / 导入任务 四个原桌面工位分区。

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
              style: const TextStyle(
                fontSize: 9, // ignore: font_size_whitelist
                color: MobileEnvColors.inkMuted,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// 托管态状态胶囊（运行/完成/失败等着色）。
class _HostedStatusChip extends StatelessWidget {
  const _HostedStatusChip({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final upper = status.toUpperCase();
    final Color color;
    if (upper == 'COMPLETED' || upper == 'CONNECTED' || upper == 'ACTIVE') {
      color = MobileEnvColors.accent;
    } else if (upper == 'FAILED' || upper == 'ERROR') {
      color = const Color(0xFFE2A1A1);
    } else {
      color = MobileEnvColors.inkFaint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8, // ignore: font_size_whitelist
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 通用发丝线信息行（图标盒 + 标题/副题 + 尾部槽）。
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
        constraints: const BoxConstraints(minHeight: 60),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MobileEnvColors.line07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MobileEnvColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: MobileEnvColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w600,
                        color: MobileEnvColors.ink,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9, // ignore: font_size_whitelist
                          color: MobileEnvColors.inkMuted,
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

/// 与我共享（hosted）：FileEnvRow 列表 + 计数行。
class _HostedSharedWithMe extends ConsumerWidget {
  const _HostedSharedWithMe({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = state.sharedWithMe;
    return Column(
      children: [
        _HostedSectionMetaRow(
          text: l10n.photosHostedToolbarCount(items.length),
        ),
        Expanded(
          child:
              items.isEmpty
                  ? Center(
                    child: Text(
                      l10n.filesEmpty,
                      style: const TextStyle(
                        color: MobileEnvColors.inkMuted,
                        fontSize: 13, // ignore: font_size_whitelist
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return FileEnvRow(
                        file: item.file,
                        selected: false,
                        onTap: () => _openFilePreview(context, item.file),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

/// 离线下载（hosted）：任务行 + 新建入口胶囊。
class _HostedOfflineDownloads extends StatelessWidget {
  const _HostedOfflineDownloads({required this.state, required this.onCreate});

  final FileBrowserState state;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = state.offlineTasks;
    return Column(
      children: [
        _HostedSectionMetaRow(
          text: l10n.photosHostedToolbarCount(tasks.length),
          action: _HostedPillAction(
            icon: Icons.add_rounded,
            label: l10n.filesNewOfflineDownload,
            onTap: onCreate,
          ),
        ),
        Expanded(
          child:
              tasks.isEmpty
                  ? Center(
                    child: Text(
                      l10n.filesEmpty,
                      style: const TextStyle(
                        color: MobileEnvColors.inkMuted,
                        fontSize: 13, // ignore: font_size_whitelist
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final uri = Uri.tryParse(task.sourceUri);
                      final name =
                          uri?.pathSegments.isNotEmpty == true
                              ? uri!.pathSegments.last
                              : task.sourceUri;
                      return _HostedInfoRow(
                        icon: Icons.download_for_offline_outlined,
                        title: name.isEmpty ? task.sourceUri : name,
                        subtitle: task.sourceUri,
                        trailing: _HostedStatusChip(
                          label: task.status,
                          status: task.status,
                        ),
                      );
                    },
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
      children: [
        _HostedSectionMetaRow(
          text: l10n.photosHostedToolbarCount(accounts.length),
          action: _HostedPillAction(
            icon: Icons.add_rounded,
            label: l10n.filesAddMount,
            onTap: onAdd,
          ),
        ),
        Expanded(
          child:
              accounts.isEmpty
                  ? Center(
                    child: Text(
                      l10n.filesEmpty,
                      style: const TextStyle(
                        color: MobileEnvColors.inkMuted,
                        fontSize: 13, // ignore: font_size_whitelist
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      return _HostedInfoRow(
                        icon: Icons.cloud_queue_outlined,
                        title: account.displayName,
                        subtitle: account.provider,
                        trailing: _HostedStatusChip(
                          label: account.status,
                          status: account.status,
                        ),
                        onTap: () => onOpenAccount(account.id),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

/// 导入任务（hosted）：任务行 + 来源路径副题。
class _HostedImportTasks extends StatelessWidget {
  const _HostedImportTasks({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = state.importTasks;
    return Column(
      children: [
        _HostedSectionMetaRow(
          text: l10n.photosHostedToolbarCount(tasks.length),
        ),
        Expanded(
          child:
              tasks.isEmpty
                  ? Center(
                    child: Text(
                      l10n.filesEmpty,
                      style: const TextStyle(
                        color: MobileEnvColors.inkMuted,
                        fontSize: 13, // ignore: font_size_whitelist
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _HostedInfoRow(
                        icon: Icons.cloud_download_outlined,
                        title: task.sourcePath,
                        subtitle: task.status,
                        trailing: _HostedStatusChip(
                          label: task.status,
                          status: task.status,
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
      color: const Color(0x0FFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: const BorderSide(color: MobileEnvColors.line09),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              Icon(icon, size: 15, color: MobileEnvColors.ink),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9, // ignore: font_size_whitelist
                  color: MobileEnvColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
