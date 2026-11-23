part of 'desktop_files_page.dart';

/// 左侧分区轨：分区 + 文件夹树 + 存储用量（样例 `.fx-tree`）。
///
/// 样例把整条轨道做成一块独立玻璃面板（`desktop.css:446`：圆角 20、
/// `--panel` 半透明底、1px 边线、`backdrop-filter: blur(20px)`），
/// 内部再排分区标题与导航行。此前这里只画了透明的行，轨道落在页面底色上，
/// 与样例的层级差一整层容器，所以面板在这里收口。
class _FilesRail extends StatefulWidget {
  const _FilesRail({
    required this.state,
    required this.section,
    required this.stats,
    required this.onSection,
    required this.onSharedRoot,
    required this.onSpaceChanged,
    required this.onOpenFolder,
    required this.onMoveFiles,
  });

  final FileBrowserState? state;
  final FileManagerSection section;
  final FileStorageStats? stats;
  final ValueChanged<FileManagerSection> onSection;
  final VoidCallback onSharedRoot;
  final ValueChanged<String> onSpaceChanged;
  final void Function(FileNode folder, List<FileNode> breadcrumbs) onOpenFolder;

  /// 目录树/根条目接收拖放：ids 落到 targetParentId（空串表示根）。
  final Future<void> Function(List<String> ids, String targetParentId)
  onMoveFiles;

  @override
  State<_FilesRail> createState() => _FilesRailState();
}

class _FilesRailState extends State<_FilesRail> {
  final GlobalKey<_FolderTreeState> _folderTreeKey =
      GlobalKey<_FolderTreeState>();

