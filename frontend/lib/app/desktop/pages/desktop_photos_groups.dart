part of 'desktop_photos_page.dart';

/// 按日期分组的照片墙与组头。
///
/// 独立成 part：主页面文件已经贴着源码行数棘轮，列表分组属于纯展示层，
/// 搬出来不影响任何状态归属。

class _PhotoGroups extends StatelessWidget {
  const _PhotoGroups({
    required this.photos,
    required this.displayOrders,
    required this.loading,
    required this.onRetry,
    this.error,
    required this.density,
    required this.selection,
    required this.onActivate,
    required this.onToggleSelect,
    required this.onSelectMany,
    required this.onOrderChanged,
    required this.onResetOrder,
  });

  final List<PhotoItem> photos;
  final Map<String, List<String>> displayOrders;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final double density;
  final Set<String> selection;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final ValueChanged<List<PhotoItem>> onSelectMany;
  final _PhotoOrderChanged onOrderChanged;
  final Future<void> Function(String contextKey) onResetOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (error != null) {
      return DesktopErrorView(message: error!, onRetry: onRetry);
    }
    if (loading) {
      return DesktopSkeletonPhotoGrid(targetHeight: density);
    }
    if (photos.isEmpty) {
      return DesktopEmpty(
        icon: DesktopIcons.image,
        message: l10n.desktopHomeEmptyPhotos,
        description: l10n.desktopPhotosEmptyBody,
        large: true,
      );
    }
    final groups = _groupByDay(photos);
    final browsePhotos = applyPhotoLibraryDisplayOrder(photos, displayOrders);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries)
          DesktopHover(
            cursor: SystemMouseCursors.basic,
            builder: (context, hovered) {
              final selectedCount =
                  entry.value
                      .where((photo) => selection.contains(photo.id))
                      .length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GroupHead(
                      label:
                          entry.key == null
                              ? '—'
                              : DateFormat.yMMMMd(
                                Localizations.localeOf(context).toString(),
                              ).format(entry.key!),
                      count: entry.value.length,
                      selectedCount: selectedCount,
                      hovered: hovered,
                      selectionActive: selection.isNotEmpty,
                      onToggleDay: () => onSelectMany(entry.value),
                      onReset:
                          displayOrders.containsKey(
                                photoOrderContextForDay(entry.key),
                              )
                              ? () => onResetOrder(
                                photoOrderContextForDay(entry.key),
                              )
                              : null,
                    ),
                    const SizedBox(height: 12),
                    _JustifiedPhotos(
                      photos: applyPhotoDisplayOrder(
                        entry.value,
                        displayOrders[photoOrderContextForDay(entry.key)],
                      ),
                      targetHeight: density,
                      selection: selection,
                      onActivate: (photo, _) => onActivate(photo, browsePhotos),
                      onToggleSelect: onToggleSelect,
                      orderContext: photoOrderContextForDay(entry.key),
                      onOrderChanged: onOrderChanged,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  /// 按拍摄日分组，同一天内保持服务端顺序。
  Map<DateTime?, List<PhotoItem>> _groupByDay(List<PhotoItem> items) {
    final groups = <DateTime?, List<PhotoItem>>{};
    for (final item in items) {
      final taken = item.dateTaken ?? item.createdAt;
      final key =
          taken == null ? null : DateTime(taken.year, taken.month, taken.day);
      groups.putIfAbsent(key, () => <PhotoItem>[]).add(item);
    }
    return groups;
  }
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({
    required this.label,
    required this.count,
    required this.selectedCount,
    required this.hovered,
    required this.selectionActive,
    required this.onToggleDay,
    this.onReset,
  });

  final String label;
  final int count;
  final int selectedCount;
  final bool hovered;
  final bool selectionActive;
  final VoidCallback onToggleDay;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final allSelected = count > 0 && selectedCount == count;
    final partiallySelected = selectedCount > 0 && !allSelected;
    final selectionLabel =
        allSelected ? l10n.photosDeselectDay : l10n.photosSelectDay;
    // 样例 `.g-head`：22px 圆形日选择位于日期左侧，只在组 hover、已有
    // 选择或键盘聚焦时显示；计数随该组选择数切换，右侧只保留重置排序。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        AnimatedOpacity(
          opacity: hovered || selectionActive ? 1 : 0,
          duration: DesktopMotion.fast,
          child: AnimatedScale(
            scale: hovered || selectionActive ? 1 : 0.8,
            duration: DesktopMotion.soft,
            child: IconButton(
              onPressed: onToggleDay,
              tooltip: selectionLabel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 22, height: 22),
              style: IconButton.styleFrom(
                backgroundColor:
                    allSelected
                        ? skin.accent
                        : partiallySelected
                        ? skin.accentWash(0.3)
                        : Colors.transparent,
                foregroundColor:
                    allSelected
                        ? skin.accentInk
                        : partiallySelected
                        ? skin.accent
                        : Colors.transparent,
                side: BorderSide(
                  color:
                      allSelected || partiallySelected
                          ? skin.accent
                          : skin.text3,
                  width: 1.8,
                ),
                shape: const CircleBorder(),
              ),
              icon: const Icon(DesktopIcons.check, size: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: DesktopType.displaySm(skin.text)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            selectedCount > 0
                ? l10n.photosGroupSelectedCount(selectedCount, count)
                : l10n.photosItemCount(count),
            style: DesktopType.caption(skin.text3),
          ),
        ),
        if (onReset != null) ...[
          DesktopLink(label: l10n.desktopPhotosResetOrder, onPressed: onReset),
          const SizedBox(width: 12),
        ],
      ],
    );
  }
}

/// 等高一排、按宽高比铺满（样例 `.justified` + `.ph`）。
///
/// 每行先按目标行高算出「加起来能铺满宽度」的照片，再按比例分配宽度：
/// 这是相片墙的排法，固定列网格会把竖构图裁成一样的方块。
