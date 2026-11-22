part of 'desktop_photos_page.dart';

/// 按拍摄日分组，同一天内保持服务端顺序。
Map<DateTime?, List<PhotoItem>> _groupPhotosByDay(List<PhotoItem> items) {
  final groups = <DateTime?, List<PhotoItem>>{};
  for (final item in items) {
    final taken = item.dateTaken ?? item.createdAt;
    final key =
        taken == null ? null : DateTime(taken.year, taken.month, taken.day);
    groups.putIfAbsent(key, () => <PhotoItem>[]).add(item);
  }
  return groups;
}

/// 将照片库拆分为按日期组 + 按行虚拟化的 Sliver 列表（`SliverMainAxisGroup` +
/// `SliverList.builder`），大幅降低百张以上照片的首屏构建与滚动开销。
List<Widget> _buildPhotoGroupSlivers({
  required BuildContext context,
  required List<PhotoItem> photos,
  required Map<String, List<String>> displayOrders,
  required bool loading,
  required VoidCallback onRetry,
  String? error,
  required double density,
  required Set<String> selection,
  bool selectionMode = false,
  required void Function(PhotoItem photo, List<PhotoItem> photos) onActivate,
  required ValueChanged<PhotoItem> onToggleSelect,
  void Function(PhotoItem photo, List<PhotoItem> photos, Offset globalPosition)?
  onSecondaryTap,
  required ValueChanged<List<PhotoItem>> onSelectMany,
  required _PhotoOrderChanged onOrderChanged,
  required Future<void> Function(String contextKey) onResetOrder,
}) {
  final l10n = AppLocalizations.of(context);
  if (error != null) {
    return <Widget>[
      SliverToBoxAdapter(
        child: DesktopErrorView(message: error, onRetry: onRetry),
      ),
    ];
  }
  if (loading || photos.isEmpty) {
    return <Widget>[
      SliverToBoxAdapter(
        child: DesktopSkeletonSwitcher(
          regionId: 'photos-library',
          hasData: photos.isNotEmpty,
          loading: loading,
          skeleton: DesktopSkeletonPhotoGrid(targetHeight: density),
          child: DesktopEmpty(
            icon: DesktopIcons.image,
            message: l10n.desktopHomeEmptyPhotos,
            description: l10n.desktopPhotosEmptyBody,
            large: true,
          ),
        ),
      ),
    ];
  }

  final groups = _groupPhotosByDay(photos);
  final browsePhotos = applyPhotoLibraryDisplayOrder(photos, displayOrders);
  final selectionActive = selection.isNotEmpty || selectionMode;
  final locale = Localizations.localeOf(context).toString();

  return <Widget>[
    for (final entry in groups.entries)
      _PhotoDaySliverGroup(
        key: ValueKey<String>(
          'photo-day-${photoOrderContextForDay(entry.key)}',
        ),
        dayKey: entry.key,
        label:
            entry.key == null
                ? '—'
                : DateFormat.yMMMMd(locale).format(entry.key!),
        dayPhotos: entry.value,
        orderedDayPhotos: applyPhotoDisplayOrder(
          entry.value,
          displayOrders[photoOrderContextForDay(entry.key)],
        ),
        browsePhotos: browsePhotos,
        contextKey: photoOrderContextForDay(entry.key),
        hasCustomOrder: displayOrders.containsKey(
          photoOrderContextForDay(entry.key),
        ),
        density: density,
        selection: selection,
        selectionMode: selectionMode,
        selectionActive: selectionActive,
        onActivate: onActivate,
        onToggleSelect: onToggleSelect,
        onSecondaryTap: onSecondaryTap,
        onSelectMany: onSelectMany,
        onOrderChanged: onOrderChanged,
        onResetOrder: onResetOrder,
      ),
  ];
}

