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

/// 单日分组悬停联动状态（由组头与同级 `_SliverJustifiedPhotos` 共享，
/// 拆平 `SliverMainAxisGroup` 后依然 100% 保持组头/照片行悬停联动）。
class _PhotoDayHoverState {
  final ValueNotifier<bool> hovered = ValueNotifier<bool>(false);
  int _depth = 0;

  void enter() {
    _depth += 1;
    if (!hovered.value) {
      hovered.value = true;
    }
  }

  void exit() {
    if (_depth > 0) {
      _depth -= 1;
    }
    if (_depth == 0 && hovered.value) {
      hovered.value = false;
    }
  }

  void dispose() {
    hovered.dispose();
  }
}

/// 将照片库拆分为扁平同级 Sliver 列表（移除 `SliverMainAxisGroup` 以避免 Windows
/// `ui::AXTree` 在分组 Sliver 边界产生语义断链），100% 保留按行虚拟化、FLIP 拖拽与悬停联动。
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
  _PhotoDayHoverState Function(String contextKey)? hoverStateOf,
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

  final slivers = <Widget>[];
  for (final entry in groups.entries) {
    final contextKey = photoOrderContextForDay(entry.key);
    final dayPhotos = entry.value;
    final orderedDayPhotos = applyPhotoDisplayOrder(
      dayPhotos,
      displayOrders[contextKey],
    );
    final selectedCount =
        dayPhotos.where((photo) => selection.contains(photo.id)).length;
    final label =
        entry.key == null ? '—' : DateFormat.yMMMMd(locale).format(entry.key!);
    final hoverState = hoverStateOf?.call(contextKey) ?? _PhotoDayHoverState();
    final ownsHoverState = hoverStateOf == null;

    slivers.add(
      SliverToBoxAdapter(
        key: ValueKey<String>('photo-day-head-$contextKey'),
        child: Semantics(
          container: true,
          child: _PhotoDayHeaderHost(
            hoverState: hoverState,
            ownsHoverState: ownsHoverState,
            label: label,
            count: dayPhotos.length,
            selectedCount: selectedCount,
            selectionActive: selectionActive,
            onToggleDay: () => onSelectMany(dayPhotos),
            onReset:
                displayOrders.containsKey(contextKey)
                    ? () => onResetOrder(contextKey)
                    : null,
          ),
        ),
      ),
    );
    slivers.add(
      _SliverJustifiedPhotos(
        key: ValueKey<String>('photo-day-grid-$contextKey'),
        photos: orderedDayPhotos,
        targetHeight: density,
        selection: selection,
        selectionMode: selectionMode,
        onActivate: (photo, _) => onActivate(photo, browsePhotos),
        onToggleSelect: onToggleSelect,
        onSecondaryTap:
            onSecondaryTap == null
                ? null
                : (photo, _, globalPos) =>
                    onSecondaryTap(photo, browsePhotos, globalPos),
        orderContext: contextKey,
        onOrderChanged: onOrderChanged,
        onRowHoverEnter: hoverState.enter,
        onRowHoverExit: hoverState.exit,
      ),
    );
    slivers.add(
      SliverToBoxAdapter(
        key: ValueKey<String>('photo-day-gap-$contextKey'),
        child: const SizedBox(height: 34),
      ),
    );
  }
  return slivers;
}

class _PhotoDayHeaderHost extends StatefulWidget {
  const _PhotoDayHeaderHost({
    required this.hoverState,
    required this.ownsHoverState,
    required this.label,
    required this.count,
    required this.selectedCount,
    required this.selectionActive,
    required this.onToggleDay,
    this.onReset,
  });

  final _PhotoDayHoverState hoverState;
  final bool ownsHoverState;
  final String label;
  final int count;
  final int selectedCount;
  final bool selectionActive;
  final VoidCallback onToggleDay;
  final VoidCallback? onReset;

  @override
  State<_PhotoDayHeaderHost> createState() => _PhotoDayHeaderHostState();
}

class _PhotoDayHeaderHostState extends State<_PhotoDayHeaderHost> {
  @override
  void didUpdateWidget(covariant _PhotoDayHeaderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownsHoverState &&
        !identical(oldWidget.hoverState, widget.hoverState)) {
      oldWidget.hoverState.dispose();
    }
  }

  @override
  void dispose() {
    if (widget.ownsHoverState) {
      widget.hoverState.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => widget.hoverState.enter(),
      onExit: (_) => widget.hoverState.exit(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.hoverState.hovered,
          builder:
              (context, hovered, _) => _GroupHead(
                label: widget.label,
                count: widget.count,
                selectedCount: widget.selectedCount,
                hovered: hovered,
                selectionActive: widget.selectionActive,
                onToggleDay: widget.onToggleDay,
                onReset: widget.onReset,
              ),
        ),
      ),
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
