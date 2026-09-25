import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';

/// 扁平化后的目录可见行：节点与其在树中的深度。
class ComicCatalogFlatRow {
  const ComicCatalogFlatRow({required this.node, required this.depth});

  final ComicCatalogNode node;
  final int depth;
}

/// 漫画目录视图状态：展开集合维护 + 可见行扁平化。
///
/// 供盒式列表（[ComicCatalogTree]）与详情页 Sliver 虚拟化列表共用，
/// 保证两种承载方式的展开行为与当前位置解析完全一致。
/// 属纯 UI 展开/派生行状态，按 AGENTS 允许 ChangeNotifier；阅读进度在 application 层。
class ComicCatalogController extends ChangeNotifier {
  ComicCatalogController({
    required List<ComicCatalogNode> nodes,
    List<ComicPage>? pages,
    List<ComicSource>? sources,
    String? currentNodeId,
    String? currentPageId,
  }) {
    _apply(
      nodes: nodes,
      pages: pages,
      sources: sources,
      currentNodeId: currentNodeId,
      currentPageId: currentPageId,
      adoptNewParents: false,
    );
  }

  List<ComicCatalogNode> _nodes = const [];
  List<ComicPage>? _pages;
  List<ComicSource>? _sources;
  String? _currentNodeId;
  String? _currentPageId;
  final Set<String> _expanded = {};
  Set<String> _parentIds = const {};
  Map<String?, List<ComicCatalogNode>> _childrenByParent = const {};
  List<ComicCatalogNode> _roots = const [];
  List<ComicCatalogFlatRow>? _flatRows;

  List<ComicCatalogNode> get nodes => _nodes;

  /// 顶层可见节点（隐藏 ROOT：有 ROOT 时为其子级，否则为无父级节点）。
  List<ComicCatalogNode> get roots => _roots;

  bool get hasMultipleSources => _sources != null && _sources!.length > 1;

  /// 数据变化后的状态调和：清理失效展开项，为新出现的父节点补默认展开，
  /// 并重新展开到当前节点的路径。输入未变化时不触发通知。
  void update({
    required List<ComicCatalogNode> nodes,
    List<ComicPage>? pages,
    List<ComicSource>? sources,
    String? currentNodeId,
    String? currentPageId,
  }) {
    if (identical(_nodes, nodes) &&
        identical(_pages, pages) &&
        identical(_sources, sources) &&
        _currentNodeId == currentNodeId &&
        _currentPageId == currentPageId) {
      return;
    }
    _apply(
      nodes: nodes,
      pages: pages,
      sources: sources,
      currentNodeId: currentNodeId,
      currentPageId: currentPageId,
      adoptNewParents: true,
    );
    notifyListeners();
  }

  void _apply({
    required List<ComicCatalogNode> nodes,
    required List<ComicPage>? pages,
    required List<ComicSource>? sources,
    required String? currentNodeId,
    required String? currentPageId,
    required bool adoptNewParents,
  }) {
    if (adoptNewParents) {
      final validIds = nodes.map((node) => node.id).toSet();
      final newParentIds = {
        for (final node in nodes)
          if (node.parentId != null) node.parentId!,
      };
      _expanded.removeWhere((id) => !validIds.contains(id));
      for (final node in nodes) {
        if (newParentIds.contains(node.id) &&
            !_nodes.any((item) => item.id == node.id)) {
          _expanded.add(node.id);
        }
      }
    } else {
      _expanded.clear();
    }
    _nodes = nodes;
    _pages = pages;
    _sources = sources;
    _currentNodeId = currentNodeId;
    _currentPageId = currentPageId;
    _rebuildIndex();
    if (!adoptNewParents) {
      _expanded.addAll(_parentIds);
    }
    _expandPathToCurrentNode();
    _flatRows = null;
  }

