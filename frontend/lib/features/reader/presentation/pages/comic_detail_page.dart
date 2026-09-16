import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_catalog_tree.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_source_tile.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 漫画详情页 — 与文本详情页同构的 Hero + 页签布局。
///
/// Hero 行承载封面、标题、导入/阅读状态与核心动作；页签承载基本信息、
/// 目录树与来源管理。滚动由外层详情页骨架承担，本页输出无滚动体的 Column。
class ComicDetailPage extends ConsumerStatefulWidget {
  const ComicDetailPage({
    required this.item,
    this.chapters = const [],
    this.pages = const [],
    this.sources = const [],
    this.progress,
    this.onRetrySource,
    this.onDeleteSource,
    this.canRead = true,
    this.parseProgress,
    this.onEditMetadata,
    this.onDelete,
    super.key,
  });

  /// 漫画条目数据。
  final ReaderItem item;

  /// 目录节点列表（来自 ComicManifest.catalog）。
  final List<ComicCatalogNode> chapters;

  /// 页面列表（配合阅读进度高亮当前目录节点）。
  final List<ComicPage> pages;

  /// 来源文件列表（用于展示多源解析状态）。
  final List<ComicSource> sources;

  /// 服务端阅读进度（进度展示与当前页定位）。
  final ReaderProgress? progress;

  /// 重试失败来源。
  final Future<bool> Function(ComicSource source)? onRetrySource;

  /// 删除来源。
  final Future<bool> Function(ComicSource source)? onDeleteSource;

  /// 清单至少包含一个可读页面时允许进入阅读器。
  final bool canRead;

  /// 后台解析任务进度（0-100）。
  final int? parseProgress;

  /// 打开元数据编辑页。
  final VoidCallback? onEditMetadata;

  /// 确认删除后由宿主执行删除与跳转。
  final VoidCallback? onDelete;

  @override
  ConsumerState<ComicDetailPage> createState() => _ComicDetailPageState();
}

enum _ComicDetailTab { info, catalog, sources }

class _ComicDetailPageState extends ConsumerState<ComicDetailPage> {
  bool _bookshelfBusy = false;
  _ComicDetailTab _tab = _ComicDetailTab.info;
  ComicCatalogController? _catalogController;

  @override
  void initState() {
    super.initState();
    _syncCatalogController();
  }

  @override
  void didUpdateWidget(covariant ComicDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCatalogController();
  }

  @override
  void dispose() {
    _catalogController?.removeListener(_onCatalogChanged);
    _catalogController?.dispose();
    super.dispose();
  }

  /// 创建或调和目录控制器；数据未变化时内部去重，避免重建循环。
  void _syncCatalogController() {
    final existing = _catalogController;
    if (existing == null) {
      _catalogController = ComicCatalogController(
        nodes: widget.chapters,
        pages: widget.pages,
        currentNodeId: null,
        currentPageId: widget.progress?.pageId,
      )..addListener(_onCatalogChanged);
      return;
    }
    existing.update(
      nodes: widget.chapters,
      pages: widget.pages,
      currentNodeId: null,
      currentPageId: widget.progress?.pageId,
    );
  }

