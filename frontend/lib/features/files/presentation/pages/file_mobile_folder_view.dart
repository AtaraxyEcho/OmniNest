part of 'file_browser_page.dart';

/// 样例 FolderView 的托管移动工作区头：模块横幅（返回圆钮 + 目录名/
/// 分区名 + 副题 + 右侧动作圆钮）。
///
/// 副题按分区取自己的口径：目录分区沿用样例 FolderView 的「路径 · 条数」，
/// 其余分区给该分区自己的真实计数——原先统一复用工位列表的文件数，对最近/
/// 收藏/共享等分区是错数（冷入口为 0，从目录进则是上一个目录的条数）。
class _MobileFolderHeader extends ConsumerWidget {
  const _MobileFolderHeader({
    required this.state,
    required this.controller,
    required this.onBack,
  });

  final FileBrowserState state;
  final FileBrowserController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final inFolder =
        state.section == FileManagerSection.allFiles &&
        state.breadcrumbs.isNotEmpty;
    return MobileModuleHeader(
      title:
          inFolder ? state.breadcrumbs.last.name : state.section.labelOf(l10n),
      subtitle: _subtitleOf(l10n),
      onBack: onBack,
      actions: _actionsOf(context, ref),
    );
  }

  String _subtitleOf(AppLocalizations l10n) {
    switch (state.section) {
      case FileManagerSection.allFiles:
        final crumbs = state.breadcrumbs.map((node) => node.name).join(' / ');
        final count = l10n.filesFolderItemCount(state.files.length);
        return crumbs.isEmpty ? count : '$crumbs · $count';
      case FileManagerSection.sharedSpace:
        return '${FileManagerSection.sharedSpace.labelOf(l10n)} · '
            '${l10n.filesFolderItemCount(state.files.length)}';
      case FileManagerSection.recent:
        return l10n.filesHostedItemCount(state.recentMeta.totalElements);
      case FileManagerSection.favorites:
        return l10n.filesHostedItemCount(state.favoritesMeta.totalElements);
      case FileManagerSection.recycleBin:
        return l10n.filesHostedItemCount(state.recycleMeta.totalElements);
      case FileManagerSection.sharedWithMe:
        return l10n.filesHostedItemCount(state.sharedWithMeMeta.totalElements);
      case FileManagerSection.myShares:
      case FileManagerSection.shareManagement:
        return l10n.filesHostedItemCount(state.sharesMeta.totalElements);
      case FileManagerSection.uploadQueue:
        return l10n.filesHostedItemCount(state.uploadQueueMeta.totalElements);
      case FileManagerSection.externalStorage:
        return l10n.filesHostedItemCount(
          state.externalBrowseAccountId == null
              ? state.externalAccounts.length
              : state.externalMeta.totalElements,
        );
      case FileManagerSection.importTasks:
        return l10n.filesHostedItemCount(state.importMeta.totalElements);
      case FileManagerSection.storageStats:
        return FileManagerSection.storageStats.descriptionOf(l10n);
    }
  }

  List<Widget> _actionsOf(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (state.section) {
      // 样例 FeaturePage 三页不复用 FolderView 的上传圆钮。
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.sharedWithMe => const <Widget>[],
      _ => <Widget>[
        if (_canCreateFolder(ref, state))
          MobileGlassIconButton(
            tooltip: l10n.filesNewFolder,
            icon: Icons.create_new_folder_outlined,
            onPressed:
                () => unawaited(
                  showNewFolderNameDialog(context, controller, state),
                ),
          ),
        MobileGlassIconButton(
          tooltip: l10n.portalQuickUpload,
          icon: Icons.add_rounded,
          onPressed: () => unawaited(_pickAndUploadFiles(context, controller)),
        ),
      ],
    };
  }

  /// 目录分区、有贡献权且不在写入中时，页头才给新建文件夹
  /// （回收站/共享空间/只读分区不给；判据与移动端「+」面板同源）。
  bool _canCreateFolder(WidgetRef ref, FileBrowserState state) {
    return ref.read(userCapabilitiesProvider).canContributeContent &&
        state.section == FileManagerSection.allFiles &&
        !state.isBusy;
  }
}

/// 移动端新建文件夹：走命名对话框。
///
/// 工位走就地草稿行（`beginFolderCreation` → FileList 的第 0 行），但托管
/// 首页的内联列表没有草稿行的宿主，此前首页「+ → 新建文件夹」只写了
/// `draftFolderName` 就再无下文——点了没反应就是这条。移动端统一用可见输入框。
Future<void> showNewFolderNameDialog(
  BuildContext context,
  FileBrowserController controller,
  FileBrowserState state,
) async {
  final l10n = AppLocalizations.of(context);
  await _showNameDialog(
    context: context,
    title: l10n.filesNewFolder,
    actionLabel: l10n.filesCreate,
    labelText: l10n.filesFolderName,
    initialValue: dedupeFolderName(l10n.filesNewFolderDefault, state.files),
    onSubmit: (name) => controller.createFolder(name),
  );
}

/// 样例 FolderView 三档分段（Files/Shared/Recycle），左对齐。
class _MobileFolderSegments extends ConsumerWidget {
  const _MobileFolderSegments({required this.state});

  final FileBrowserState state;

  static const _sections = <FileManagerSection>[
    FileManagerSection.allFiles,
    FileManagerSection.sharedSpace,
    FileManagerSection.recycleBin,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final effective =
        _sections.contains(state.section) ? state.section : _sections.first;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: MobileSegmentedControl<FileManagerSection>(
          values: _sections,
          selected: effective,
          labelBuilder:
              (section) => switch (section) {
                FileManagerSection.allFiles => l10n.filesHomeTabMyFiles,
                FileManagerSection.sharedSpace => l10n.filesSharedSpace,
                _ => l10n.filesRecycleBin,
              },
          onSelected: (section) {
            unawaited(
              _runFileAction(context, () => controller.loadSection(section)),
            );
          },
        ),
      ),
    );
  }
}

/// Shared 档的分享管理入口（样例 share-manage-entry：酸绿 7% 底、
/// 居中图标 + 文案 + 箭头）。
class _MobileShareManageEntry extends StatelessWidget {
  const _MobileShareManageEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: context.env.accentInk.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OmniIcon(
                  icon: OmniIcons.share,
                  size: 17,
                  color: context.env.ink,
                ),
                const SizedBox(width: 7),
                Text(
                  l10n.filesShareManageEntry,
                  style: TextStyle(
                    fontSize: 10, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(width: 7),
                OmniIcon(
                  icon: OmniIcons.chevron,
                  size: 15,
                  color: context.env.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 样例 FolderView 的主体判定：三档分段覆盖的分区走托管行列表形态。
bool _isMobileFolderSection(FileManagerSection section) {
  return switch (section) {
    FileManagerSection.allFiles ||
    FileManagerSection.sharedSpace ||
    FileManagerSection.recycleBin => true,
    _ => false,
  };
}

/// 固定「返回上一级」栏：子目录内钉在分段与列表之间，点击回到上级目录。
class _MobileGoUpBar extends StatelessWidget {
  const _MobileGoUpBar({required this.parentName, required this.onTap});

  final String parentName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  Icons.expand_less_rounded,
                  size: 20,
                  color: context.env.accentInk,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).videoBackToParentNode,
                  style: TextStyle(
                    fontSize: 11, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    parentName,
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
