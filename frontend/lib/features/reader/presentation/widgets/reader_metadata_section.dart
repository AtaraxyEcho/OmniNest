import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

/// 元数据管理区：标题 + 搜索 + 限高内滚列表。
///
/// 标题与搜索固定在列表上方；列表在固定高度容器内滚动，
/// 避免条目过多把页面下方「最近阅读」推得过远。
class MetadataSection extends StatefulWidget {
  const MetadataSection({required this.items, super.key});

  final List<ReaderItem> items;

  /// 列表区最大高度（px）。
  static const double _listMaxHeight = 560;

  @override
  State<MetadataSection> createState() => _MetadataSectionState();
}

class _MetadataSectionState extends State<MetadataSection> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ReaderItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.items;
    }
    return widget.items.where((item) {
      final title = item.title.toLowerCase();
      final author = (item.authorName ?? '').toLowerCase();
      return title.contains(q) || author.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.readerMetadataManagement,
              style: TextStyle(
                color: context.readerColors.onSurface,
                fontSize: AppTypography.headlineSmall,
                height: 28 / 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: 14),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.readerColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.readerBookCount(filtered.length),
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                  height: 14 / 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          l10n.readerMetadataDesc,
          style: TextStyle(
            color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
            height: 18 / 13,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          style: TextStyle(
            color: context.readerColors.onSurface,
            fontSize: AppTypography.bodyMedium,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.readerSearchBooksHint,
            hintStyle: TextStyle(
              color: context.readerColors.onSurfaceVariant.withValues(
                alpha: 0.65,
              ),
              fontSize: AppTypography.bodyMedium,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: context.readerColors.onSurfaceVariant.withValues(
                alpha: 0.7,
              ),
            ),
            suffixIcon:
                _query.isEmpty
                    ? null
                    : IconButton(
                      tooltip: l10n.readerSearch,
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: context.readerColors.onSurfaceVariant,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            filled: true,
            fillColor: context.readerColors.surfaceContainer.withValues(
              alpha: 0.55,
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.readerColors.outlineVariant.withValues(
                  alpha: 0.35,
                ),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: context.readerColors.outlineVariant.withValues(
                  alpha: 0.35,
                ),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.readerColors.reading),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (filtered.isEmpty)
          _buildEmptyState(context)
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MetadataSection._listMaxHeight,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: context.readerColors.outlineVariant.withValues(
                    alpha: 0.22,
                  ),
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in filtered) _MetadataRow(item: item),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: context.readerColors.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.readerColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _query.isEmpty ? Icons.edit_note_rounded : Icons.search_off_rounded,
            size: 36,
            color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12),
          Text(
            _query.isEmpty ? l10n.readerNoBookEntries : l10n.searchEmptyResult,
            style: TextStyle(
              color: context.readerColors.onSurfaceVariant,
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            _query.isEmpty ? l10n.readerNoBookEntriesHint : l10n.searchFailed,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.readerColors.onSurfaceVariant.withValues(
                alpha: 0.7,
              ),
              fontSize: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatefulWidget {
  const _MetadataRow({required this.item});

  final ReaderItem item;

  @override
  State<_MetadataRow> createState() => _MetadataRowState();
}

class _MetadataRowState extends State<_MetadataRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final statusLabel = switch (item.metadataStatus) {
      'PENDING' => l10n.readerStatusPending,
      'FAILED' => l10n.readerStatusFailed,
      'MANUAL' => l10n.readerStatusManual,
      'MATCHED' => l10n.readerStatusMatched,
      _ => item.metadataStatus ?? l10n.readerStatusUnknown,
    };
    final statusColor = switch (item.metadataStatus) {
      'FAILED' => context.readerColors.danger,
      'MATCHED' => context.readerColors.success,
      _ => context.readerColors.onSurfaceVariant,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.readerColors.surfaceContainerHigh.withValues(
            alpha: _hovered ? 0.88 : 0.72,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.readerColors.outlineVariant.withValues(
              alpha: _hovered ? 0.35 : 0.18,
            ),
          ),
        ),
        child: Row(
          children: [
            // 封面缩略
            Container(
              width: 44,
              height: 62,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: context.readerColors.surfaceContainerHighest,
              ),
              child:
                  item.hasCover
                      ? AuthCoverImage(
                        itemId: item.id,
                        fit: BoxFit.cover,
                        fallback: _fallbackIcon(item),
                      )
                      : _fallbackIcon(item),
            ),
            SizedBox(width: 14),
            // 文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          _hovered
                              ? context.readerColors.primary
                              : context.readerColors.onSurface,
                      fontSize: AppTypography.bodyLarge,
                      height: 18 / 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${readerTypeLabel(l10n, item.itemType)} · ${item.authorName ?? l10n.readerUnknownAuthor} · $statusLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor.withValues(alpha: 0.8),
                      fontSize: AppTypography.bodySmall,
                      height: 16 / 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            // 编辑按钮
            GestureDetector(
              onTap: () => context.push('/reader/items/${item.id}/metadata'),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.readerColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 15,
                      color: context.readerColors.primary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      l10n.readerEdit,
                      style: TextStyle(
                        color: context.readerColors.primary,
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(ReaderItem item) {
    return Center(
      child: Text(
        item.title.trim().isEmpty
            ? '?'
            : item.title.trim().substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: context.readerColors.onSurfaceVariant,
          fontSize: AppTypography.titleLarge,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