/// 单日照片虚拟化分组：使用 [SliverMainAxisGroup] 组合组头与按行虚拟化的
/// [_SliverJustifiedPhotos]，仅在视口范围内构建可见行。
class _PhotoDaySliverGroup extends StatefulWidget {
  const _PhotoDaySliverGroup({
    required this.dayKey,
    required this.label,
    required this.dayPhotos,
    required this.orderedDayPhotos,
    required this.browsePhotos,
    required this.contextKey,
    required this.hasCustomOrder,
    required this.density,
    required this.selection,
    required this.selectionMode,
    required this.selectionActive,
    required this.onActivate,
    required this.onToggleSelect,
    required this.onSelectMany,
    required this.onOrderChanged,
    required this.onResetOrder,
    this.onSecondaryTap,
    super.key,
  });

  final DateTime? dayKey;
  final String label;
  final List<PhotoItem> dayPhotos;
  final List<PhotoItem> orderedDayPhotos;
  final List<PhotoItem> browsePhotos;
  final String contextKey;
  final bool hasCustomOrder;
  final double density;
  final Set<String> selection;
  final bool selectionMode;
  final bool selectionActive;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final void Function(
    PhotoItem photo,
    List<PhotoItem> photos,
    Offset globalPosition,
  )?
  onSecondaryTap;
  final ValueChanged<List<PhotoItem>> onSelectMany;
  final _PhotoOrderChanged onOrderChanged;
  final Future<void> Function(String contextKey) onResetOrder;

  @override
  State<_PhotoDaySliverGroup> createState() => _PhotoDaySliverGroupState();
}

class _PhotoDaySliverGroupState extends State<_PhotoDaySliverGroup> {
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);
  int _hoverDepth = 0;

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  void _enter() {
    _hoverDepth += 1;
    if (!_hovered.value) {
      _hovered.value = true;
    }
  }

  void _exit() {
    if (_hoverDepth > 0) {
      _hoverDepth -= 1;
    }
    if (_hoverDepth == 0 && _hovered.value) {
      _hovered.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount =
        widget.dayPhotos
            .where((photo) => widget.selection.contains(photo.id))
            .length;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: (_) => _enter(),
            onExit: (_) => _exit(),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ValueListenableBuilder<bool>(
                valueListenable: _hovered,
                builder:
                    (context, hovered, _) => _GroupHead(
                      label: widget.label,
                      count: widget.dayPhotos.length,
                      selectedCount: selectedCount,
                      hovered: hovered,
                      selectionActive: widget.selectionActive,
                      onToggleDay: () => widget.onSelectMany(widget.dayPhotos),
                      onReset:
                          widget.hasCustomOrder
                              ? () => widget.onResetOrder(widget.contextKey)
                              : null,
                    ),
              ),
            ),
          ),
        ),
        _SliverJustifiedPhotos(
          photos: widget.orderedDayPhotos,
          targetHeight: widget.density,
          selection: widget.selection,
          selectionMode: widget.selectionMode,
          onActivate:
              (photo, _) => widget.onActivate(photo, widget.browsePhotos),
          onToggleSelect: widget.onToggleSelect,
          onSecondaryTap:
              widget.onSecondaryTap == null
                  ? null
                  : (photo, _, globalPos) => widget.onSecondaryTap!(
                    photo,
                    widget.browsePhotos,
                    globalPos,
                  ),
          orderContext: widget.contextKey,
          onOrderChanged: widget.onOrderChanged,
          onRowHoverEnter: _enter,
          onRowHoverExit: _exit,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 34)),
      ],
    );
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
    // 样例 `.g-head`：22px 圆形日选择位于日期左侧，悬停整日区块任意照片、
    // 已有选择或开启多选开关时显现；右侧在悬停或有自定义排序时展示重置排序。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedOpacity(
          opacity: hovered || selectionActive ? 1 : 0,
          duration: DesktopMotion.fast,
          alwaysIncludeSemantics: true,
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
          AnimatedOpacity(
            opacity: hovered || selectionActive ? 1 : 0,
            duration: DesktopMotion.fast,
            alwaysIncludeSemantics: true,
            child: DesktopLink(
              label: l10n.desktopPhotosResetOrder,
              onPressed: onReset,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ],
    );
  }
}
