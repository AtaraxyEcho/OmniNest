part of 'file_browser_page.dart';

/// 原型 `.tool-shortcuts`：首页工作区工具入口（外部存储 / 导入任务 /
/// 上传队列），点击进入对应分区列表态。
///
/// 副题只取已加载的真实数据；分区数据要打开该分区才拉取，未加载时
/// 回退到分区说明文案，不编造计数。
class _HomeToolShortcuts extends StatelessWidget {
  const _HomeToolShortcuts({required this.state, required this.onOpenSection});

  final FileBrowserState state;
  final ValueChanged<FileManagerSection> onOpenSection;

  static bool _isOnlineAccount(ExternalStorageAccount account) {
    return switch (account.status.toUpperCase()) {
      'CONNECTED' || 'ONLINE' || 'ACTIVE' => true,
      _ => false,
    };
  }

  static bool _isRunningStatus(String status) {
    return switch (status.toUpperCase()) {
      'COMPLETED' || 'FAILED' || 'ERROR' || 'CANCELLED' || 'CANCELED' => false,
      _ => true,
    };
  }

  String _externalSubtitle(AppLocalizations l10n) {
    final accounts = state.externalAccounts;
    if (accounts.isEmpty) {
      return l10n.filesExternalStorageDesc;
    }
    final online = accounts.where(_isOnlineAccount).length;
    return l10n.filesHomeShortcutMountsOnline(online, accounts.length);
  }

  String _importSubtitle(AppLocalizations l10n) {
    final active =
        state.importTasks.where((task) => _isRunningStatus(task.status)).length;
    return active > 0
        ? l10n.filesHomeShortcutTasksActive(active)
        : l10n.filesImportTasksDesc;
  }

  String _uploadSubtitle(AppLocalizations l10n) {
    var remaining = 0;
    for (final task in state.localUploadTasks) {
      if (!FileBrowserState.isTerminalUploadStatus(task.status)) {
        remaining += (task.sizeBytes - task.uploadedBytes).clamp(
          0,
          task.sizeBytes,
        );
      }
    }
    for (final item in state.uploadQueue) {
      if (!FileBrowserState.isTerminalUploadStatus(item.status)) {
        remaining += (item.sizeBytes * (1 - item.progress)).round();
      }
    }
    return remaining > 0
        ? l10n.filesHomeShortcutUploadRemaining(formatFileSize(remaining))
        : l10n.filesUploadQueueDesc;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(FileManagerSection, OmniIconsData, String)>[
      (
        FileManagerSection.externalStorage,
        OmniIcons.device,
        _externalSubtitle(l10n),
      ),
      (
        FileManagerSection.importTasks,
        OmniIcons.download,
        _importSubtitle(l10n),
      ),
      (FileManagerSection.uploadQueue, OmniIcons.queue, _uploadSubtitle(l10n)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0) const SizedBox(height: 7),
            _HomeToolShortcutRow(
              icon: entries[index].$2,
              title: entries[index].$1.labelOf(l10n),
              detail: entries[index].$3,
              onTap: () => onOpenSection(entries[index].$1),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单行工具入口（原型 `.tool-shortcuts > button`：58 高 r15 卡面 +
/// 酸绿首图标 + 名称/说明 + 弱化箭头）。
class _HomeToolShortcutRow extends StatelessWidget {
  const _HomeToolShortcutRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final OmniIconsData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: title,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.env.surfaceTint,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: context.env.line07),
        ),
        child: Row(
          children: [
            OmniIcon(icon: icon, size: 18, color: context.env.accentInk),
            const SizedBox(width: 11),
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
                      fontWeight: FontWeight.w700,
                      color: context.env.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      color: context.env.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            OmniIcon(
              icon: OmniIcons.chevron,
              size: 16,
              color: context.env.ink40,
            ),
          ],
        ),
      ),
    );
  }
}

/// 目录原地展开态的内联返回上级栏：一级目录回空间根，更深层回上级。
class _InlineGoUpBar extends StatelessWidget {
  const _InlineGoUpBar({required this.state, required this.controller});

  final FileBrowserState state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final crumbs = state.breadcrumbs;
    final atFirstLevel = crumbs.length == 1;
    final label =
        atFirstLevel
            ? (state.spaceType == 'SHARED'
                ? l10n.filesSharedSpace
                : l10n.filesHomeTabMyFiles)
            : crumbs[crumbs.length - 2].name;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            unawaited(
              atFirstLevel
                  ? controller.goToRoot()
                  : controller.goToBreadcrumb(crumbs.length - 2),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.expand_less_rounded,
                  size: 20,
                  color: context.env.accentInk,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.videoBackToParentNode,
                  style: TextStyle(
                    fontSize: 11, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10, // ignore: font_size_whitelist
                      color: context.env.inkFaint,
                    ),
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
