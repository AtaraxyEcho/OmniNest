part of 'desktop_files_page.dart';

/// 左侧分区轨：分区 + 文件夹树 + 存储用量（样例 `.fx-tree`）。
class _FilesRail extends StatelessWidget {
  const _FilesRail({
    required this.state,
    required this.section,
    required this.stats,
    required this.onSection,
    required this.onOpenFolder,
  });

  final FileBrowserState? state;
  final FileManagerSection section;
  final FileStorageStats? stats;
  final ValueChanged<FileManagerSection> onSection;
  final ValueChanged<FileNode> onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final currentId =
        state != null && state!.section == FileManagerSection.allFiles
            ? state!.breadcrumbs.isEmpty
                ? null
                : state!.breadcrumbs.last.id
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailGroupLabel(l10n.desktopFilesGroupLibrary),
        _RailItem(
          label: l10n.desktopFilesAll,
          icon: DesktopIcons.folderFilled,
          active: section == FileManagerSection.allFiles && currentId == null,
          onTap: () => onSection(FileManagerSection.allFiles),
        ),
        _FolderTree(
          currentId: currentId,
          onOpen: onOpenFolder,
          onSection: () => onSection(FileManagerSection.allFiles),
        ),
        _RailItem(
          label: l10n.filesRecent,
          icon: DesktopIcons.clock,
          active: section == FileManagerSection.recent,
          onTap: () => onSection(FileManagerSection.recent),
        ),
        _RailItem(
          label: l10n.filesFavorites,
          icon: DesktopIcons.star,
          count: state?.favoriteFiles.length,
          active: section == FileManagerSection.favorites,
          onTap: () => onSection(FileManagerSection.favorites),
        ),
        const SizedBox(height: 14),
        _RailGroupLabel(l10n.desktopFilesGroupSharing),
        _RailItem(
          label: l10n.desktopFilesSharedByMe,
          icon: DesktopIcons.link,
          count: state?.myShares.length,
          active:
              section == FileManagerSection.myShares ||
              section == FileManagerSection.shareManagement,
          onTap: () => onSection(FileManagerSection.myShares),
        ),
        _RailItem(
          label: l10n.filesSharedWithMe,
          icon: DesktopIcons.user,
          count: state?.sharedWithMe.length,
          active: section == FileManagerSection.sharedWithMe,
          onTap: () => onSection(FileManagerSection.sharedWithMe),
        ),
        _RailItem(
          label: l10n.filesSharedSpace,
          icon: DesktopIcons.users,
          active: section == FileManagerSection.sharedSpace,
          onTap: () => onSection(FileManagerSection.sharedSpace),
        ),
        const SizedBox(height: 14),
        _RailGroupLabel(l10n.desktopFilesGroupSources),
        _RailItem(
          label: l10n.filesExternalStorage,
          icon: DesktopIcons.server,
          count: state?.externalAccounts.length,
          active: section == FileManagerSection.externalStorage,
          onTap: () => onSection(FileManagerSection.externalStorage),
        ),
        _RailItem(
          label: l10n.filesRecycleBin,
          icon: DesktopIcons.trash,
          count: state?.recycleBin.length,
          active: section == FileManagerSection.recycleBin,
          onTap: () => onSection(FileManagerSection.recycleBin),
        ),
        if (stats != null) ...[
          const SizedBox(height: 20),
          _RailStorageCard(
            stats: stats!,
            onTap: () => onSection(FileManagerSection.storageStats),
          ),
        ],
        const SizedBox(height: 8),
        // 轨道最底的一条极淡分隔线，和样例 `.fx-tree` 收口一致。
        Container(height: 1, color: skin.line.withValues(alpha: 0.4)),
      ],
    );
  }
}

class _RailGroupLabel extends StatelessWidget {
  const _RailGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Text(label.toUpperCase(), style: DesktopType.eyebrow(skin.text3)),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                height: DesktopMetrics.navItemHeightCompact + 3,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color:
                      active
                          ? skin.raise2
                          : hovered
                          ? skin.raise
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusButton,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: DesktopMetrics.iconSmall,
                      color: active ? skin.accent : skin.text2,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.navItem(
                          active ? skin.text : skin.text2,
                        ),
                      ),
                    ),
                    if (count != null && count! > 0)
                      Text('$count', style: DesktopType.numeric(skin.text3)),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

/// 文件夹树：根级一次拉取，展开时才拉子级。
///
/// 后端没有"整棵树"接口，逐层加载是唯一不造重复请求的做法；
/// 树只是导航辅助，取数失败时静默留空，不阻断主列表。
class _FolderTree extends ConsumerStatefulWidget {
  const _FolderTree({
    required this.currentId,
    required this.onOpen,
    required this.onSection,
  });

  final String? currentId;
  final ValueChanged<FileNode> onOpen;
  final VoidCallback onSection;

