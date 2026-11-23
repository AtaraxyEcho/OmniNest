part of 'desktop_files_page.dart';

/// 左侧分区轨：顶部固定空间切换 + 中部独立滚动导航与虚拟化目录树 + 底部固定存储卡。
class _FilesRail extends StatefulWidget {
  const _FilesRail({
    required this.state,
    required this.section,
    required this.stats,
    required this.onSection,
    required this.onSharedRoot,
    required this.onSharedRecent,
    required this.onSharedUploadedByMe,
    required this.onSpaceChanged,
    required this.onOpenFolder,
    required this.onMoveFiles,
    this.onNewFolder,
  });

  final FileBrowserState? state;
  final FileManagerSection section;
  final FileStorageStats? stats;
  final ValueChanged<FileManagerSection> onSection;
  final VoidCallback onSharedRoot;
  final VoidCallback onSharedRecent;
  final VoidCallback onSharedUploadedByMe;
  final VoidCallback? onNewFolder;
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
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final state = widget.state;
    final shared = state?.spaceType == 'SHARED';
    final sharedQuickRecent =
        shared &&
        widget.section == FileManagerSection.allFiles &&
        state?.sharedSort == 'updatedAt,desc';
    final sharedQuickUploaded =
        shared &&
        widget.section == FileManagerSection.allFiles &&
        (state?.sharedUploadedByMe ?? false);
    final currentId =
        state != null && state.section == FileManagerSection.allFiles
            ? (shared
                ? state.sharedSpaceBreadcrumbs.isEmpty
                    ? null
                    : state.sharedSpaceBreadcrumbs.last.id
                : state.breadcrumbs.isEmpty
                ? null
                : state.breadcrumbs.last.id)
            : null;
    final canDrop = widget.section == FileManagerSection.allFiles;

    final List<Widget> leadingItems;
    final List<Widget> trailingItems;
    if (!shared) {
      leadingItems = <Widget>[
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
      ];
      trailingItems = <Widget>[
        _RailItem(
          label: l10n.filesRecent,
          icon: DesktopIcons.clock,
          active: widget.section == FileManagerSection.recent,
          onTap: () => widget.onSection(FileManagerSection.recent),
        ),
        _RailItem(
          label: l10n.filesFavorites,
          icon: DesktopIcons.star,
          count: state?.favoriteFiles.length,
          active: widget.section == FileManagerSection.favorites,
          onTap: () => widget.onSection(FileManagerSection.favorites),
        ),
        _RailGroupLabel(l10n.desktopFilesGroupSharing, gap: true),
        _RailItem(
          label: l10n.desktopFilesSharedByMe,
          icon: DesktopIcons.link,
          count: state?.myShares.length,
          active:
              widget.section == FileManagerSection.myShares ||
              widget.section == FileManagerSection.shareManagement,
          onTap: () => widget.onSection(FileManagerSection.myShares),
        ),
        _RailItem(
          label: l10n.filesSharedWithMe,
          icon: DesktopIcons.user,
          count: state?.sharedWithMe.length,
          active: widget.section == FileManagerSection.sharedWithMe,
          onTap: () => widget.onSection(FileManagerSection.sharedWithMe),
        ),
        _RailGroupLabel(l10n.desktopFilesGroupSources, gap: true),
        _RailItem(
          label: l10n.filesExternalStorage,
          icon: DesktopIcons.server,
          count: state?.externalAccounts.length,
          active: widget.section == FileManagerSection.externalStorage,
          onTap: () => widget.onSection(FileManagerSection.externalStorage),
        ),
        _RailItem(
          label: l10n.filesRecycleBin,
          icon: DesktopIcons.trash,
          count: state?.recycleBin.length,
          active: widget.section == FileManagerSection.recycleBin,
          onTap: () => widget.onSection(FileManagerSection.recycleBin),
        ),
      ];
    } else {
      leadingItems = <Widget>[
        _RailGroupLabel(isZh ? '共享目录' : 'Shared folders'),
        _RailItem(
          label: isZh ? '全部共享文件' : 'All shared files',
          icon: DesktopIcons.users,
          active:
              widget.section == FileManagerSection.allFiles &&
              currentId == null &&
              !sharedQuickRecent &&
              !sharedQuickUploaded,
          onTap: widget.onSharedRoot,
          onDropFiles: canDrop ? (ids) => _moveFiles(ids, '') : null,
        ),
      ];
      trailingItems = <Widget>[
        _RailGroupLabel(isZh ? '快捷视图' : 'Quick views', gap: true),
        _RailItem(
          label: isZh ? '最近更新' : 'Recently updated',
          icon: DesktopIcons.clock,
          active: sharedQuickRecent,
          onTap: widget.onSharedRecent,
        ),
        _RailItem(
          label: isZh ? '我上传的' : 'Uploaded by me',
          icon: DesktopIcons.upload,
          active: sharedQuickUploaded,
          onTap: widget.onSharedUploadedByMe,
        ),
        _RailGroupLabel(isZh ? '协作分享' : 'Collaboration', gap: true),
        _RailItem(
          label: l10n.filesSharedWithMe,
          icon: DesktopIcons.user,
          count: state?.sharedWithMe.length,
          active: widget.section == FileManagerSection.sharedWithMe,
          onTap: () => widget.onSection(FileManagerSection.sharedWithMe),
        ),
        _RailItem(
          label: l10n.desktopFilesSharedByMe,
          icon: DesktopIcons.link,
          count: state?.myShares.length,
          active:
              widget.section == FileManagerSection.myShares ||
              widget.section == FileManagerSection.shareManagement,
          onTap: () => widget.onSection(FileManagerSection.myShares),
        ),
        _RailGroupLabel(isZh ? '管理' : 'Manage', gap: true),
        _RailItem(
          label: l10n.filesRecycleBin,
          icon: DesktopIcons.trash,
          count: state?.recycleBin.length,
          active: widget.section == FileManagerSection.recycleBin,
          onTap: () => widget.onSection(FileManagerSection.recycleBin),
        ),
      ];
    }

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
            Expanded(
              child: _FolderTree(
                key: _folderTreeKey,
                state: state,
                currentId: currentId,
                onOpen: widget.onOpenFolder,
                // 共享空间中的树节点已经处于 allFiles；点击节点只打开它，
                // 不先回根目录，否则两次异步导航会互相覆盖面包屑。
                onSection:
                    shared
                        ? () {}
                        : () => widget.onSection(FileManagerSection.allFiles),
                onMoveFiles: _moveFiles,
                onNewFolder: shared ? widget.onNewFolder : null,
                leadingItems: leadingItems,
                trailingItems: trailingItems,
              ),
            ),
            if (shared && state?.sharedSpaceUsage != null)
              _RailSharedStorageCard(usage: state!.sharedSpaceUsage!)
            else if (widget.stats != null)
              _RailStorageCard(stats: widget.stats!)
            else if (state == null)
              const _RailStorageSkeleton(),
          ],
        ),
      ),
    );
  }
}

