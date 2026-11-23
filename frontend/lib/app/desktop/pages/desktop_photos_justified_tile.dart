part of 'desktop_photos_page.dart';

/// 等高流布局行构建与容器包装（从 desktop_photos_justified.dart 拆出）。
extension _JustifiedPhotosLayout<W extends StatefulWidget>
    on _JustifiedPhotosStateMixin<W> {
  List<PhotoItem> _resolveOrderedPhotos() {
    final activeOrder = _dragOrder ?? _settlingOrder;
    final photos =
        activeOrder == null
            ? _photos
            : applyPhotoDisplayOrder(
              _photos
                  .where((photo) => activeOrder.contains(photo.id))
                  .toList(growable: false),
              activeOrder,
            );
    for (final photo in photos) {
      _tileKeys.putIfAbsent(
        photo.id,
        () => GlobalObjectKey<State<StatefulWidget>>('photo-order-${photo.id}'),
      );
    }
    return photos;
  }

  Widget _buildJustifiedRow(
    BuildContext context,
    List<_SizedPhoto> row,
    List<PhotoItem> photos, {
    required bool isReordering,
    required bool selectionActive,
  }) {
    final rowWidget = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (var i = 0; i < row.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              flex: (row[i].ratio * 1000).round(),
              child: LayoutBuilder(
                builder: (context, tileConstraints) {
                  final photo = row[i].photo;
                  // 保持单张照片卡片在拖拽起落全过程节点树恒定，杜绝松手整组重播入场动画。
                  final tile = _PhotoTile(
                    key: ValueKey<String>('desktop-photo-${photo.id}'),
                    photo: photo,
                    height: _targetHeight,
                    onTap: (selectedPhoto) {
                      if (_draggedPhotoId != null) {
                        return;
                      }
                      if (_justDragged) return;
                      _onActivate(selectedPhoto, photos);
                    },
                    onToggleSelect: _onToggleSelect,
                    onSecondaryTap:
                        _onSecondaryTap == null
                            ? null
                            : (targetPhoto, globalPos) => _onSecondaryTap!(
                              targetPhoto,
                              photos,
                              globalPos,
                            ),
                    onInspect:
                        _onInspect == null
                            ? null
                            : (targetPhoto) => _onInspect!(targetPhoto, photos),
                    selected: _selection.contains(photo.id),
                    pressing: _pressingPhotoIds.contains(photo.id),
                    dragging: _draggedPhotoId == photo.id,
                    reordering: isReordering,
                    landed: _landedPhotoIds.contains(photo.id),
                    selectionActive: selectionActive,
                    showCaption: _showCaption,
                    showFavorite: _showFavorite,
                    showSelectionControls: _showSelectionControls,
                  );
                  final orderContext = _orderContext;
                  final onOrderChanged = _onOrderChanged;
                  if (orderContext == null ||
                      onOrderChanged == null ||
                      photos.length < 2) {
                    return tile;
                  }

                  final selectedIds = _selection;
                  final movingPhotos =
                      selectedIds.contains(photo.id) && selectedIds.length > 1
                          ? photos
                              .where((item) => selectedIds.contains(item.id))
                              .toList(growable: false)
                          : <PhotoItem>[photo];
                  final movingIds = movingPhotos
                      .map((item) => item.id)
                      .toList(growable: false);
                  final orderIds = photos
                      .map((item) => item.id)
                      .toList(growable: false);
                  final tileWidth = tileConstraints.maxWidth;
                  final feedbackWidth =
                      movingPhotos.length > 1 && tileWidth > 190
                          ? 190.0
                          : tileWidth;
                  final feedbackHeight =
                      tileWidth > 0
                          ? _targetHeight * feedbackWidth / tileWidth
                          : _targetHeight;
                  final tileKey = _tileKeys[photo.id]!;
                  return _FlipPhotoTile(
                    key: tileKey,
                    photoId: photo.id,
                    tracker: _flipTracker,
                    epoch: _flipTracker.epoch,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        final payload = _PhotoDragPayload(
                          contextKey: orderContext,
                          orderIds: orderIds,
                          baseOrderIds: orderIds
                              .where(
                                (id) =>
                                    id == photo.id || !movingIds.contains(id),
                              )
                              .toList(growable: false),
                          draggedId: photo.id,
                          movingIds: movingIds,
                          movingPhotos: movingPhotos,
                          feedbackWidth: feedbackWidth,
                          feedbackHeight: feedbackHeight,
                          fanOffsets: const <_PhotoFlyOffset>[],
                          grabOffset: event.localPosition,
                        );
                        _onTilePointerDown(payload, event, event.localPosition);
                      },
                      onPointerMove: _onTilePointerMove,
                      onPointerUp: _onTilePointerUp,
                      onPointerCancel: _onTilePointerCancel,
                      child: tile,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
    if (_onRowHoverEnter == null && _onRowHoverExit == null) {
      return rowWidget;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => _onRowHoverEnter?.call(),
      onExit: (_) => _onRowHoverExit?.call(),
      child: rowWidget,
    );
  }

  Widget _buildBoxJustified(BuildContext context) {
    final photos = _resolveOrderedPhotos();
    final isReordering = _draggedPhotoId != null;
    final selectionActive = _selection.isNotEmpty || _selectionMode;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (photos.length == 1) {
          return _soloLayout(context, photos.first, width, selectionActive);
        }
        final rows = _layout(width, photos);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              _buildJustifiedRow(
                context,
                row,
                photos,
                isReordering: isReordering,
                selectionActive: selectionActive,
              ),
          ],
        );
      },
    );
  }

  /// 按行虚拟化 Sliver 构建：通过 [SliverLayoutBuilder] + [SliverList.builder]
  /// 仅实例化视口及缓存区内的行，显著降低百张以上照片的首屏构建与滚动开销。
  Widget _buildSliverJustified(BuildContext context) {
    final photos = _resolveOrderedPhotos();
    final isReordering = _draggedPhotoId != null;
    final selectionActive = _selection.isNotEmpty || _selectionMode;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        if (photos.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        if (photos.length == 1) {
          final solo = _soloLayout(
            context,
            photos.first,
            width,
            selectionActive,
          );
          return SliverToBoxAdapter(
            child:
                _onRowHoverEnter == null && _onRowHoverExit == null
                    ? solo
                    : MouseRegion(
                      cursor: SystemMouseCursors.basic,
                      onEnter: (_) => _onRowHoverEnter?.call(),
                      onExit: (_) => _onRowHoverExit?.call(),
                      child: solo,
                    ),
          );
        }
        final rows = _layout(width, photos);
        return SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, rowIndex) {
            return _buildJustifiedRow(
              context,
              rows[rowIndex],
              photos,
              isReordering: isReordering,
              selectionActive: selectionActive,
            );
          },
        );
      },
    );
  }

  /// 单张照片：照片按原比例 + `.solo-note` 旁注（polish.css:324-328）。
  Widget _soloLayout(
    BuildContext context,
    PhotoItem photo,
    double width,
    bool selectionActive,
  ) {
    final ratio = _ratioOf(photo);
    final photoWidth = (_targetHeight * ratio).clamp(120.0, width);
    final noteWidth = (width - photoWidth - 20).clamp(220.0, 320.0);
    final singleList = <PhotoItem>[photo];
    final tile = SizedBox(
      width: photoWidth,
      height: _targetHeight,
      child: _PhotoTile(
        photo: photo,
        height: _targetHeight,
        onTap: (selectedPhoto) => _onActivate(selectedPhoto, singleList),
        onToggleSelect: _onToggleSelect,
        onSecondaryTap:
            _onSecondaryTap == null
                ? null
                : (targetPhoto, globalPos) =>
                    _onSecondaryTap!(targetPhoto, singleList, globalPos),
        onInspect:
            _onInspect == null
                ? null
                : (targetPhoto) => _onInspect!(targetPhoto, singleList),
        selected: _selection.contains(photo.id),
        selectionActive: selectionActive,
        showCaption: _showCaption,
        showFavorite: _showFavorite,
        showSelectionControls: _showSelectionControls,
      ),
    );
    return Wrap(
      spacing: 20,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        tile,
        SizedBox(width: noteWidth, child: _SoloNote(photo: photo)),
      ],
    );
  }

  List<List<_SizedPhoto>> _layout(double width, List<PhotoItem> photos) {
    final rows = <List<_SizedPhoto>>[];
    var current = <_SizedPhoto>[];
    var ratioSum = 0.0;
    for (final photo in photos) {
      final ratio = _ratioOf(photo);
      current.add(_SizedPhoto(photo: photo, ratio: ratio));
      ratioSum += ratio;
      if (ratioSum * _targetHeight >= width) {
        rows.add(current);
        current = <_SizedPhoto>[];
        ratioSum = 0;
      }
    }
    if (current.isNotEmpty) {
      rows.add(current);
    }
    return rows;
  }

  /// 宽高比夹在 0.5–2.2：极端长图会把整行压成一条缝。
  double _ratioOf(PhotoItem photo) {
    final width = photo.width ?? 0;
    final height = photo.height ?? 0;
    if (width <= 0 || height <= 0) {
      return 1.5;
    }
    return (width / height).clamp(0.5, 2.2);
  }

  bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class _JustifiedPhotosState extends State<_JustifiedPhotos>
    with
        TickerProviderStateMixin,
        _JustifiedPhotosStateMixin<_JustifiedPhotos> {
  @override
  List<PhotoItem> get _photos => widget.photos;
  @override
  double get _targetHeight => widget.targetHeight;
  @override
  Set<String> get _selection => widget.selection;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos) get _onActivate =>
      widget.onActivate;
  @override
  ValueChanged<PhotoItem> get _onToggleSelect => widget.onToggleSelect;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos, Offset globalPosition)?
  get _onSecondaryTap => widget.onSecondaryTap;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos)? get _onInspect =>
      widget.onInspect;
  @override
  bool get _selectionMode => widget.selectionMode;
  @override
  String? get _orderContext => widget.orderContext;
  @override
  _PhotoOrderChanged? get _onOrderChanged => widget.onOrderChanged;
  @override
  bool get _showCaption => widget.showCaption;
  @override
  bool get _showFavorite => widget.showFavorite;
  @override
  bool get _showSelectionControls => widget.showSelectionControls;

  @override
  Widget build(BuildContext context) => _buildBoxJustified(context);
}

