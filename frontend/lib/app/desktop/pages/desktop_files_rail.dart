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
    required this.onOpenFolder,
    required this.onMoveFiles,
  });

  final FileBrowserState? state;
  final FileManagerSection section;
  final FileStorageStats? stats;
  final ValueChanged<FileManagerSection> onSection;
  final ValueChanged<FileNode> onOpenFolder;

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
            ? widget.state!.breadcrumbs.isEmpty
                ? null
                : widget.state!.breadcrumbs.last.id
            : null;
    final canDrop = widget.section == FileManagerSection.allFiles;
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
            _RailItem(
              label: l10n.filesSharedSpace,
              icon: DesktopIcons.users,
              active: widget.section == FileManagerSection.sharedSpace,
              onTap: () => widget.onSection(FileManagerSection.sharedSpace),
            ),
            _RailGroupLabel(l10n.desktopFilesGroupSources, gap: true),
            _RailItem(
              label: l10n.filesExternalStorage,
              icon: DesktopIcons.server,
              count: widget.state?.externalAccounts.length,
              active: widget.section == FileManagerSection.externalStorage,
              onTap: () => widget.onSection(FileManagerSection.externalStorage),
            ),
            _RailItem(
              label: l10n.filesRecycleBin,
              icon: DesktopIcons.trash,
              count: widget.state?.recycleBin.length,
              active: widget.section == FileManagerSection.recycleBin,
              onTap: () => widget.onSection(FileManagerSection.recycleBin),
            ),
            if (widget.stats != null) _RailStorageCard(stats: widget.stats!),
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
  static const double navHeight = 34;
  static const double nodeHeight = 32;
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
        await onDropFiles(details.data);
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

/// 文件夹树：根级一次拉取，展开时才拉子级。
///
/// 后端没有"整棵树"接口，逐层加载是唯一不造重复请求的做法；树只是导航辅助，
/// 取数失败时静默留空，不阻断主列表。
///
/// 与样例的同步语义：样例树直接从同一份 `files` 状态派生，新建目录后立刻
/// 出现在树上。这里保留逐层接口，但把当前目录的文件夹签名（id + 名称集）
/// 作为失效依据——列表一变化就丢掉该层缓存并重取，避免"列表有、树没有"。
class _FolderTree extends ConsumerStatefulWidget {
  const _FolderTree({
    super.key,
    required this.state,
    required this.currentId,
    required this.onOpen,
    required this.onSection,
    required this.onMoveFiles,
  });

  final FileBrowserState? state;
  final String? currentId;
  final ValueChanged<FileNode> onOpen;
  final VoidCallback onSection;
  final Future<void> Function(List<String> ids, String targetParentId)
  onMoveFiles;

