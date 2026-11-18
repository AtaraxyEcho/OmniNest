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
          Padding(
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
                  onSelectAll: () => onSelectMany(entry.value),
                  onReset:
                      displayOrders.containsKey(
                            photoOrderContextForDay(entry.key),
                          )
                          ? () =>
                              onResetOrder(photoOrderContextForDay(entry.key))
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
    required this.onSelectAll,
    this.onReset,
  });

  final String label;
  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    // 样例 `.g-head`：日期是 22 衬线，计数 `flex:1` 吃掉中段，右侧常驻
    // "Select all" 链接；三者在基线上对齐，不是底对齐。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label, style: DesktopType.displaySm(skin.text)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.desktopFolderItemCount(count),
            style: DesktopType.caption(skin.text3),
          ),
        ),
        if (onReset != null) ...[
          DesktopLink(label: l10n.desktopPhotosResetOrder, onPressed: onReset),
          const SizedBox(width: 12),
        ],
        DesktopLink(label: l10n.photosSelectAll, onPressed: onSelectAll),
      ],
    );
  }
}

/// 等高一排、按宽高比铺满（样例 `.justified` + `.ph`）。
///
/// 每行先按目标行高算出「加起来能铺满宽度」的照片，再按比例分配宽度：
/// 这是相片墙的排法，固定列网格会把竖构图裁成一样的方块。