/// 按行 Sliver 虚拟化的 Justified 照片流，供 [SliverMainAxisGroup] 按日分组消费。
class _SliverJustifiedPhotos extends StatefulWidget {
  const _SliverJustifiedPhotos({
    super.key,
    required this.photos,
    required this.targetHeight,
    required this.selection,
    required this.onActivate,
    required this.onToggleSelect,
    this.onSecondaryTap,
    this.onInspect,
    this.selectionMode = false,
    this.orderContext,
    this.onOrderChanged,
    this.onRowHoverEnter,
    this.onRowHoverExit,
  });
  final List<PhotoItem> photos;
  final double targetHeight;
  final Set<String> selection;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final void Function(
    PhotoItem photo,
    List<PhotoItem> photos,
    Offset globalPosition,
  )?
  onSecondaryTap;
  final void Function(PhotoItem photo, List<PhotoItem> photos)? onInspect;
  final bool selectionMode;
  final String? orderContext;
  final _PhotoOrderChanged? onOrderChanged;

  /// 日分组与 Justified 流共用同一套磁贴开关，当前仅此一处消费，故不再从构造参数透传。
  final bool showCaption = true;
  final bool showFavorite = true;
  final bool showSelectionControls = true;
  final VoidCallback? onRowHoverEnter;
  final VoidCallback? onRowHoverExit;