  @override
  ConsumerState<_FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends ConsumerState<_FolderTree> {
  final Map<String, List<FileNode>> _children = <String, List<FileNode>>{};
  final Set<String> _open = <String>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  final Map<String, String> _parentSignatures = <String, String>{};
  final Map<String, int> _fetchGenerations = <String, int>{};
  bool _loadedRoot = false;
  String? _lastParentKey;

  /// 内部拖拽悬停 650ms 后展开目标目录（样例 `expandOnHover`）。
  Timer? _hoverTimer;
  String? _hoverFolderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(null));
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNode(String id) => _focusNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'files-tree-$id'),
  );

  Future<void> _load(String? parentId) async {
    final key = parentId ?? '';
    if (_children.containsKey(key)) {
      return;
    }
    await _fetch(key);
  }

  /// 绕过缓存重取一层；目录改动后调用。
  Future<void> _reload(String key) async {
    if (!mounted) {
      return;
    }
    await _fetch(key);
  }

  Future<void> _fetch(String key) async {
    final generation = (_fetchGenerations[key] ?? 0) + 1;
    _fetchGenerations[key] = generation;
    try {
      final nodes = await ref
          .read(fileBrowserControllerProvider.notifier)
          .listFolderOptions(key.isEmpty ? null : key);
      if (!mounted || _fetchGenerations[key] != generation) {
        return;
      }
      setState(() {
        _children[key] = _sortedFolders(nodes);
        _loadedRoot = true;
      });
    } on Object {
      if (mounted && _fetchGenerations[key] == generation) {
        setState(() => _loadedRoot = true);
      }
    }
  }

  /// 样例 `treeFolders` 用 `localeCompare(numeric: true)` 按名称排序。
  static List<FileNode> _sortedFolders(List<FileNode> nodes) {
    final folders = nodes.where((node) => node.isFolder).toList();
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List<FileNode>.unmodifiable(folders);
  }

  /// 当前目录的文件夹签名：列表新增/删除/改名都会改变它。
  static String _signatureOf(List<FileNode> nodes) {
    final folders =
        nodes.where((node) => node.isFolder).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return folders.map((node) => '${node.id}:${node.name}').join('|');
  }

  /// 列表状态与树缓存的同步：当前目录变化或文件夹集变化时丢缓存重取。
  void _syncWithState() {
    final state = widget.state;
    if (state == null || state.section != FileManagerSection.allFiles) {
      return;
    }
    final parentKey = state.parentId ?? '';
    final signature = _signatureOf(state.files);
    final known = _parentSignatures[parentKey];
    final parentChanged = _lastParentKey != parentKey;
    _lastParentKey = parentKey;
    if (known == signature && !parentChanged) {
      return;
    }
    _parentSignatures[parentKey] = signature;
    if (known == null) {
      // 第一次看到这一层：缓存若存在（之前展开过），按最新列表重取。
      if (_children.containsKey(parentKey)) {
        _scheduleReload(parentKey);
      }
      return;
    }
    if (known != signature) {
      // 文件夹移动会同时改变来源与目标层。刷新树上当前可见的每层，避免
      // 只刷新当前列表所在目录而把另一侧已展开的子树留在旧状态。
      _scheduleReloadVisibleLayers();
    } else if (parentChanged && _children.containsKey(parentKey)) {
      _scheduleReload(parentKey);
    }
  }

  void _scheduleReloadVisibleLayers() {
    final visibleKeys = <String>{'', ..._open};
    for (final key in visibleKeys) {
      _scheduleReload(key);
    }
  }

  /// 树内跨分支移动不会改变当前主列表层级；在移动请求结束后显式重取已展开节点。
  void refreshAfterMove() => _scheduleReloadVisibleLayers();

  void _scheduleReload(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_reload(key));
      }
    });
  }

  void _toggle(FileNode folder) {
    setState(() {
      if (_open.contains(folder.id)) {
        _open.remove(folder.id);
      } else {
        _open.add(folder.id);
        // 展开时重取这一层：目录内容可能在别处被改过（上传/新建/移动）。
        unawaited(_reload(folder.id));
      }
    });
  }

  void _scheduleHoverExpand(FileNode folder) {
    if (_hoverFolderId == folder.id) {
      return;
    }
    _hoverTimer?.cancel();
    setState(() => _hoverFolderId = folder.id);
    _hoverTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _hoverFolderId != folder.id) {
        return;
      }
      setState(() {
        _hoverFolderId = null;
        _open.add(folder.id);
      });
      unawaited(_reload(folder.id));
    });
  }

  void _cancelHoverExpand() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    if (mounted && _hoverFolderId != null) {
      setState(() => _hoverFolderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncWithState();
    final root = _children[''] ?? const <FileNode>[];
    if (_loadedRoot && root.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!_loadedRoot) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final folder in root) ..._buildNode(folder, 1)],
      ),
    );
  }

  List<Widget> _buildNode(FileNode folder, int depth) {
    final skin = DesktopSkin.of(context);
    final children = _children[folder.id];
    final open = _open.contains(folder.id);
    final active = widget.currentId == folder.id;
    final dropping = _hoverFolderId == folder.id;

    Widget row({required bool hovered, required bool dropActive}) {
      return GestureDetector(
        onTap: () {
          _focusNode(folder.id).requestFocus();
          widget.onSection();
          widget.onOpen(folder);
        },
        onDoubleTap: () => _toggle(folder),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: DesktopMotion.of(context, DesktopMotion.fast),
          height: _FilesRailGeometry.nodeHeight,
          padding: EdgeInsets.only(left: 4 + (depth - 1) * 14.0),
          decoration: BoxDecoration(
            color:
                dropActive
                    ? skin.accentWash(0.22)
                    : active
                    ? skin.raise2
                    : hovered
                    ? skin.raise
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border:
                dropActive
                    ? Border.all(
                      color: skin.accent,
                      width: DesktopMetrics.hairlineStrong,
                    )
                    : null,
          ),
          child: Row(
            children: [
              // 样例 `.tw`：20×28 展开钮，展开时 chevron 旋转 90°。
              GestureDetector(
                onTap: () => _toggle(folder),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  key: ValueKey<String>(
                    'desktop-files-tree-chevron-${folder.id}',
                  ),
                  width: 20,
                  height: 28,
                  child: Center(
                    child: AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: DesktopMotion.of(context, DesktopMotion.fast),
                      curve: DesktopMotion.ease,
                      child: Icon(
                        DesktopIcons.chevron,
                        size: 12,
                        color: skin.text3,
                      ),
                    ),
                  ),
                ),
              ),
              Icon(
                DesktopIcons.folder,
                size: _FilesRailGeometry.folderIconSize,
                color: active ? skin.accent : skin.text3,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.navSub(active ? skin.text : skin.text2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildRow({required bool dropActive}) => DesktopHover(
      builder:
          (context, hovered) => row(hovered: hovered, dropActive: dropActive),
    );

    // 拖放目标：悬停延时展开 + 落点高亮 + 接收 id 集。
    Widget rowWithHover = DragTarget<List<String>>(
      onWillAcceptWithDetails:
          (details) =>
              details.data.isNotEmpty && !details.data.contains(folder.id),
      onMove: (_) => _scheduleHoverExpand(folder),
      onLeave: (_) => _cancelHoverExpand(),
      onAcceptWithDetails: (details) async {
        _cancelHoverExpand();
        await widget.onMoveFiles(details.data, folder.id);
      },
      builder:
          (context, candidate, rejected) =>
              buildRow(dropActive: candidate.isNotEmpty || dropping),
    );

    // 键盘：样例 → 展开、← 收起（`Files.tsx` tree-item onKeyDown）。
    // Focus 必须在 DragTarget 外层：DragTarget 的 builder 会重建子行，
    // 把 Focus 放进 builder 里每帧换实例，焦点会在重绘时丢失。
    rowWithHover = Focus(
      focusNode: _focusNode(folder.id),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight && !open) {
          _toggle(folder);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && open) {
          _toggle(folder);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: rowWithHover,
    );

    // 树节点自身可拖：样例 `onDragStart` 用单个目录 id。
    rowWithHover = _AdaptiveFileDraggable(
      data: <String>[folder.id],
      feedback: _RowDragGhost(node: folder, count: 1),
      childWhenDragging: Opacity(opacity: 0.45, child: rowWithHover),
      child: rowWithHover,
    );

    return <Widget>[
      rowWithHover,
      if (open)
        for (final child in children ?? const <FileNode>[])
          ..._buildNode(child, depth + 1),
    ];
  }
}

/// 轨道底部存储用量（样例 `.usage`）：分隔线 + 眉标 + 8px 分段条 + 图例。
class _RailStorageCard extends StatelessWidget {
  const _RailStorageCard({required this.stats});

  final FileStorageStats stats;

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
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.desktopFilesGroupStorage.toUpperCase(),
            style: DesktopType.eyebrow(skin.text3),
          ),
          const SizedBox(height: 10),
          if (segments.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var index = 0; index < segments.length; index++) ...[
                      if (index > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: segments[index].bytes.clamp(1, 0x7fffffff),
                        child: ColoredBox(color: segments[index].color),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            DesktopProgress(fraction: stats.usageRatio),
          const SizedBox(height: 10),
          for (final segment in segments)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: segment.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
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