  /// 重建父子索引与顶层节点，供 O(N) 扁平化与 O(1) 父子判断。
  void _rebuildIndex() {
    final parentIds = <String>{};
    final children = <String?, List<ComicCatalogNode>>{};
    for (final node in _nodes) {
      if (node.parentId != null) {
        parentIds.add(node.parentId!);
      }
      children.putIfAbsent(node.parentId, () => []).add(node);
    }
    for (final list in children.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    _parentIds = parentIds;
    _childrenByParent = children;
    final root = _nodes.where((n) => n.isRoot).firstOrNull;
    _roots =
        root == null
            ? List.of(children[null] ?? const [])
            : List.of(children[root.id] ?? const []);
  }

  bool hasChildren(ComicCatalogNode node) => _parentIds.contains(node.id);

  bool isExpanded(String nodeId) => _expanded.contains(nodeId);

  void toggle(String nodeId) {
    if (!_expanded.remove(nodeId)) {
      _expanded.add(nodeId);
    }
    _flatRows = null;
    notifyListeners();
  }

  void expandAll() {
    _expanded
      ..clear()
      ..addAll(_parentIds);
    _flatRows = null;
    notifyListeners();
  }

  void collapseAll() {
    _expanded.clear();
    _flatRows = null;
    notifyListeners();
  }

  /// 通过 currentPageId 查找当前所在节点 ID。
  String? get resolvedCurrentNodeId {
    if (_currentNodeId != null) {
      return _currentNodeId;
    }
    if (_currentPageId == null || _pages == null) {
      return null;
    }
    final page = _pages!.where((p) => p.id == _currentPageId).firstOrNull;
    return page?.catalogNodeId;
  }

  String? sourceNameOf(String sourceId) {
    for (final source in _sources ?? const <ComicSource>[]) {
      if (source.id == sourceId) {
        return source.sourceName;
      }
    }
    return null;
  }

  /// 扁平化当前可见行（结果按展开状态缓存）。
  List<ComicCatalogFlatRow> get flatRows {
    final cached = _flatRows;
    if (cached != null) {
      return cached;
    }
    final rows = <ComicCatalogFlatRow>[];
    void walk(List<ComicCatalogNode> level, int depth) {
      for (final node in level) {
        rows.add(ComicCatalogFlatRow(node: node, depth: depth));
        if (hasChildren(node) && _expanded.contains(node.id)) {
          walk(_childrenByParent[node.id] ?? const [], depth + 1);
        }
      }
    }

    walk(_roots, 0);
    _flatRows = rows;
    return rows;
  }

  /// 展开从根到当前节点的所有祖先。
  void _expandPathToCurrentNode() {
    final currentId = resolvedCurrentNodeId;
    if (currentId == null) {
      return;
    }
    final nodeMap = {for (final n in _nodes) n.id: n};
    String? nodeId = currentId;
    while (nodeId != null) {
      final node = nodeMap[nodeId];
      if (node == null) {
        break;
      }
      if (node.parentId != null) {
        _expanded.add(node.parentId!);
      }
      nodeId = node.parentId;
    }
    _flatRows = null;
  }
}

/// 漫画可折叠目录树。
///
/// 隐藏 ROOT 节点，SEASON/VOLUME 可展开折叠，CHAPTER/COLLECTION 可点击。
/// 支持多源区分指示器和当前阅读位置高亮；列表行扁平化后按需构建。
class ComicCatalogTree extends StatefulWidget {
  const ComicCatalogTree({
    required this.nodes,
    required this.onNodeTap,
    this.currentNodeId,
    this.currentPageId,
    this.pages,
    this.sources,
    this.shrinkWrap = false,
    this.showControls = false,
    super.key,
  });

  final List<ComicCatalogNode> nodes;
  final ValueChanged<ComicCatalogNode> onNodeTap;
  final String? currentNodeId;

  /// 当前页面 ID（用于查找并高亮当前所在节点）。
  final String? currentPageId;

  /// 页面列表（配合 currentPageId 定位当前节点）。
  final List<ComicPage>? pages;

  /// 来源列表（多源时显示来源指示器）。
  final List<ComicSource>? sources;

  final bool shrinkWrap;

  /// 在详情页显示目录展开/收起控制；嵌入导入确认页时保持紧凑布局。
  final bool showControls;

  @override
  State<ComicCatalogTree> createState() => _ComicCatalogTreeState();
}

class _ComicCatalogTreeState extends State<ComicCatalogTree> {
  late ComicCatalogController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ComicCatalogController(
      nodes: widget.nodes,
      pages: widget.pages,
      sources: widget.sources,
      currentNodeId: widget.currentNodeId,
      currentPageId: widget.currentPageId,
    );
  }

