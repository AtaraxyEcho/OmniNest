part of 'desktop_files_page.dart';

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
  final void Function(FileNode folder, List<FileNode> breadcrumbs) onOpen;
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
  String? _lastSpaceType;

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
      final controller = ref.read(fileBrowserControllerProvider.notifier);
      final nodes = await controller.listFolderOptions(
        key.isEmpty ? null : key,
        shared: widget.state?.spaceType == 'SHARED',
      );
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
    if (_lastSpaceType != state.spaceType) {
      _lastSpaceType = state.spaceType;
      _children.clear();
      _parentSignatures.clear();
      _open.clear();
      _loadedRoot = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load(null));
      });
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

  List<Widget> _buildNode(
    FileNode folder,
    int depth, [
    List<FileNode> path = const <FileNode>[],
  ]) {
    final skin = DesktopSkin.of(context);
    final children = _children[folder.id];
    final open = _open.contains(folder.id);
    final active = widget.currentId == folder.id;
    final dropping = _hoverFolderId == folder.id;

    Widget row({required bool hovered, required bool dropActive}) {
      return GestureDetector(
        onTap: () {
          _focusNode(folder.id).requestFocus();
          if (widget.state?.section != FileManagerSection.allFiles) {
            widget.onSection();
          }
          widget.onOpen(folder, [...path, folder]);
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
          ..._buildNode(child, depth + 1, [...path, folder]),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: skin.raise2)),
                    FractionallySizedBox(
                      widthFactor: stats.usageRatio,
                      child: ColoredBox(color: skin.accent),
                    ),
                  ],
                ),
              ),
            ),
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

/// 共享空间没有按文件类型拆分的后端统计；显示真实配额进度，避免用原型演示
/// 的类别数字伪造生产数据，同时保留样例底部用量条的层级和尺寸。
class _RailSharedStorageCard extends StatelessWidget {
  const _RailSharedStorageCard({required this.usage});

  final SharedSpaceUsage usage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final capacity =
        usage.isUnlimited
            ? l10n.filesSharedSpaceUnlimited
            : formatFileSize(usage.maxBytes);
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: skin.raise2)),
                  FractionallySizedBox(
                    widthFactor: usage.usageRatio,
                    child: ColoredBox(color: skin.accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.filesSharedSpaceInfo(
              formatFileSize(usage.usedBytes),
              capacity,
              usage.fileCount,
            ),
            style: DesktopType.caption(skin.text2),
          ),
        ],
      ),
    );
  }
}