  @override
  ConsumerState<_FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends ConsumerState<_FolderTree> {
  final Map<String, List<FileNode>> _children = <String, List<FileNode>>{};
  final Set<String> _open = <String>{};
  bool _loadedRoot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(null));
  }

  Future<void> _load(String? parentId) async {
    if (_children.containsKey(parentId ?? '')) {
      return;
    }
    try {
      final nodes = await ref
          .read(fileBrowserControllerProvider.notifier)
          .listFolderOptions(parentId);
      if (!mounted) {
        return;
      }
      setState(() {
        _children[parentId ?? ''] = nodes
            .where((node) => node.isFolder)
            .toList(growable: false);
        _loadedRoot = true;
      });
    } on Object {
      if (mounted) {
        setState(() => _loadedRoot = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final root = _children[''] ?? const <FileNode>[];
    if (_loadedRoot && root.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!_loadedRoot) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 1,
            height: 2,
            margin: const EdgeInsets.only(left: 6),
            color: skin.line,
          ),
          for (final folder in root) ..._buildNode(folder, 1),
        ],
      ),
    );
  }

  List<Widget> _buildNode(FileNode folder, int depth) {
    final skin = DesktopSkin.of(context);
    final children = _children[folder.id];
    final open = _open.contains(folder.id);
    return [
      Padding(
        padding: EdgeInsets.only(left: (depth - 1) * 12.0),
        child: DesktopHover(
          builder:
              (context, hovered) => GestureDetector(
                onTap: () {
                  widget.onSection();
                  widget.onOpen(folder);
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  decoration: BoxDecoration(
                    color:
                        widget.currentId == folder.id
                            ? skin.raise2
                            : hovered
                            ? skin.raise
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      DesktopMetrics.radiusSmall,
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (open) {
                              _open.remove(folder.id);
                            } else {
                              _open.add(folder.id);
                              unawaited(_load(folder.id));
                            }
                          });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: 16,
                          height: 20,
                          child: Icon(
                            open ? DesktopIcons.chevDown : DesktopIcons.chevron,
                            size: 12,
                            color: skin.text3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        DesktopIcons.folder,
                        size: 13,
                        color:
                            widget.currentId == folder.id
                                ? skin.accent
                                : skin.text3,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.navSub(
                            widget.currentId == folder.id
                                ? skin.text
                                : skin.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
      if (open)
        for (final child in children ?? const <FileNode>[])
          ..._buildNode(child, depth + 1),
    ];
  }
}

class _RailStorageCard extends StatelessWidget {
  const _RailStorageCard({required this.stats, required this.onTap});

  final FileStorageStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final types = stats.typeDistribution.take(3).toList(growable: false);
    final remainingBytes = stats.typeDistribution
        .skip(3)
        .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    final segments = <({String label, int bytes, Color color})>[
      for (var index = 0; index < types.length; index++)
        (
          label: _categoryLabel(l10n, types[index].category),
          bytes: types[index].sizeBytes,
          color: switch (index) {
            0 => skin.accent,
            1 => skin.info,
            _ => skin.warn,
          },
        ),
      if (remainingBytes > 0)
        (
          label: l10n.filesCategoryOther,
          bytes: remainingBytes,
          color: skin.text3,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: hovered ? skin.raise : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.desktopFilesGroupStorage.toUpperCase(),
                      style: DesktopType.eyebrow(skin.text3),
                    ),
                    const SizedBox(height: 9),
                    if (segments.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              for (final segment in segments)
                                Expanded(
                                  flex: segment.bytes.clamp(1, 0x7fffffff),
                                  child: ColoredBox(color: segment.color),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      DesktopProgress(fraction: stats.usageRatio),
                    if (segments.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      for (final segment in segments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: segment.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  segment.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.nano(skin.text2),
                                ),
                              ),
                              Text(
                                formatFileSize(segment.bytes),
                                style: DesktopType.nano(skin.text3),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      l10n.desktopFilesStorageUsed(
                        formatFileSize(stats.usedBytes),
                        stats.isQuotaUnlimited
                            ? l10n.filesUnlimited
                            : formatFileSize(stats.quotaBytes),
                      ),
                      style: DesktopType.caption(skin.text3),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  String _categoryLabel(AppLocalizations l10n, String category) =>
      switch (category.toUpperCase()) {
        'FOLDER' => l10n.filesCategoryFolder,
        'IMAGE' || 'PHOTO' => l10n.filesCategoryImage,
        'VIDEO' => l10n.filesCategoryVideo,
        'AUDIO' => l10n.filesCategoryAudio,
        'DOCUMENT' || 'PDF' || 'TEXT' => l10n.filesCategoryDocument,
        'NOVEL' => l10n.filesCategoryNovel,
        'COMIC' => l10n.filesCategoryComic,
        'ARCHIVE' => l10n.filesCategoryArchive,
        _ => l10n.filesCategoryOther,
      };
}
