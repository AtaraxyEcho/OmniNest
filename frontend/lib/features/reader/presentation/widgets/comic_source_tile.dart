import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 漫画来源文件条目：状态图标、摘要与重试/删除操作。
class ComicSourceTile extends StatefulWidget {
  const ComicSourceTile({
    required this.source,
    required this.canDelete,
    this.onRetry,
    this.onDelete,
    super.key,
  });

  final ComicSource source;
  final bool canDelete;
  final Future<bool> Function(ComicSource source)? onRetry;
  final Future<bool> Function(ComicSource source)? onDelete;

  @override
  State<ComicSourceTile> createState() => _ComicSourceTileState();
}

class _ComicSourceTileState extends State<ComicSourceTile> {
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
        borderRadius: BorderRadius.circular(2),
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