  @override
  void didUpdateWidget(covariant ComicCatalogTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.update(
      nodes: widget.nodes,
      pages: widget.pages,
      sources: widget.sources,
      currentNodeId: widget.currentNodeId,
      currentPageId: widget.currentPageId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.roots.isEmpty) {
          return const SizedBox.shrink();
        }
        final list = ListView.builder(
          shrinkWrap: widget.shrinkWrap,
          physics:
              widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _controller.flatRows.length,
          itemBuilder:
              (context, index) => buildComicCatalogRow(
                context,
                row: _controller.flatRows[index],
                controller: _controller,
                onNodeTap: widget.onNodeTap,
              ),
        );
        if (!widget.showControls) {
          return list;
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 4),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context).readerComicCatalogItems(
                      widget.nodes.where((node) => !node.isRoot).length,
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: AppLocalizations.of(context).readerComicExpandAll,
                    onPressed: _controller.expandAll,
                    icon: const Icon(Icons.unfold_more_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip:
                        AppLocalizations.of(context).readerComicCollapseAll,
                    onPressed: _controller.collapseAll,
                    icon: const Icon(Icons.unfold_less_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Expanded(child: list),
          ],
        );
      },
    );
  }
}

/// 构建单行目录条目；盒式列表与 Sliver 虚拟化列表共用同一视觉。
Widget buildComicCatalogRow(
  BuildContext context, {
  required ComicCatalogFlatRow row,
  required ComicCatalogController controller,
  required ValueChanged<ComicCatalogNode> onNodeTap,
}) {
  final node = row.node;
  final hasKids = controller.hasChildren(node);
  final isExpanded = controller.isExpanded(node.id);
  final isCurrent = node.id == controller.resolvedCurrentNodeId;
  final colorScheme = Theme.of(context).colorScheme;

  return InkWell(
    onTap: () {
      if (hasKids) {
        controller.toggle(node.id);
      } else {
        onNodeTap(node);
      }
    },
    child: Padding(
      padding: EdgeInsets.only(
        left: 16.0 + row.depth * 24.0,
        right: 16,
        top: 10,
        bottom: 10,
      ),
      child: Row(
        children: [
          // 当前位置指示器
          if (isCurrent)
            Container(
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            )
          else
            const SizedBox(width: 13),
          Icon(
            _nodeIcon(node),
            size: 18,
            color:
                isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: hasKids ? 15 : 14,
                      fontWeight:
                          hasKids || isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                      color:
                          isCurrent
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                    ),
                  ),
                ),
                // 多源时显示来源指示器
                if (controller.hasMultipleSources && node.sourceId != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _buildSourceBadge(
                      context,
                      controller,
                      node.sourceId!,
                    ),
                  ),
              ],
            ),
          ),
          // 页数
          if (node.pageCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${node.pageCount}',
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          // 展开/折叠箭头
          if (hasKids)
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    ),
  );
}

/// 构建来源小标签（显示来源文件名缩写）。
Widget _buildSourceBadge(
  BuildContext context,
  ComicCatalogController controller,
  String sourceId,
) {
  final sourceName = controller.sourceNameOf(sourceId);
  final label =
      sourceName != null
          ? _abbreviateSourceName(sourceName)
          : sourceId.substring(0, 6);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        // ignore: font_size_whitelist
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 缩写来源文件名（取扩展名前最后 8 个字符）。
String _abbreviateSourceName(String name) {
  final stripped =
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  if (stripped.length <= 8) {
    return stripped;
  }
  return stripped.substring(stripped.length - 8);
}

IconData _nodeIcon(ComicCatalogNode node) {
  return switch (node.nodeType) {
    'ROOT' => Icons.folder_outlined,
    'SEASON' => Icons.calendar_view_month_outlined,
    'VOLUME' => Icons.book_outlined,
    'CHAPTER' => Icons.article_outlined,
    'COLLECTION' => Icons.collections_bookmark_outlined,
    'EXTRA' => Icons.star_outline_rounded,
    _ => Icons.article_outlined,
  };
}