  void _onCatalogChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = _visibleTabs(l10n);
    // 来源删除等操作后当前页签可能已不可见，回退到基本信息页签。
    final selectedTab = tabs.containsKey(_tab) ? _tab : _ComicDetailTab.info;
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final pagePadding = EdgeInsets.fromLTRB(
      wide ? 32 : 24,
      24,
      wide ? 32 : 24,
      0,
    );
    // 页面自带滚动体：Hero/页签与短内容为盒式 sliver，目录页签走
    // SliverList 虚拟化，千章级目录帧成本恒定于可见区域。
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: pagePadding,
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(context),
                const SizedBox(height: 32),
                if (tabs.length > 1) ...[
                  _buildTabBar(context, tabs, selectedTab),
                  const SizedBox(height: 24),
                ],
                if (selectedTab != _ComicDetailTab.catalog)
                  _buildTabContent(context, selectedTab),
              ],
            ),
          ),
        ),
        if (selectedTab == _ComicDetailTab.catalog)
          ..._buildCatalogSlivers(context),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  /// 当前可见页签：目录与来源在无数据时隐藏。
  Map<_ComicDetailTab, String> _visibleTabs(AppLocalizations l10n) {
    return {
      _ComicDetailTab.info: l10n.readerDetailInfo,
      if (widget.chapters.isNotEmpty)
        _ComicDetailTab.catalog: l10n.readerTableOfContents,
      if (widget.sources.isNotEmpty)
        _ComicDetailTab.sources: l10n.readerComicSources,
    };
  }

  Widget _buildHero(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 144,
          height: 216,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: ReaderBookCover(item: item, size: ReaderCoverSize.large),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                readerTypeLabel(l10n, item.itemType),
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  // ignore: font_size_whitelist
                  fontSize: 10,
                  height: 1.2,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: TextStyle(
                  color: rc.onSurface,
                  fontSize: AppTypography.headlineMedium,
                  height: 1.25,
                  fontFamily: kReaderSerifFamily,
                ),
              ),
              if (item.authorName?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  item.authorName!,
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // 状态区文字与按钮同样钳制缩放：常规字号下与书籍详情页
              // 渲染一致，大字号下不膨胀，避免窄幅信息列横向溢出。
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: _buildStatusArea(context),
              ),
              const SizedBox(height: 20),
              _buildActionRow(context),
            ],
          ),
        ),
      ],
    );
  }

  /// 状态区：解析中/导入异常时展示导入状态，否则展示阅读进度细条。
  Widget _buildStatusArea(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    if (item.isParsing) {
      final parseProgress = widget.parseProgress;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusRow(
            context,
            icon: Icons.hourglass_top_rounded,
            message: l10n.readerComicParsingMessage,
            color: rc.tertiary,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            minHeight: 2,
            value:
                parseProgress == null
                    ? null
                    : parseProgress.clamp(0, 100) / 100,
            backgroundColor: rc.outlineVariant,
            color: rc.tertiary,
          ),
        ],
      );
    }
    if (item.isPartialFailed) {
      return _statusRow(
        context,
        icon: Icons.warning_amber_rounded,
        message: l10n.readerComicPartialFailedMessage,
        color: rc.warning,
      );
    }
    if (item.isFailed) {
      return _statusRow(
        context,
        icon: Icons.error_outline_rounded,
        message: l10n.readerComicFailedMessage,
        color: rc.danger,
      );
    }
    final percent =
        ((widget.progress?.progressPercent ?? item.progressPercent) ?? 0).clamp(
          0.0,
          1.0,
        );
    final complete = percent >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.readerDetailProgress,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
                height: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              complete
                  ? l10n.readerDetailComplete
                  : '${(percent * 100).round()}%',
              style: TextStyle(
                color: complete ? rc.reading : rc.onSurface,
                fontSize: AppTypography.bodySmall,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 2,
          color: rc.outlineVariant,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: percent,
            child: Container(height: 2, color: rc.reading),
          ),
        ),
      ],
    );
  }

  Widget _statusRow(
    BuildContext context, {
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: color,
              fontSize: AppTypography.bodySmall,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final hasProgress =
        (widget.progress?.progressPercent ?? item.progressPercent ?? 0) > 0;
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 按钮文字缩放钳制在 1.2 内：常规字号下与书籍详情页逐像素一致，
        // 大字号下按钮不再随系统缩放膨胀，避免窄幅信息列横向溢出。
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: FilledButton.icon(
            onPressed:
                widget.canRead
                    ? () => context.push('/reader/comics/${item.id}/read')
                    : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(
              hasProgress
                  ? l10n.readerContinueReading
                  : l10n.readerStartReading,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: rc.primary,
              foregroundColor: rc.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: OutlinedButton.icon(
            onPressed: _bookshelfBusy ? null : _toggleBookshelf,
            icon: Icon(
              item.addedToBookshelf
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_add_rounded,
              size: 18,
              color: item.addedToBookshelf ? rc.onSurface : rc.onSurfaceVariant,
            ),
            label: Text(
              item.addedToBookshelf
                  ? l10n.readerAddedToBookshelf
                  : l10n.readerAddToBookshelf,
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: item.addedToBookshelf ? rc.onSurface : rc.outlineVariant,
              ),
              foregroundColor:
                  item.addedToBookshelf ? rc.onSurface : rc.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (widget.onEditMetadata != null || widget.onDelete != null)
          PopupMenuButton<String>(
            tooltip: l10n.coreMore,
            icon: Icon(Icons.more_horiz_rounded, color: rc.onSurfaceVariant),
            onSelected: (value) {
              if (value == 'metadata') widget.onEditMetadata?.call();
              if (value == 'delete') _confirmDelete(context);
            },
            itemBuilder:
                (context) => [
                  if (widget.onEditMetadata != null)
                    PopupMenuItem(
                      value: 'metadata',
                      child: Text(l10n.readerDetailEditMeta),
                    ),
                  if (widget.onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        l10n.readerDeleteBook,
                        style: TextStyle(color: rc.danger),
                      ),
                    ),
                ],
          ),
      ],
    );
  }

  /// 切换书架状态。
  Future<void> _toggleBookshelf() async {
    setState(() => _bookshelfBusy = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(widget.item.id);
      if (mounted) {
        ref.invalidate(readerCenterControllerProvider);
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(
          context,
          widget.item.addedToBookshelf
              ? l10n.readerRemovedFromBookshelf
              : l10n.readerAddedToBookshelf,
        );
      }
    } on Exception {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerOperationFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _bookshelfBusy = false);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.readerConfirmDelete),
            content: Text(l10n.readerConfirmDeleteMsg(widget.item.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.readerColors.danger,
                ),
                child: Text(l10n.filesDelete),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      widget.onDelete?.call();
    }
  }

  Widget _buildTabBar(
    BuildContext context,
    Map<_ComicDetailTab, String> tabs,
    _ComicDetailTab selectedTab,
  ) {
    final rc = context.readerColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: rc.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in tabs.entries)
              InkWell(
                onTap: () => setState(() => _tab = entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            selectedTab == entry.key
                                ? rc.onSurface
                                : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      height: 1.2,
                      fontWeight:
                          selectedTab == entry.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                      color:
                          selectedTab == entry.key
                              ? rc.onSurface
                              : rc.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, _ComicDetailTab tab) {
    switch (tab) {
      case _ComicDetailTab.info:
        return _buildInfoTab(context);
      case _ComicDetailTab.catalog:
        // 目录页签由外层 slivers 承载，不进入盒式内容。
        return const SizedBox.shrink();
      case _ComicDetailTab.sources:
        return _buildSourcesTab(context);
    }
  }

  Widget _buildInfoTab(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final lastReadAt = widget.progress?.updatedAt ?? item.updatedAt;
    final rows = <(String, String)>[
      (l10n.readerDetailType, readerTypeLabel(l10n, item.itemType)),
      if (item.language?.isNotEmpty == true)
        (l10n.readerDetailLanguage, item.language!.toUpperCase()),
      if (item.publisher?.isNotEmpty == true)
        (l10n.readerLabelPublisher, item.publisher!),
      if (item.serialStatus?.isNotEmpty == true)
        (l10n.readerLabelSerialStatus, item.serialStatus!),
      if (item.rating != null && item.rating! > 0)
        (l10n.readerLabelRating, item.rating!.toStringAsFixed(1)),
      if (item.releaseDate != null)
        (l10n.readerLabelReleaseDate, _formatDate(item.releaseDate!)),
      if (item.createdAt != null)
        (l10n.readerDetailAdded, _formatDate(item.createdAt!)),
      if (lastReadAt != null)
        (l10n.readerDetailLastRead, _formatDateTime(lastReadAt)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.description?.isNotEmpty == true
              ? item.description!
              : l10n.readerNoDescription,
          style: TextStyle(
            color: rc.onSurface.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
            height: 1.7,
          ),
        ),
        if (item.genres?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final genre in item.genres!) _genreChip(context, genre),
            ],
          ),
        ],
        const SizedBox(height: 16),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: AppTypography.labelSmall,
                      height: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      color: rc.onSurface,
                      fontSize: AppTypography.bodyMedium,
                      height: 1.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _genreChip(BuildContext context, String genre) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: context.readerColors.surfaceContainerHighest.withValues(
          alpha: 0.6,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: context.readerColors.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        genre,
        style: TextStyle(
          color: context.readerColors.onSurfaceVariant,
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 目录页签 slivers：计数与展开/收起控制 + SliverList 虚拟化行。
  ///
  /// 行自带头部缩进（16+深度×24），此处不再追加水平内边距，与原树视觉一致。
  List<Widget> _buildCatalogSlivers(BuildContext context) {
    final controller = _catalogController;
    if (controller == null || controller.roots.isEmpty) {
      return const [];
    }
    final l10n = AppLocalizations.of(context);
    final rows = controller.flatRows;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 4),
          child: Row(
            children: [
              Text(
                l10n.readerComicCatalogItems(
                  widget.chapters.where((node) => !node.isRoot).length,
                ),
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: l10n.readerComicExpandAll,
                onPressed: controller.expandAll,
                icon: const Icon(Icons.unfold_more_rounded),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.readerComicCollapseAll,
                onPressed: controller.collapseAll,
                icon: const Icon(Icons.unfold_less_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 4),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildComicCatalogRow(
              context,
              row: rows[index],
              controller: controller,
              onNodeTap: (node) {
                context.push(
                  '/reader/comics/${widget.item.id}/read?catalogNodeId=${node.id}',
                );
              },
            ),
            childCount: rows.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildSourcesTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final source in widget.sources) ...[
          ComicSourceTile(
            source: source,
            canDelete: widget.sources.length > 1,
            onRetry: widget.onRetrySource,
            onDelete: widget.onDeleteSource,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _formatDate(DateTime time) {
    final y = time.year.toString();
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDateTime(DateTime time) {
    final y = time.year.toString();
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