  Future<void> _moveFiles(List<String> ids, String targetParentId) async {
    try {
      await widget.onMoveFiles(ids, targetParentId);
    } finally {
      if (mounted) {
        _folderTreeKey.currentState?.refreshAfterMove();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final currentId =
        widget.state != null &&
                widget.state!.section == FileManagerSection.allFiles
            ? (widget.state!.spaceType == 'SHARED'
                ? widget.state!.sharedSpaceBreadcrumbs.isEmpty
                    ? null
                    : widget.state!.sharedSpaceBreadcrumbs.last.id
                : widget.state!.breadcrumbs.isEmpty
                ? null
                : widget.state!.breadcrumbs.last.id)
            : null;
    final canDrop = widget.section == FileManagerSection.allFiles;
    final shared = widget.state?.spaceType == 'SHARED';
    return DesktopGlassSurface(
      borderRadius: BorderRadius.circular(_FilesRailGeometry.radius),
      blur: _FilesRailGeometry.blur,
      saturation: _FilesRailGeometry.saturation,
      child: Container(
        padding: _FilesRailGeometry.padding,
        decoration: BoxDecoration(
          color: skin.panel,
          borderRadius: BorderRadius.circular(_FilesRailGeometry.radius),
          border: Border.all(color: skin.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RailSpaceSwitch(shared: shared, onChanged: widget.onSpaceChanged),
            const SizedBox(height: 10),
            if (!shared) ...[
              _RailGroupLabel(l10n.desktopFilesGroupLibrary),
              _RailItem(
                label: l10n.desktopFilesAll,
                icon: DesktopIcons.folderFilled,
                active:
                    widget.section == FileManagerSection.allFiles &&
                    currentId == null,
                onTap: () => widget.onSection(FileManagerSection.allFiles),
                onDropFiles: canDrop ? (ids) => _moveFiles(ids, '') : null,
              ),
              _FolderTree(
                key: _folderTreeKey,
                state: widget.state,
                currentId: currentId,
                onOpen: widget.onOpenFolder,
                onSection: () => widget.onSection(FileManagerSection.allFiles),
                onMoveFiles: _moveFiles,
              ),
              _RailItem(
                label: l10n.filesRecent,
                icon: DesktopIcons.clock,
                active: widget.section == FileManagerSection.recent,
                onTap: () => widget.onSection(FileManagerSection.recent),
              ),
              _RailItem(
                label: l10n.filesFavorites,
                icon: DesktopIcons.star,
                count: widget.state?.favoriteFiles.length,
                active: widget.section == FileManagerSection.favorites,
                onTap: () => widget.onSection(FileManagerSection.favorites),
              ),
              _RailGroupLabel(l10n.desktopFilesGroupSharing, gap: true),
              _RailItem(
                label: l10n.desktopFilesSharedByMe,
                icon: DesktopIcons.link,
                count: widget.state?.myShares.length,
                active:
                    widget.section == FileManagerSection.myShares ||
                    widget.section == FileManagerSection.shareManagement,
                onTap: () => widget.onSection(FileManagerSection.myShares),
              ),
              _RailItem(
                label: l10n.filesSharedWithMe,
                icon: DesktopIcons.user,
                count: widget.state?.sharedWithMe.length,
                active: widget.section == FileManagerSection.sharedWithMe,
                onTap: () => widget.onSection(FileManagerSection.sharedWithMe),
              ),
              _RailGroupLabel(l10n.desktopFilesGroupSources, gap: true),
              _RailItem(
                label: l10n.filesExternalStorage,
                icon: DesktopIcons.server,
                count: widget.state?.externalAccounts.length,
                active: widget.section == FileManagerSection.externalStorage,
                onTap:
                    () => widget.onSection(FileManagerSection.externalStorage),
              ),
              _RailItem(
                label: l10n.filesRecycleBin,
                icon: DesktopIcons.trash,
                count: widget.state?.recycleBin.length,
                active: widget.section == FileManagerSection.recycleBin,
                onTap: () => widget.onSection(FileManagerSection.recycleBin),
              ),
            ] else ...[
              _RailGroupLabel(l10n.filesSharedSpace),
              _RailItem(
                label: l10n.filesSharedSpace,
                icon: DesktopIcons.users,
                active:
                    widget.section == FileManagerSection.allFiles &&
                    currentId == null,
                onTap: widget.onSharedRoot,
                onDropFiles: canDrop ? (ids) => _moveFiles(ids, '') : null,
              ),
              _FolderTree(
                key: _folderTreeKey,
                state: widget.state,
                currentId: currentId,
                onOpen: widget.onOpenFolder,
                // 共享空间中的树节点已经处于 allFiles；点击节点只打开它，
                // 不先回根目录，否则两次异步导航会互相覆盖面包屑。
                onSection: () {},
                onMoveFiles: _moveFiles,
              ),
              if (widget.state?.sharedSpaceUsage != null) ...[
                _RailGroupLabel(l10n.filesSharedSpaceUsage, gap: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Text(
                    '${formatFileSize(widget.state!.sharedSpaceUsage!.usedBytes)} · '
                    '${l10n.desktopFilesItemCount(widget.state!.sharedSpaceUsage!.fileCount)}',
                    style: DesktopType.caption(skin.text3),
                  ),
                ),
              ],
            ],
            if (shared && widget.state?.sharedSpaceUsage != null)
              _RailSharedStorageCard(usage: widget.state!.sharedSpaceUsage!)
            else if (widget.stats != null)
              _RailStorageCard(stats: widget.stats!),
          ],
        ),
      ),
    );
  }
}

/// 轨道几何：逐值取 `desktop.css:446` 与 `polish.css:245`。
abstract final class _FilesRailGeometry {
  static const double radius = 20;
  static const double blur = 20;
  static const double saturation = 1.3;
  static const EdgeInsets padding = EdgeInsets.fromLTRB(10, 14, 10, 14);
  // 最终 polish.css 覆盖：顶层 tree-item 为 38px，tree-row 内节点为 34px。
  static const double navHeight = 38;
  static const double nodeHeight = 34;
  static const double folderIconSize = 15;
}

class _RailGroupLabel extends StatelessWidget {
  const _RailGroupLabel(this.label, {this.gap = false});

  final String label;

  /// 样例 `.fx-tree .eyebrow.gap`：上分隔线 + 14/12 的额外间距。
  final bool gap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Text(label.toUpperCase(), style: DesktopType.eyebrow(skin.text3)),
    );
    if (!gap) {
      return text;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: skin.line)),
        ),
        child: text,
      ),
    );
  }
}

