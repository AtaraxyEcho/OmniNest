part of 'movie_management.dart';

/// 媒体库审阅工作区：展示扫描 run 概览与媒体树，支持勾选候选并入库。
///
/// 媒体树为父子嵌套列表：文件夹节点原地展开并懒加载子节点，叶子节点
/// 直接勾选；不再使用右侧详情面板与面包屑钻取。[treeHeight] 为媒体树
/// 可视区高度，调用方按宿主窗口高度调整；默认值适配电影模块管理面板。
class MediaLibraryReviewWorkspace extends ConsumerStatefulWidget {
  const MediaLibraryReviewWorkspace({
    required this.source,
    this.treeHeight = 460,
    super.key,
  });

  final VideoLibrarySource source;

  /// 媒体树可视区高度；媒体树在该固定高度内滚动。
  final double treeHeight;

  @override
  ConsumerState<MediaLibraryReviewWorkspace> createState() =>
      MediaLibraryReviewWorkspaceState();
}

class MediaLibraryReviewWorkspaceState
    extends ConsumerState<MediaLibraryReviewWorkspace> {
  String? _runId;
  int? _selectionRevision;
  int _page = 0;
  bool _mutating = false;

  @override
  void didUpdateWidget(covariant MediaLibraryReviewWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id != widget.source.id) {
      _runId = null;
      _selectionRevision = null;
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runProvider = latestMediaScanRunProvider(widget.source.id);
    ref.listen(runProvider, (previous, next) {
      final nextRun = next.asData?.value;
      if (nextRun != null && nextRun.id != _runId && mounted) {
        setState(() {
          _runId = nextRun.id;
          _selectionRevision = nextRun.selectionRevision;
          _page = 0;
        });
      } else if (nextRun != null &&
          !_mutating &&
          nextRun.selectionRevision != _selectionRevision &&
          mounted) {
        setState(() => _selectionRevision = nextRun.selectionRevision);
      }
    });
    final runState = ref.watch(runProvider);
    return runState.when(
      loading: () => const _MediaLibraryLoadingSkeleton(),
      error:
          (error, _) => MovieNoticePanel(
            icon: Icons.error_outline_rounded,
            title: l10n.videoLoadTreeFailed,
            message: movieErrorMessage(error),
          ),
      data: (run) => _buildRun(context, l10n, run),
    );
  }

  Widget _buildRun(
    BuildContext context,
    AppLocalizations l10n,
    MediaScanRun? run,
  ) {
    if (run == null) {
      return MovieNoticePanel(
        icon: Icons.manage_search_rounded,
        title: l10n.videoDiscoveryTitle,
        message: l10n.videoDiscoveryEmpty,
      );
    }
    if (run.active) {
      return _MediaLibraryTaskProgress(
        run: run,
        mutating: _mutating,
        onPause: run.status == 'APPLYING' ? () => _pause(run) : null,
        onCancel: () => _cancel(run),
      );
    }
    if (run.status == 'FAILED') {
      return MovieNoticePanel(
        icon: Icons.error_outline_rounded,
        title: l10n.videoDiscoveryTitle,
        message: l10n.videoDiscoveryFailed,
      );
    }
    if (run.status == 'CANCELLED') {
      return MovieNoticePanel(
        icon: Icons.cancel_outlined,
        title: l10n.videoDiscoveryTitle,
        message: l10n.videoDiscoveryCancelled,
      );
    }

    final tree = ref.watch(
      mediaScanTreeProvider((runId: run.id, parentNodeId: null, page: _page)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewSummaryBar(
          run: run,
          mutating: _mutating,
          onSelectAll: run.reviewable ? () => _toggle(run, 'ROOT', true) : null,
          onClear: run.reviewable ? () => _toggle(run, 'ROOT', false) : null,
          onApply:
              run.reviewable && run.selectedCount > 0
                  ? () => _apply(run)
                  : null,
        ),
        const SizedBox(height: 14),
        tree.when(
          loading: () => const LinearProgressIndicator(),
          error:
              (error, _) => MovieNoticePanel(
                icon: Icons.error_outline_rounded,
                title: l10n.videoLoadTreeFailed,
                message: movieErrorMessage(error),
              ),
          data: (page) => _buildTree(context, l10n, run, page),
        ),
      ],
    );
  }

  /// 媒体树容器：固定高度内滚动的父子嵌套列表，根层分页条置于容器下方。
  Widget _buildTree(
    BuildContext context,
    AppLocalizations l10n,
    MediaScanRun run,
    MediaPage<MediaScanTreeNode> page,
  ) {
    final canSelect = run.reviewable && !_mutating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: widget.treeHeight,
          decoration: BoxDecoration(
            color: context.videoColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child:
              page.items.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        l10n.videoNoCandidates,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.videoColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                  : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final node in page.items)
                        _MediaTreeNodeTile(
                          run: run,
                          node: node,
                          level: 0,
                          canSelect: canSelect,
                          onToggle:
                              (node, selected) =>
                                  _toggle(run, node.nodeId, selected),
                        ),
                    ],
                  ),
        ),
        if (page.totalPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: page.page > 0 ? () => setState(() => _page--) : null,
                tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${page.page + 1} / ${page.totalPages}'),
              IconButton(
                onPressed:
                    page.page + 1 < page.totalPages
                        ? () => setState(() => _page++)
                        : null,
                tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _toggle(MediaScanRun run, String nodeId, bool selected) async {
    setState(() => _mutating = true);
    try {
      final summary = await ref
          .read(videoLibrarySourceActionsProvider)
          .updateSelection(
            run: run,
            nodeId: nodeId,
            selected: selected,
            expectedRevision: _selectionRevision,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectionRevision = summary.revision;
      });
      // 勾选会影响任意已展开层级的聚合状态，整体失效以刷新嵌套树。
      ref.invalidate(mediaScanTreeProvider);
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _apply(MediaScanRun run) async {
    setState(() => _mutating = true);
    try {
      final task = await ref
          .read(videoLibrarySourceActionsProvider)
          .apply(run, expectedRevision: _selectionRevision);
      if (mounted) {
        showMovieFeedback(context, task.message);
      }
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _pause(MediaScanRun run) async {
    setState(() => _mutating = true);
    try {
      await ref.read(videoLibrarySourceActionsProvider).pause(run);
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _cancel(MediaScanRun run) async {
    setState(() => _mutating = true);
    try {
      await ref.read(videoLibrarySourceActionsProvider).cancel(run);
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }
}

class _ReviewSummaryBar extends StatelessWidget {
  const _ReviewSummaryBar({
    required this.run,
    required this.mutating,
    required this.onSelectAll,
    required this.onClear,
    required this.onApply,
  });

  final MediaScanRun run;
  final bool mutating;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClear;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final applyButton = FilledButton.icon(
      onPressed: mutating ? null : onApply,
      icon:
          mutating
              ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.library_add_outlined),
      label: Text(l10n.videoAddSelectedToLibrary),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.videoDiscoveryTitle,
                    style: TextStyle(
                      color: context.videoColors.onSurface,
                      fontSize: AppTypography.titleMedium,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.videoReviewSelectionHint,
                    style: TextStyle(
                      color: context.videoColors.onSurfaceVariant,
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 12), applyButton],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  applyButton,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _ReviewMetric(
                icon: Icons.inventory_2_outlined,
                label: l10n.videoDiscoveryCandidates(run.candidateCount),
              ),
              _ReviewMetric(
                icon: Icons.check_circle_outline_rounded,
                label: l10n.videoDiscoverySelected(run.selectedCount),
                emphasized: run.selectedCount > 0,
              ),
              _ReviewMetric(
                icon: Icons.report_problem_outlined,
                label: l10n.videoDiscoveryIssues(
                  run.conflictCount + run.unmatchedCount,
                ),
                issue: run.conflictCount + run.unmatchedCount > 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: mutating ? null : onSelectAll,
                icon: const Icon(Icons.select_all_rounded),
                label: Text(l10n.videoSelectAllCandidates),
              ),
              TextButton.icon(
                onPressed: mutating ? null : onClear,
                icon: const Icon(Icons.deselect_rounded),
                label: Text(l10n.videoClearCandidateSelection),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({
    required this.icon,
    required this.label,
    this.emphasized = false,
    this.issue = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;
  final bool issue;

  @override
  Widget build(BuildContext context) {
    final color =
        issue
            ? Theme.of(context).colorScheme.error
            : emphasized
            ? context.videoColors.primary
            : context.videoColors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 媒体树父子嵌套节点：文件夹节点原地展开并按页懒加载子节点，勾选走
/// 后端聚合选择接口；叶子节点展示匹配状态徽标。缩进在五层后封顶。
class _MediaTreeNodeTile extends ConsumerStatefulWidget {
  const _MediaTreeNodeTile({
    required this.run,
    required this.node,
    required this.level,
    required this.canSelect,
    required this.onToggle,
  });

  final MediaScanRun run;
  final MediaScanTreeNode node;
  final int level;
  final bool canSelect;
  final void Function(MediaScanTreeNode node, bool selected) onToggle;

  @override
  ConsumerState<_MediaTreeNodeTile> createState() => _MediaTreeNodeTileState();
}

class _MediaTreeNodeTileState extends ConsumerState<_MediaTreeNodeTile> {
  static const _indentStep = 18.0;
  static const _maxIndent = 90.0;

  bool _expanded = false;
  int _childPage = 0;

  double get _indent {
    final raw = widget.level * _indentStep;
    return raw > _maxIndent ? _maxIndent : raw;
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      _childPage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.videoColors;
    final node = widget.node;
    final selected = node.selectionState == 'ALL';
    final partial = node.selectionState == 'PARTIAL';
    final childAsync =
        _expanded
            ? ref.watch(
              mediaScanTreeProvider((
                runId: widget.run.id,
                parentNodeId: node.nodeId,
                page: _childPage,
              )),
            )
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: node.hasChildren ? _toggleExpanded : null,
          child: Container(
            padding: EdgeInsetsDirectional.fromSTEB(_indent + 8, 4, 10, 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child:
                      node.hasChildren
                          ? AnimatedRotation(
                            turns: _expanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                          )
                          : null,
                ),
                Checkbox(
                  tristate: true,
                  value: partial ? null : selected,
                  onChanged:
                      widget.canSelect
                          ? (value) => widget.onToggle(node, value ?? !selected)
                          : null,
                ),
                const SizedBox(width: 4),
                Icon(
                  _mediaTreeNodeIcon(node.nodeType),
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (node.hasChildren) ...[
                  const SizedBox(width: 8),
                  Text(
                    l10n.videoDiscoveryCandidates(node.candidateCount),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                ],
                if (!node.hasChildren || node.issueCount > 0) ...[
                  const SizedBox(width: 8),
                  _CandidateStatusBadge(status: node.matchStatus),
                ],
              ],
            ),
          ),
        ),
        if (_expanded)
          childAsync!.when(
            loading:
                () => Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    _indent + 40,
                    10,
                    16,
                    10,
                  ),
                  child: const LinearProgressIndicator(minHeight: 2),
                ),
            error:
                (error, _) => Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    _indent + 40,
                    8,
                    16,
                    8,
                  ),
                  child: Text(
                    l10n.videoLoadTreeFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                ),
            data:
                (page) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in page.items)
                      _MediaTreeNodeTile(
                        run: widget.run,
                        node: child,
                        level: widget.level + 1,
                        canSelect: widget.canSelect,
                        onToggle: widget.onToggle,
                      ),
                    if (page.totalPages > 1)
                      Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          _indent + 40,
                          2,
                          12,
                          2,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed:
                                  page.page > 0
                                      ? () => setState(() => _childPage--)
                                      : null,
                              tooltip:
                                  MaterialLocalizations.of(
                                    context,
                                  ).previousPageTooltip,
                              iconSize: 18,
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Text(
                              '${page.page + 1} / ${page.totalPages}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            IconButton(
                              onPressed:
                                  page.page + 1 < page.totalPages
                                      ? () => setState(() => _childPage++)
                                      : null,
                              tooltip:
                                  MaterialLocalizations.of(
                                    context,
                                  ).nextPageTooltip,
                              iconSize: 18,
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
          ),
      ],
    );
  }
}
