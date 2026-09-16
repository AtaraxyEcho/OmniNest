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
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 漫画详情页 — 展示封面、信息、目录树、继续阅读。
///
/// 接收 [ReaderItem] 和可选的 [ComicManifest] 数据，
/// 渲染漫画专属的详情布局。
class ComicDetailPage extends ConsumerStatefulWidget {
  const ComicDetailPage({
    required this.item,
    this.chapters = const [],
    this.sources = const [],
    this.onRetrySource,
    this.onDeleteSource,
    this.canRead = true,
    this.parseProgress,
    super.key,
  });

  /// 漫画条目数据。
  final ReaderItem item;

  /// 章节列表（来自 ComicManifest.catalog 或本地解析）。
  final List<ComicCatalogNode> chapters;

  /// 来源文件列表（用于展示多源解析状态）。
  final List<ComicSource> sources;

  /// 重试失败来源。
  final Future<bool> Function(ComicSource source)? onRetrySource;

  /// 删除来源。
  final Future<bool> Function(ComicSource source)? onDeleteSource;

  /// 清单至少包含一个可读页面时允许进入阅读器。
  final bool canRead;

  /// 后台解析任务进度。
  final int? parseProgress;

  @override
  ConsumerState<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends ConsumerState<ComicDetailPage> {
  bool _bookshelfBusy = false;
  bool _showFullDescription = false;

  static const _collapsedMaxLines = 3;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = AppLocalizations.of(context);
    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;

    // 滚动由外层详情页的滚动体承担；本页自身再嵌滚动/Scaffold
    // 会在无界约束下产生布局错误。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // 封面
              _ComicDetailCover(item: item),
              const SizedBox(height: 28),
              // 标题
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.readerColors.onSurface,
                  fontSize: AppTypography.headlineSmall,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // 作者
              if (item.authorName?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  item.authorName!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.readerColors.onSurface.withValues(
                      alpha: 0.6,
                    ),
                    fontSize: AppTypography.bodyLarge,
                    height: 1.4,
                  ),
                ),
              ],
              // 导入状态提示
              if (item.isParsing) ...[
                const SizedBox(height: 12),
                _ImportStatusBanner(
                  icon: Icons.hourglass_top_rounded,
                  message: l10n.readerComicParsingMessage,
                  color: context.readerColors.tertiary,
                ),
                if (widget.parseProgress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: widget.parseProgress!.clamp(0, 100) / 100,
                  ),
                ],
              ] else if (item.isPartialFailed) ...[
                const SizedBox(height: 12),
                _ImportStatusBanner(
                  icon: Icons.warning_amber_rounded,
                  message: l10n.readerComicPartialFailedMessage,
                  color: context.readerColors.warning,
                ),
              ] else if (item.isFailed) ...[
                const SizedBox(height: 12),
                _ImportStatusBanner(
                  icon: Icons.error_outline_rounded,
                  message: l10n.readerComicFailedMessage,
                  color: context.readerColors.danger,
                ),
              ],
              const SizedBox(height: 16),
              // 数据胶囊行
              _buildCapsuleRow(item),
              // 分类标签
              if (item.genres?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                _buildGenreTags(item.genres!),
              ],
              const SizedBox(height: 28),
              // 阅读按钮
              _buildActionButtons(context, item),
              const SizedBox(height: 32),
              // 简介
              _buildDescriptionSection(context, item),
              // 来源解析状态
              if (widget.sources.isNotEmpty) ...[
                const SizedBox(height: 28),
                _buildSourcesSection(context, widget.sources),
              ],
              // 目录
              if (widget.chapters.isNotEmpty) ...[
                const SizedBox(height: 28),
                _buildCatalogSection(context, widget.chapters),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// 数据胶囊行
  Widget _buildCapsuleRow(ReaderItem item) {
    final capsules = <_CapsuleData>[
      _CapsuleData(
        readerTypeLabel(AppLocalizations.of(context), item.itemType),
        context.readerColors.primary,
      ),
      if (item.rating != null && item.rating! > 0)
        _CapsuleData(
          '${item.rating!.toStringAsFixed(1)} ★',
          context.readerColors.success,
        ),
      if (item.publisher?.isNotEmpty == true)
        _CapsuleData(item.publisher!, context.readerColors.tertiary),
      if (item.serialStatus?.isNotEmpty == true)
        _CapsuleData(item.serialStatus!, context.readerColors.success),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final c in capsules)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              c.label,
              style: TextStyle(
                color: c.color,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// 分类标签
  Widget _buildGenreTags(List<String> genres) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final genre in genres)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: context.readerColors.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: context.readerColors.outlineVariant.withValues(
                  alpha: 0.24,
                ),
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
          ),
      ],
    );
  }

  /// 阅读/书架操作按钮
  Widget _buildActionButtons(BuildContext context, ReaderItem item) {
    final hasProgress =
        item.progressPercent != null && item.progressPercent! > 0;

    final l10n = AppLocalizations.of(context);
    final readButton = FilledButton.icon(
      onPressed:
          widget.canRead
              ? () => context.push('/reader/comics/${item.id}/read')
              : null,
      icon: Icon(
        hasProgress ? Icons.play_arrow_rounded : Icons.auto_stories_rounded,
        size: 20,
      ),
      label: Text(
        hasProgress ? l10n.readerContinueReading : l10n.readerStartReading,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: context.readerColors.primaryContainer,
        foregroundColor: context.readerColors.onPrimaryContainer,
      ),
    );
    final bookshelfButton = FilledButton.icon(
      onPressed: _bookshelfBusy ? null : () => _toggleBookshelf(item),
      icon: Icon(
        item.addedToBookshelf
            ? Icons.bookmark_rounded
            : Icons.bookmark_add_rounded,
        size: 18,
      ),
      label:
          _bookshelfBusy
              ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.readerColors.onSurfaceVariant,
                ),
              )
              : Text(
                item.addedToBookshelf
                    ? l10n.readerAddedToBookshelf
                    : l10n.readerAddToBookshelf,
              ),
      style: FilledButton.styleFrom(
        backgroundColor:
            item.addedToBookshelf
                ? context.readerColors.primary.withValues(alpha: 0.12)
                : context.readerColors.surfaceContainerHigh,
        foregroundColor:
            item.addedToBookshelf
                ? context.readerColors.primary
                : context.readerColors.onSurfaceVariant,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        if (stackButtons) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [readButton, const SizedBox(height: 8), bookshelfButton],
          );
        }
        return Row(
          children: [
            Expanded(child: readButton),
            const SizedBox(width: 12),
            Expanded(child: bookshelfButton),
          ],
        );
      },
    );
  }

  /// 切换书架状态
  Future<void> _toggleBookshelf(ReaderItem item) async {
    setState(() => _bookshelfBusy = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(item.id);
      if (mounted) {
        ref.invalidate(readerCenterControllerProvider);
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(
          context,
          item.addedToBookshelf
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

  /// 简介区域
  Widget _buildDescriptionSection(BuildContext context, ReaderItem item) {
    final l10n = AppLocalizations.of(context);
    final desc =
        item.description?.isNotEmpty == true
            ? item.description!
            : l10n.readerNoDescription;
    final hasLongDesc = desc.length > 120;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readerDescription,
          style: TextStyle(
            color: context.readerColors.onSurface,
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap:
              hasLongDesc
                  ? () => setState(
                    () => _showFullDescription = !_showFullDescription,
                  )
                  : null,
          child: Text(
            desc,
            maxLines: _showFullDescription ? null : _collapsedMaxLines,
            overflow: _showFullDescription ? null : TextOverflow.ellipsis,
            style: TextStyle(
              color: context.readerColors.onSurfaceVariant,
              fontSize: AppTypography.bodyMedium,
              height: 1.7,
            ),
          ),
        ),
        if (hasLongDesc)
          GestureDetector(
            onTap:
                () => setState(
                  () => _showFullDescription = !_showFullDescription,
                ),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _showFullDescription
                    ? l10n.readerCollapse
                    : l10n.readerExpandFull,
                style: TextStyle(
                  color: context.readerColors.primary,
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 目录区域（树形结构）
  Widget _buildCatalogSection(
    BuildContext context,
    List<ComicCatalogNode> chapters,
  ) {
    // 统计可读叶子节点
    final leafCount =
        chapters
            .where(
              (n) =>
                  n.nodeType == 'CHAPTER' ||
                  n.nodeType == 'COLLECTION' ||
                  n.nodeType == 'EXTRA',
            )
            .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context).readerTableOfContents,
              style: TextStyle(
                color: context.readerColors.onSurface,
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (leafCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).readerTotalChapters(leafCount),
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 460,
          child: ComicCatalogTree(
            nodes: chapters,
            shrinkWrap: false,
            showControls: true,
            onNodeTap: (node) {
              context.push(
                '/reader/comics/${widget.item.id}/read?catalogNodeId=${node.id}',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesSection(BuildContext context, List<ComicSource> sources) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).readerComicSources,
          style: TextStyle(
            color: context.readerColors.onSurface,
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (final source in sources) ...[
          _ComicSourceTile(
            source: source,
            canDelete: sources.length > 1,
            onRetry: widget.onRetrySource,
            onDelete: widget.onDeleteSource,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ComicSourceTile extends StatefulWidget {
  const _ComicSourceTile({
    required this.source,
    required this.canDelete,
    this.onRetry,
    this.onDelete,
  });

  final ComicSource source;
  final bool canDelete;
  final Future<bool> Function(ComicSource source)? onRetry;
  final Future<bool> Function(ComicSource source)? onDelete;

  @override
  State<_ComicSourceTile> createState() => _ComicSourceTileState();
}

class _ComicSourceTileState extends State<_ComicSourceTile> {
  bool _busy = false;

  bool get _failed => widget.source.status == 'FAILED';
  bool get _parsing =>
      widget.source.status == 'PENDING' || widget.source.status == 'PARSING';

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context);
    final l10n = AppLocalizations.of(context);
    final subtitle = _subtitle(l10n);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.readerColors.surfaceContainerHigh.withValues(
          alpha: 0.62,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: _failed ? 0.35 : 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.source.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.readerColors.onSurface,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.readerColors.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            if (_failed && widget.onRetry != null)
              IconButton(
                tooltip: l10n.readerRetry,
                icon: const Icon(Icons.refresh_rounded),
                color: color,
                onPressed: () => _runAction(widget.onRetry!),
              ),
            if (widget.canDelete && widget.onDelete != null)
              IconButton(
                tooltip: AppLocalizations.of(context).readerDeleteSource,
                icon: const Icon(Icons.delete_outline_rounded),
                color: context.readerColors.danger,
                onPressed: _confirmDelete,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _runAction(
    Future<bool> Function(ComicSource source) action,
  ) async {
    setState(() => _busy = true);
    final ok = await action(widget.source);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    final l10n = AppLocalizations.of(context);
    showReaderSnackBar(
      context,
      ok ? l10n.readerOperationSubmitted : l10n.readerOperationFailed,
    );
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.readerDeleteSource),
            content: Text(
              l10n.readerConfirmDeleteSource(widget.source.sourceName),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.readerDeleteSource),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true || widget.onDelete == null) {
      return;
    }
    await _runAction(widget.onDelete!);
  }

  String _subtitle(AppLocalizations l10n) {
    final pieces = <String>[
      widget.source.fileFormat,
      l10n.readerPageCount(widget.source.pageCount),
    ];
    if (widget.source.readingDirection == 'rtl') {
      pieces.add(l10n.readerRtl);
    } else if (widget.source.readingDirection == 'ltr') {
      pieces.add(l10n.readerLtr);
    }
    if (_parsing) {
      pieces.add(l10n.readerComicImportParsing);
    }
    if (_failed) {
      pieces.add(widget.source.errorMessage ?? l10n.readerComicImportFailed);
    }
    if (widget.source.retryCount > 0) {
      pieces.add(l10n.readerComicRetryCount(widget.source.retryCount));
    }
    return pieces.join(' · ');
  }

  IconData _statusIcon() {
    if (_failed) {
      return Icons.error_outline_rounded;
    }
    if (_parsing) {
      return Icons.hourglass_top_rounded;
    }
    return Icons.check_circle_outline_rounded;
  }

  Color _statusColor(BuildContext context) {
    if (_failed) {
      return context.readerColors.danger;
    }
    if (_parsing) {
      return context.readerColors.tertiary;
    }
    return context.readerColors.success;
  }
}

/// 漫画详情页封面组件
class _ComicDetailCover extends StatelessWidget {
  const _ComicDetailCover({required this.item});

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        height: 280,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              context.readerColors.comicBg,
              context.readerColors.comicBg.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child:
            item.hasCover
                ? AuthCoverImage(
                  itemId: item.id,
                  fit: BoxFit.cover,
                  fallback: _buildPlaceholder(context),
                )
                : _buildPlaceholder(context),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          item.title.trim().isEmpty
              ? 'C'
              : item.title.trim().substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: context.readerColors.comicText,
            fontSize: AppTypography.displayLarge,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Icon(
          Icons.auto_stories_rounded,
          color: context.readerColors.comicMuted,
          size: 32,
        ),
      ],
    );
  }
}

/// 胶囊数据（用于复用样式）
class _CapsuleData {
  const _CapsuleData(this.label, this.color);

  final String label;
  final Color color;
}

/// 导入状态横幅。
class _ImportStatusBanner extends StatelessWidget {
  const _ImportStatusBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
