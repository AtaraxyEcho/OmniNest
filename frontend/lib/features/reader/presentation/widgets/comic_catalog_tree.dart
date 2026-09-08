import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';

/// 漫画可折叠目录树。
///
/// 隐藏 ROOT 节点，SEASON/VOLUME 可展开折叠，CHAPTER/COLLECTION 可点击。
/// 支持多源区分指示器和当前阅读位置高亮。
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
  final Set<String> _expanded = {};

  /// 多源时是否存在（用于显示来源指示器）。
  bool get _hasMultipleSources =>
      widget.sources != null && widget.sources!.length > 1;

  /// 通过 currentPageId 查找当前所在节点 ID。
  String? get _resolvedCurrentNodeId {
    if (widget.currentNodeId != null) return widget.currentNodeId;
    if (widget.currentPageId == null || widget.pages == null) return null;
    final page =
        widget.pages!.where((p) => p.id == widget.currentPageId).firstOrNull;
    return page?.catalogNodeId;
  }

  /// 构建 sourceId → sourceName 映射。
  Map<String, String> get _sourceNameMap {
    if (widget.sources == null) return const {};
    return {for (final s in widget.sources!) s.id: s.sourceName};
  }

  @override
  void initState() {
    super.initState();
    // 默认展开所有非叶子节点
    for (final node in widget.nodes) {
      if (_hasChildren(node)) {
        _expanded.add(node.id);
      }
    }
    // 自动展开到当前节点的路径
    _expandPathToCurrentNode();
  }

  @override
  void didUpdateWidget(covariant ComicCatalogTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes ||
        oldWidget.currentNodeId != widget.currentNodeId ||
        oldWidget.currentPageId != widget.currentPageId) {
      final validIds = widget.nodes.map((node) => node.id).toSet();
      _expanded.removeWhere((id) => !validIds.contains(id));
      for (final node in widget.nodes) {
        if (_hasChildren(node) &&
            !oldWidget.nodes.any((item) => item.id == node.id)) {
          _expanded.add(node.id);
        }
      }
      _expandPathToCurrentNode();
    }
  }

  /// 展开从根到当前节点的所有祖先。
  void _expandPathToCurrentNode() {
    final currentId = _resolvedCurrentNodeId;
    if (currentId == null) return;
    final nodeMap = {for (final n in widget.nodes) n.id: n};
    String? nodeId = currentId;
    while (nodeId != null) {
      final node = nodeMap[nodeId];
      if (node == null) break;
      if (node.parentId != null) {
        _expanded.add(node.parentId!);
      }
      nodeId = node.parentId;
    }
  }

  List<ComicCatalogNode> get _roots {
    // ROOT 节点的子节点作为顶层
    final root = widget.nodes.where((n) => n.isRoot).firstOrNull;
    if (root == null) {
      // 无 ROOT：直接显示 parentId 为空的节点
      return widget.nodes.where((n) => n.parentId == null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return widget.nodes.where((n) => n.parentId == root.id).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  bool _hasChildren(ComicCatalogNode node) {
    return widget.nodes.any((n) => n.parentId == node.id);
  }

  List<ComicCatalogNode> _childrenOf(ComicCatalogNode node) {
    return widget.nodes.where((n) => n.parentId == node.id).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Widget build(BuildContext context) {
    final roots = _roots;
    if (roots.isEmpty) {
      return const SizedBox.shrink();
    }

    final list = ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: roots.length,
      itemBuilder: (context, index) {
        return _buildNode(roots[index], depth: 0);
      },
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
                onPressed: _expandAll,
                icon: const Icon(Icons.unfold_more_rounded),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).readerComicCollapseAll,
                onPressed: _collapseAll,
                icon: const Icon(Icons.unfold_less_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  void _expandAll() {
    setState(() {
      _expanded
        ..clear()
        ..addAll(widget.nodes.where(_hasChildren).map((node) => node.id));
    });
  }

  void _collapseAll() {
    setState(_expanded.clear);
  }

  Widget _buildNode(ComicCatalogNode node, {required int depth}) {
    final hasKids = _hasChildren(node);
    final isExpanded = _expanded.contains(node.id);
    final isCurrent = node.id == _resolvedCurrentNodeId;
    final isLeaf = !hasKids;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            if (hasKids) {
              setState(() {
                if (isExpanded) {
                  _expanded.remove(node.id);
                } else {
                  _expanded.add(node.id);
                }
              });
            }
            if (isLeaf) {
              widget.onNodeTap(node);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + depth * 24.0,
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
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  )
                else
                  const SizedBox(width: 13),
                // 图标
                Icon(
                  _nodeIcon(node),
                  size: 18,
                  color:
                      isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                // 标题
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
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      // 多源时显示来源指示器
                      if (_hasMultipleSources && node.sourceId != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _buildSourceBadge(node.sourceId!),
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 子节点
        if (hasKids && isExpanded)
          ..._childrenOf(
            node,
          ).map((child) => _buildNode(child, depth: depth + 1)),
      ],
    );
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

  /// 构建来源小标签（显示来源文件名缩写）。
  Widget _buildSourceBadge(String sourceId) {
    final sourceName = _sourceNameMap[sourceId];
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
    if (stripped.length <= 8) return stripped;
    return stripped.substring(stripped.length - 8);
  }
}
