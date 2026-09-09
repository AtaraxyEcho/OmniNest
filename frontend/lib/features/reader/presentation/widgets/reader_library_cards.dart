import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';

/// 书库“继续阅读”横滑卡：小封面 + 标题作者 + 细进度线。
class ReaderContinueCard extends StatefulWidget {
  const ReaderContinueCard({
    required this.item,
    required this.onTap,
    super.key,
  });

  final ReaderItem item;
  final VoidCallback onTap;

  @override
  State<ReaderContinueCard> createState() => _ReaderContinueCardState();
}

class _ReaderContinueCardState extends State<ReaderContinueCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final item = widget.item;
    final progress = (item.progressPercent ?? 0).clamp(0.0, 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _hovered ? rc.onSurface : rc.outlineVariant,
              ),
            ),
            width: 208,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  height: 72,
                  child: ReaderBookCover(
                    item: item,
                    size: ReaderCoverSize.small,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rc.onSurface,
                            fontSize: AppTypography.bodyMedium,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.authorName?.isNotEmpty == true
                              ? item.authorName!
                              : item.itemType,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rc.onSurfaceVariant,
                            fontSize: AppTypography.labelSmall,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 2,
                          color: rc.outlineVariant,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(height: 2, color: rc.reading),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(progress * 100).round()}%',
                          style: TextStyle(
                            color: rc.onSurfaceVariant,
                            // ignore: font_size_whitelist
                            fontSize: 10,
                            height: 1.2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
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

/// 书库网格卡：封面（进度下划线 + 完成徽标 + 解析状态）+ 标题作者。
class ReaderLibraryGridCard extends ConsumerWidget {
  const ReaderLibraryGridCard({
    required this.item,
    required this.onTap,
    this.onDelete,
    this.onToggleBookshelf,
    super.key,
  });

  final ReaderItem item;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<ReaderItem>? onToggleBookshelf;

  bool get _hasActions => onDelete != null || onToggleBookshelf != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = context.readerColors;
    final progress = item.progressPercent;
    return Semantics(
      label: item.title,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: _hasActions ? () => _showActionsSheet(context) : null,
          onSecondaryTapUp:
              _hasActions
                  ? (details) =>
                      _showActionsMenu(context, details.globalPosition)
                  : null,
          child: _HoverDim(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ReaderBookCover(item: item, size: ReaderCoverSize.grid),
                        if (progress != null && progress > 0 && progress < 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 2,
                              color: rc.outlineVariant,
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress,
                                child: Container(height: 2, color: rc.reading),
                              ),
                            ),
                          ),
                        if (progress != null && progress >= 1)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: rc.reading,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (item.isParsing)
                          _ParseProgressStrip(itemId: item.id),
                        if (item.isPartialFailed || item.isFailed)
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: _ParseStatusBadge(item: item),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: rc.onSurface,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.authorName?.isNotEmpty == true ? item.authorName! : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.labelSmall,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onToggleBookshelf != null)
                  ListTile(
                    leading: Icon(
                      item.addedToBookshelf
                          ? Icons.bookmark_remove_rounded
                          : Icons.bookmark_add_rounded,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    title: Text(
                      item.addedToBookshelf
                          ? l10n.readerRemoveFromBookshelf
                          : l10n.readerAddToBookshelf,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onToggleBookshelf!(item);
                    },
                  ),
                if (onDelete != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                    title: Text(
                      l10n.readerDeleteBook,
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                    ),
                    subtitle: Text(l10n.readerDeleteBookHint),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onDelete!();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _showActionsMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay?.size.width ?? position.dx,
        overlay?.size.height ?? position.dy,
      ),
      items: [
        if (onToggleBookshelf != null)
          PopupMenuItem(
            value: 'bookshelf',
            child: Text(
              item.addedToBookshelf
                  ? l10n.readerRemoveFromBookshelf
                  : l10n.readerAddToBookshelf,
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Text(
              l10n.readerDeleteBook,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ).then((value) {
      if (value == 'bookshelf') onToggleBookshelf?.call(item);
      if (value == 'delete') onDelete?.call();
    });
  }
}

/// 悬停时标题整体变淡（对应参考设计 group-hover 的透明度变化）。
class _HoverDim extends StatefulWidget {
  const _HoverDim({required this.child});

  final Widget child;

  @override
  State<_HoverDim> createState() => _HoverDimState();
}

class _HoverDimState extends State<_HoverDim> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _hovered ? 0.72 : 1,
        child: widget.child,
      ),
    );
  }
}

/// 封面底部的解析状态徽章（部分失败 / 失败）。
class _ParseStatusBadge extends StatelessWidget {
  const _ParseStatusBadge({required this.item});

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final failed = item.isFailed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (failed ? rc.danger : rc.warning).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        failed
            ? l10n.readerComicImportFailed
            : l10n.readerComicImportPartialFailed,
        style: const TextStyle(
          color: Colors.white,
          // ignore: font_size_whitelist
          fontSize: 9,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 封面底部的解析进度条（解析中显示）。
class _ParseProgressStrip extends ConsumerWidget {
  const _ParseProgressStrip({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(textParseProgressProvider(itemId));
    return progressAsync.when(
      data: (value) {
        if (value.finished) {
          return const SizedBox.shrink();
        }
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: LinearProgressIndicator(
            value: (value.progress / 100).clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: Colors.black45,
            color: context.readerColors.reading,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