/// 侧栏与主视图之间的可拖拽分隔条（200px–380px，双击重置 244px）。
class _RailResizeHandle extends StatefulWidget {
  const _RailResizeHandle({
    required this.width,
    required this.onChanged,
    required this.onReset,
  });

  static const double minWidth = 200.0;
  static const double maxWidth = 380.0;

  final double width;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  State<_RailResizeHandle> createState() => _RailResizeHandleState();
}

class _RailResizeHandleState extends State<_RailResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (details) {
          final next = (widget.width + details.delta.dx).clamp(
            _RailResizeHandle.minWidth,
            _RailResizeHandle.maxWidth,
          );
          if (next != widget.width) {
            widget.onChanged(next);
          }
        },
        child: SizedBox(
          width: 22,
          child: Center(
            child: AnimatedContainer(
              duration: DesktopMotion.of(context, DesktopMotion.fast),
              width: active ? 3 : 1,
              height: active ? 56 : 28,
              decoration: BoxDecoration(
                color:
                    _dragging
                        ? skin.accent
                        : _hovered
                        ? skin.text3.withValues(alpha: 0.55)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
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

/// 展平后的可见树节点，供 `SliverFixedExtentList.builder` 虚拟化渲染。
class _VisibleTreeNode {
  const _VisibleTreeNode({
    required this.folder,
    required this.depth,
    required this.path,
  });

  final FileNode folder;
  final int depth;
  final List<FileNode> path;
}

class _TreeMiniAction extends StatelessWidget {
  const _TreeMiniAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Tooltip(
      message: tooltip,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: enabled ? onTap : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color:
                      active
                          ? skin.accentWash(0.16)
                          : (enabled && hovered)
                          ? skin.raise
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  size: 13,
                  color:
                      !enabled
                          ? skin.text3.withValues(alpha: 0.4)
                          : active
                          ? skin.accent
                          : skin.text2,
                ),
              ),
            ),
      ),
    );
  }
}