/// 原型 `.space-switch`：空间切换是文件树的上下文，而不是普通分区。
/// 选中态保留面板底和阴影，避免切换时侧栏整体跳动。
class _RailSpaceSwitch extends StatelessWidget {
  const _RailSpaceSwitch({required this.shared, required this.onChanged});

  final bool shared;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RailSpaceButton(
              label: l10n.importToPersonalSpace,
              icon: DesktopIcons.user,
              selected: !shared,
              onTap: () => onChanged('PERSONAL'),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _RailSpaceButton(
              label: l10n.importToSharedSpace,
              icon: DesktopIcons.users,
              selected: shared,
              onTap: () => onChanged('SHARED'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailSpaceButton extends StatelessWidget {
  const _RailSpaceButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Tooltip(
      message: label,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color:
                      selected
                          ? skin.panelSolid
                          : hovered
                          ? skin.raise2
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow:
                      selected
                          ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                          : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: selected ? skin.accent : skin.text2,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(
                          selected ? skin.text : skin.text2,
                        ).copyWith(
                          fontWeight: selected ? FontWeight.w600 : null,
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

/// 分区导航行（样例 `.tree-item` 34px，圆角 9，hover `--raise`）。
///
/// `onDropFiles` 非空时整行同时是拖放目标（样例 `nav()` 给 My files 挂了
/// `dropProps("root")`），落点高亮走 `.tree-item.drop` 的 accent 22% 底
/// 与 1.5px 内描边。
class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.count,
    this.onDropFiles,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final Future<void> Function(List<String> ids)? onDropFiles;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _dropping = false;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    Widget row(bool hovered) {
      return GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: DesktopMotion.of(context, DesktopMotion.fast),
          height: _FilesRailGeometry.navHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color:
                _dropping
                    ? skin.accentWash(0.22)
                    : widget.active
                    ? skin.raise2
                    : hovered
                    ? skin.raise
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border:
                _dropping
                    ? Border.all(
                      color: skin.accent,
                      width: DesktopMetrics.hairlineStrong,
                    )
                    : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: _FilesRailGeometry.folderIconSize,
                color: widget.active ? skin.accent : skin.text2,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.navItem(
                    widget.active ? skin.text : skin.text2,
                  ),
                ),
              ),
              if (widget.count != null && widget.count! > 0)
                Text('${widget.count}', style: DesktopType.numeric(skin.text3)),
            ],
          ),
        ),
      );
    }

    Widget content = DesktopHover(
      builder:
          (context, hovered) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: row(hovered),
          ),
    );
    final onDropFiles = widget.onDropFiles;
    if (onDropFiles == null) {
      return content;
    }
    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) async {
        setState(() => _dropping = false);
        try {
          await onDropFiles(details.data);
        } on Object catch (error) {
          // 捕获的是 build 的 BuildContext 参数，必须用它自己的 mounted 判定。
          if (!context.mounted) {
            return;
          }
          final l10n = AppLocalizations.of(context);
          showDesktopToast(
            context,
            failureToast(l10n, l10n.filesOpMove, error),
            kind: DesktopToastKind.error,
            icon: DesktopIcons.info,
          );
        }
      },
      onMove: (_) {
        if (!_dropping) {
          setState(() => _dropping = true);
        }
      },
      onLeave: (_) {
        if (_dropping) {
          setState(() => _dropping = false);
        }
      },
      builder: (context, candidate, rejected) => content,
    );
  }
}
