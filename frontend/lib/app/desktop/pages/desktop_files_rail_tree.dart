part of 'desktop_files_page.dart';

/// 文件夹树：根级一次拉取，展开时才拉子级；展平后虚拟化渲染并内置树顶工具条。
class _FolderTree extends ConsumerStatefulWidget {
  const _FolderTree({
    super.key,
    required this.state,
    required this.currentId,
    required this.onOpen,
    required this.onSection,
    required this.onMoveFiles,
    this.onNewFolder,
    this.leadingItems = const <Widget>[],
    this.trailingItems = const <Widget>[],
  });

  final FileBrowserState? state;
  final String? currentId;
  final void Function(FileNode folder, List<FileNode> breadcrumbs) onOpen;
  final VoidCallback onSection;
  final Future<void> Function(List<String> ids, String targetParentId)
  onMoveFiles;
  final VoidCallback? onNewFolder;
  final List<Widget> leadingItems;
  final List<Widget> trailingItems;

  @override
  ConsumerState<_FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends ConsumerState<_FolderTree> {
  static const double _maxIndent = 72.0;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _filterController = TextEditingController();
  final Map<String, List<FileNode>> _children = <String, List<FileNode>>{};
  final Set<String> _open = <String>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  final Map<String, String> _parentSignatures = <String, String>{};
  final Map<String, int> _fetchGenerations = <String, int>{};
  bool _loadedRoot = false;
  bool _filterExpanded = false;
  String _filterQuery = '';
  String? _lastParentKey;
  String? _lastSpaceType;

  /// 内部拖拽悬停 650ms 后展开目标目录（样例 `expandOnHover`）。
  Timer? _hoverTimer;
  String? _hoverFolderId;

  @override
  void initState() {
    super.initState();
    if (widget.state != null) {
      _syncWithState();
    }
  }

  @override
  void didUpdateWidget(covariant _FolderTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != null && !identical(oldWidget.state, widget.state)) {
      _syncWithState();
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _scrollController.dispose();
    _filterController.dispose();
    _disposeAllFocusNodes();
    super.dispose();
  }

  FocusNode _focusNode(String id) => _focusNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'files-tree-$id'),
  );

  void _disposeAllFocusNodes() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
  }

  void _pruneFocusNodes(Set<String> keepIds) {
    final staleIds =
        _focusNodes.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in staleIds) {
      _focusNodes.remove(id)?.dispose();
    }
  }

  Future<void> _load(String? parentId) async {
    if (widget.state == null) {
      return;
    }
    final key = parentId ?? '';
    if (_children.containsKey(key)) {
      return;
    }
    await _fetch(key);
  }

  /// 绕过缓存重取一层；目录改动后调用。
  Future<void> _reload(String key) async {
    if (!mounted || widget.state == null) {
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
        onlyFolders: true,
      );
      if (!mounted || _fetchGenerations[key] != generation) {
        return;
      }
      final nextFolders = _sortedFolders(nodes);
      final nextSig = _signatureOf(nextFolders);
      final prevFolders = _children[key];
      final prevSig = prevFolders == null ? null : _signatureOf(prevFolders);
      if (prevSig == nextSig && _loadedRoot) {
        return;
      }
      setState(() {
        _children[key] = nextFolders;
        _loadedRoot = true;
      });
    } on Object {
      if (mounted && _fetchGenerations[key] == generation && !_loadedRoot) {
        setState(() => _loadedRoot = true);
      }
    }
  }

  static List<FileNode> _sortedFolders(List<FileNode> nodes) {
    final folders = nodes.where((node) => node.isFolder).toList();
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List<FileNode>.unmodifiable(folders);
  }

  static String _signatureOf(List<FileNode> nodes) {
    final folders =
        nodes.where((node) => node.isFolder).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return folders.map((node) => '${node.id}:${node.name}').join('|');
  }

  /// 阶梯收敛缩进：前 5 层每层 12px，第 6 层起每层 4px，总缩进钳制在 72px。
  static double _indentForDepth(int depth) {
    final level = math.max(0, depth - 1);
    final stepped = math.min(level, 5) * 12.0 + math.max(0, level - 5) * 4.0;
    return math.min(stepped, _maxIndent);
  }

  void _syncWithState() {
    final state = widget.state;
    if (state == null) {
      return;
    }

    if (_lastSpaceType == null) {
      _lastSpaceType = state.spaceType;
      if (state.section == FileManagerSection.allFiles) {
        final parentKey = state.parentId ?? '';
        final signature = _signatureOf(state.files);
        _lastParentKey = parentKey;
        _parentSignatures[parentKey] = signature;
        if (parentKey.isEmpty) {
          _children[''] = _sortedFolders(state.files);
          _loadedRoot = true;
          if (state.fileTotalElements > state.files.length) {
            _scheduleReload('');
          }
          return;
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load(null));
      });
      return;
    }

    if (state.section != FileManagerSection.allFiles) {
      if (!_loadedRoot) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_load(null));
        });
      }
      return;
    }

    if (_lastSpaceType != state.spaceType) {
      _lastSpaceType = state.spaceType;
      _children.clear();
      _parentSignatures.clear();
      _open.clear();
      _disposeAllFocusNodes();
      _filterQuery = '';
      _filterExpanded = false;
      _filterController.clear();
      _lastParentKey = state.parentId ?? '';
      final parentKey = state.parentId ?? '';
      if (parentKey.isEmpty) {
        final signature = _signatureOf(state.files);
        _parentSignatures[''] = signature;
        _children[''] = _sortedFolders(state.files);
        _loadedRoot = true;
        if (state.fileTotalElements > state.files.length) {
          _scheduleReload('');
        }
      } else {
        _loadedRoot = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_load(null));
        });
      }
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
      if (_children.containsKey(parentKey)) {
        _scheduleReload(parentKey);
      }
      return;
    }
    if (known != signature) {
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
        final keepIds =
            _flattenVisibleNodes().map((node) => node.folder.id).toSet();
        _pruneFocusNodes(keepIds);
      } else {
        _open.add(folder.id);
        unawaited(_reload(folder.id));
      }
    });
  }

  void _collapseAll() {
    if (_open.isEmpty) {
      return;
    }
    setState(() {
      _open.clear();
      final rootIds =
          (_children[''] ?? const <FileNode>[]).map((node) => node.id).toSet();
      _pruneFocusNodes(rootIds);
    });
  }

  Future<void> _revealActiveFolder() async {
    final state = widget.state;
    final activeId = widget.currentId;
    if (state == null || activeId == null) {
      return;
    }
    final crumbs =
        state.spaceType == 'SHARED'
            ? state.sharedSpaceBreadcrumbs
            : state.breadcrumbs;
    final ancestorIds = <String>[
      for (final node in crumbs)
        if (node.id != activeId) node.id,
    ];
    setState(() {
      if (_filterQuery.isNotEmpty) {
        _filterQuery = '';
        _filterController.clear();
      }
      _open.addAll(ancestorIds);
    });
    if (!_children.containsKey('')) {
      await _load(null);
    }
    for (final id in ancestorIds) {
      if (!mounted) return;
      if (!_children.containsKey(id)) {
        await _load(id);
      }
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final nodes = _flattenVisibleNodes();
      final index = nodes.indexWhere((node) => node.folder.id == activeId);
      if (index < 0) return;
      final target = (index * _FilesRailGeometry.nodeHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      unawaited(
        _scrollController.animateTo(
          target,
          duration: DesktopMotion.of(context, DesktopMotion.soft),
          curve: DesktopMotion.ease,
        ),
      );
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

  /// 将可见树节点展平为线性列表，支持目录快速过滤。
  List<_VisibleTreeNode> _flattenVisibleNodes() {
    final root = _children[''] ?? const <FileNode>[];
    final query = _filterQuery.trim().toLowerCase();
    final result = <_VisibleTreeNode>[];

    bool collect(FileNode folder, int depth, List<FileNode> path) {
      final children = _children[folder.id] ?? const <FileNode>[];
      if (query.isEmpty) {
        result.add(_VisibleTreeNode(folder: folder, depth: depth, path: path));
        if (_open.contains(folder.id)) {
          final nextPath = [...path, folder];
          for (final child in children) {
            collect(child, depth + 1, nextPath);
          }
        }
        return true;
      }
      final selfMatches = folder.name.toLowerCase().contains(query);
      final childStart = result.length;
      final nextPath = [...path, folder];
      var descendantMatches = false;
      for (final child in children) {
        if (collect(child, depth + 1, nextPath)) {
          descendantMatches = true;
        }
      }
      if (selfMatches || descendantMatches) {
        result.insert(
          childStart,
          _VisibleTreeNode(folder: folder, depth: depth, path: path),
        );
        return true;
      }
      return false;
    }

    for (final folder in root) {
      collect(folder, 1, const <FileNode>[]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final root = _children[''] ?? const <FileNode>[];
    final visibleNodes =
        _loadedRoot ? _flattenVisibleNodes() : const <_VisibleTreeNode>[];
    final shared = widget.state?.spaceType == 'SHARED';
    final showToolbar = _loadedRoot && root.isNotEmpty;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (widget.leadingItems.isNotEmpty)
          SliverList(delegate: SliverChildListDelegate(widget.leadingItems)),
        if (showToolbar) SliverToBoxAdapter(child: _buildToolbar(context)),
        if (!_loadedRoot)
          const SliverToBoxAdapter(child: SizedBox(height: 4))
        else if (root.isEmpty)
          SliverToBoxAdapter(
            child:
                shared
                    ? _buildSharedEmptyGuide(context)
                    : const SizedBox.shrink(),
          )
        else if (visibleNodes.isEmpty)
          SliverToBoxAdapter(child: _buildFilterEmptyHint(context))
        else
          SliverFixedExtentList.builder(
            itemExtent: _FilesRailGeometry.nodeHeight,
            itemCount: visibleNodes.length,
            itemBuilder:
                (context, index) => _buildVisibleRow(visibleNodes[index]),
          ),
        if (widget.trailingItems.isNotEmpty)
          SliverList(delegate: SliverChildListDelegate(widget.trailingItems)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final hasActive = widget.currentId != null;
    final hasOpen = _open.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              _TreeMiniAction(
                icon: DesktopIcons.filter,
                tooltip: isZh ? '筛选目录' : 'Filter folders',
                active: _filterExpanded || _filterQuery.isNotEmpty,
                onTap: () {
                  setState(() {
                    _filterExpanded = !_filterExpanded;
                    if (!_filterExpanded && _filterQuery.isNotEmpty) {
                      _filterQuery = '';
                      _filterController.clear();
                    }
                  });
                },
              ),
              _TreeMiniAction(
                icon: DesktopIcons.pin,
                tooltip: isZh ? '定位当前目录' : 'Reveal active folder',
                enabled: hasActive,
                onTap: () => unawaited(_revealActiveFolder()),
              ),
              _TreeMiniAction(
                icon: DesktopIcons.chevUp,
                tooltip: isZh ? '全部折叠' : 'Collapse all',
                enabled: hasOpen,
                onTap: _collapseAll,
              ),
            ],
          ),
          if (_filterExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: skin.raise,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: skin.line),
                ),
                child: Row(
                  children: [
                    Icon(DesktopIcons.search, size: 13, color: skin.text3),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _filterController,
                        onChanged:
                            (value) => setState(() => _filterQuery = value),
                        style: DesktopType.caption(skin.text),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: isZh ? '过滤已加载目录…' : 'Filter folders…',
                          hintStyle: DesktopType.caption(skin.text3),
                        ),
                      ),
                    ),
                    if (_filterQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _filterController.clear();
                          setState(() => _filterQuery = '');
                        },
                        child: Icon(
                          DesktopIcons.close,
                          size: 13,
                          color: skin.text3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSharedEmptyGuide(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: skin.raise,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: skin.line),
        ),
        child: Row(
          children: [
            Icon(DesktopIcons.folder, size: 14, color: skin.text3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isZh ? '暂无子文件夹' : 'No subfolders yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.caption(skin.text3),
              ),
            ),
            if (widget.onNewFolder != null)
              DesktopHover(
                builder:
                    (context, hovered) => GestureDetector(
                      onTap: widget.onNewFolder,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color:
                              hovered
                                  ? skin.accentWash(0.18)
                                  : skin.accentWash(0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isZh ? '新建文件夹' : 'New folder',
                          style: DesktopType.nano(skin.accent),
                        ),
                      ),
                    ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterEmptyHint(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Text(
        isZh ? '未找到匹配目录' : 'No matching folders',
        style: DesktopType.caption(skin.text3),
      ),
    );
  }

  Widget _buildVisibleRow(_VisibleTreeNode item) {
    final skin = DesktopSkin.of(context);
    final folder = item.folder;
    final depth = item.depth;
    final path = item.path;
    final open = _open.contains(folder.id);
    final active = widget.currentId == folder.id;
    final dropping = _hoverFolderId == folder.id;
    final indent = _indentForDepth(depth);
    final guideOffsets = <double>[
      for (var d = 1; d < depth; d++) 4 + _indentForDepth(d) + 10,
    ];

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
          child: Stack(
            children: [
              for (final x in guideOffsets.toSet())
                Positioned(
                  left: x,
                  top: 3,
                  bottom: 3,
                  width: 1,
                  child: ColoredBox(color: skin.line.withValues(alpha: 0.7)),
                ),
              Padding(
                padding: EdgeInsets.only(left: 4 + indent, right: 6),
                child: Row(
                  children: [
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
                            duration: DesktopMotion.of(
                              context,
                              DesktopMotion.fast,
                            ),
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
                      child: Tooltip(
                        message: folder.name,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.navSub(
                            active ? skin.text : skin.text2,
                          ),
                        ),
                      ),
                    ),
                  ],
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

    return KeyedSubtree(
      key: ValueKey<String>('files-tree-node-${folder.id}'),
      child: _AdaptiveFileDraggable(
        data: <String>[folder.id],
        feedback: _RowDragGhost(node: folder, count: 1),
        childWhenDragging: Opacity(
          opacity: 0.45,
          alwaysIncludeSemantics: true,
          child: rowWithHover,
        ),
        child: rowWithHover,
      ),
    );
  }
}