  @override
  State<_SliverJustifiedPhotos> createState() => _SliverJustifiedPhotosState();
}

class _SliverJustifiedPhotosState extends State<_SliverJustifiedPhotos>
    with
        TickerProviderStateMixin,
        _JustifiedPhotosStateMixin<_SliverJustifiedPhotos> {
  @override
  List<PhotoItem> get _photos => widget.photos;
  @override
  double get _targetHeight => widget.targetHeight;
  @override
  Set<String> get _selection => widget.selection;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos) get _onActivate =>
      widget.onActivate;
  @override
  ValueChanged<PhotoItem> get _onToggleSelect => widget.onToggleSelect;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos, Offset globalPosition)?
  get _onSecondaryTap => widget.onSecondaryTap;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos)? get _onInspect =>
      widget.onInspect;
  @override
  bool get _selectionMode => widget.selectionMode;
  @override
  String? get _orderContext => widget.orderContext;
  @override
  _PhotoOrderChanged? get _onOrderChanged => widget.onOrderChanged;
  @override
  bool get _showCaption => widget.showCaption;
  @override
  bool get _showFavorite => widget.showFavorite;
  @override
  bool get _showSelectionControls => widget.showSelectionControls;
  @override
  VoidCallback? get _onRowHoverEnter => widget.onRowHoverEnter;
  @override
  VoidCallback? get _onRowHoverExit => widget.onRowHoverExit;

  @override
  Widget build(BuildContext context) => _buildSliverJustified(context);
}
