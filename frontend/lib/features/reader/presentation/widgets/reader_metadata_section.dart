import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/confirm_action_dialog.dart';
import 'package:omninest/features/files/application/space_migration_service.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_fill.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 元数据管理区：标题 + 搜索 + 限高懒加载列表。
///
/// 标题与搜索固定在列表上方；列表在固定高度容器内用 [ListView.builder]
/// 懒构建，避免大书库一次实例化全部行，同时不把「最近阅读」推得过远。
///
/// 删除由本节状态发起：条目删除后行组件会被移除，提示必须由存活的父组件发出。
class MetadataSection extends ConsumerStatefulWidget {
  const MetadataSection({required this.items, super.key});

  final List<ReaderItem> items;

  /// 列表区最大高度（px）。
  static const double _listMaxHeight = 560;

  @override
  ConsumerState<MetadataSection> createState() => _MetadataSectionState();
}

class _MetadataSectionState extends ConsumerState<MetadataSection> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _listScrollController.addListener(_onListScroll);
  }

  /// 管理列表在固定高度容器里自带滚动体：外层页面的触底控件看不见它的滚动事件，
  /// 触底必须自己续拉分页，否则第 51 本之后的条目在本页永远滚不到。
  void _onListScroll() {
    if (!mounted || !_listScrollController.hasClients) {
      return;
    }
    final position = _listScrollController.position;
    if (position.pixels < position.maxScrollExtent - 200) {
      return;
    }
    unawaited(
      ref.read(readerCenterControllerProvider.notifier).loadMoreItems(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  /// 永久删除书籍：书库记录与源文件（含 MinIO 对象）一起清理。
  Future<void> _deleteItem(ReaderItem item) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDestructiveAction(
      context,
      title: l10n.readerConfirmDelete,
      message: l10n.readerConfirmDeleteMsg(item.title),
      confirmLabel: l10n.filesDelete,
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .deleteItem(item.id);
      if (!mounted) {
        return;
      }
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerDeletedItem(item.title),
      );
    } on Exception catch (error) {
      if (mounted) {
        // 与书库页同口径：共享进来的书不属于当前用户，后端会回「无权删除」，
        // 吞成「稍后重试」会让人反复点删除。
        showReaderSnackBar(
          context,
          describeUserFacingError(
            error,
            l10n: AppLocalizations.of(context),
          ).displayMessage,
        );
      }
    }
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
    // 本节只持有已加载的分页窗口，搜索是窗口内匹配：命中不足一屏时继续往后拉，
    // 直到凑满或服务端没有下一页，排在后面的书名才可能被搜到。
    final center = ref.watch(readerCenterControllerProvider).asData?.value;
    scheduleReaderPageFill(
      ref,
      visibleCount: filtered.length,
      hasMore: center?.itemsHasMore ?? false,
      isLoadingMore: center?.itemsLoadingMore ?? false,
    );

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
                  controller: _listScrollController,
                  thumbVisibility: true,
                  interactive: true,
                  // builder 懒构建：大书库只创建视口内行，避免一次实例化全部条目。
                  child: ListView.builder(
                    controller: _listScrollController,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(12, 12, 8, 12),
                    itemCount: filtered.length,
                    itemBuilder:
                        (context, index) => _MetadataRow(
                          item: filtered[index],
                          onDeleteItem: _deleteItem,
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

class _MetadataRow extends ConsumerStatefulWidget {
  const _MetadataRow({required this.item, required this.onDeleteItem});

  final ReaderItem item;
  final Future<void> Function(ReaderItem item) onDeleteItem;

  @override
  ConsumerState<_MetadataRow> createState() => _MetadataRowState();
}

class _MetadataRowState extends ConsumerState<_MetadataRow> {
  bool _hovered = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final isShared = item.spaceType == 'SHARED';
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
                  const SizedBox(height: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: context.readerColors.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Text(
                      isShared
                          ? l10n.importToSharedSpace
                          : l10n.importToPersonalSpace,
                      style: TextStyle(
                        color: context.readerColors.onSurfaceVariant,
                        fontSize: AppTypography.labelMicro,
                        height: 1.2,
                      ),
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
            SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: l10n.filesOpenFileMenu,
              enabled: !_busy,
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color:
                    _busy
                        ? context.readerColors.onSurfaceVariant.withValues(
                          alpha: 0.35,
                        )
                        : context.readerColors.onSurfaceVariant,
              ),
              onSelected: (value) => unawaited(_handleMenuAction(value)),
              itemBuilder: (context) {
                final fileNodeId = item.fileNodeId;
                final canMigrateSpace =
                    fileNodeId != null && fileNodeId.isNotEmpty;
                return <PopupMenuEntry<String>>[
                  if (canMigrateSpace)
                    if (!isShared)
                      PopupMenuItem<String>(
                        value: 'moveToShared',
                        child: Text(l10n.filesMoveToShared),
                      )
                    else
                      PopupMenuItem<String>(
                        value: 'moveToPersonal',
                        child: Text(l10n.filesMoveToPersonal),
                      ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      l10n.readerDeleteBook,
                      style: TextStyle(color: context.readerColors.danger),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(String action) async {
    if (_busy) {
      return;
    }
    final item = widget.item;
    if (action == 'delete') {
      setState(() => _busy = true);
      try {
        // 删除会让本行从列表消失，确认与提示由父节状态承接。
        await widget.onDeleteItem(item);
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }
      return;
    }
    final fileNodeId = item.fileNodeId;
    if (fileNodeId == null || fileNodeId.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _migrateSpace(item, fileNodeId, action == 'moveToShared');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _migrateSpace(
    ReaderItem item,
    String fileNodeId,
    bool toShared,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDestructiveAction(
      context,
      title:
          toShared
              ? l10n.filesMoveToSharedConfirm
              : l10n.filesMoveToPersonalConfirm,
      message:
          toShared
              ? l10n.filesMoveToSharedMessage(item.title)
              : l10n.filesMoveToPersonalMessage(item.title),
      confirmLabel:
          toShared ? l10n.filesMoveToShared : l10n.filesMoveToPersonalLabel,
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      final service = ref.read(spaceMigrationServiceProvider);
      if (toShared) {
        await service.moveToSharedSpace(fileNodeId);
      } else {
        await service.moveToPersonalSpace(fileNodeId);
      }
      if (!mounted) {
        return;
      }
      await ref.read(readerCenterControllerProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      final resolvedL10n = AppLocalizations.of(context);
      showReaderSnackBar(
        context,
        toShared
            ? resolvedL10n.filesMoveToSharedSuccess
            : resolvedL10n.filesMoveToPersonalSuccess,
      );
    } on Exception {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).filesMoveSpaceFailed,
        );
      }
    }
  }

  Widget _fallbackIcon(ReaderItem item) {
    return Center(
      child: Text(
        item.title.trim().isEmpty
            ? '?'
            : item.title.trim().characters.first.toUpperCase(),
        style: TextStyle(
          color: context.readerColors.onSurfaceVariant,
          fontSize: AppTypography.titleLarge,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
