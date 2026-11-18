part of 'desktop_photos_page.dart';

/// 回收站分区（样例 `seg === "Trash"`）：保留期提示 + 可还原/永久删除的网格。
class _TrashSection extends StatelessWidget {
  const _TrashSection({
    required this.state,
    required this.loading,
    required this.onRetry,
    required this.onRestore,
    required this.onPurge,
    required this.purging,
    required this.onPurgeAll,
    this.error,
  });

  final PhotoCenterState? state;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<PhotoItem> onRestore;
  final ValueChanged<PhotoItem> onPurge;
  final bool purging;
  final VoidCallback onPurgeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final photos = state?.trashPhotos ?? const <PhotoItem>[];
    if (error != null) {
      return DesktopErrorView(message: error!, onRetry: onRetry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: skin.raise,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
            border: Border.all(color: skin.line),
          ),
          child: Row(
            children: [
              Icon(DesktopIcons.info, size: 15, color: skin.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.photosTrashHint,
                  style: DesktopType.caption(skin.text2),
                ),
              ),
              DesktopButton(
                label: l10n.photosEmptyTrash,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.soft,
                busy: purging,
                onPressed: photos.isEmpty || purging ? null : onPurgeAll,
              ),
            ],
          ),
        ),
        if (photos.isEmpty && loading)
          const DesktopSkeletonPhotoGrid(targetHeight: 200)
        else if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 54),
            child: DesktopEmpty(
              icon: DesktopIcons.trash,
              message: l10n.photosTrashHint,
              actionLabel: null,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // 样例 `.album-grid`：`minmax(220px,1fr)` + 26 的单一 gap。
              // 列数要按同一个 26 反推，否则最后一列会挤出容器。
              const gap = 26.0;
              final columns = ((constraints.maxWidth + gap) / (220 + gap))
                  .floor()
                  .clamp(2, 7);
              final width =
                  (constraints.maxWidth - (columns - 1) * gap) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    SizedBox(
                      width: width,
                      child: DesktopStagger(
                        index: i,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 4 / 3,
                              child: DesktopImage(
                                url: photos[i].coverUrl,
                                cacheWidth: 640,
                                borderRadius: BorderRadius.circular(
                                  DesktopMetrics.radius,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              photos[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.rowTitle(skin.text),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                DesktopButton(
                                  label: l10n.photosRestore,
                                  icon: DesktopIcons.undo,
                                  variant: DesktopButtonVariant.ghost,
                                  onPressed: () => onRestore(photos[i]),
                                ),
                                const SizedBox(width: 6),
                                DesktopButton(
                                  label: l10n.photosDeleteForever,
                                  icon: DesktopIcons.trash,
                                  variant: DesktopButtonVariant.ghost,
                                  onPressed: () => onPurge(photos[i]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// 地点分区（样例 `Photos.tsx` 的 `seg === "Places"`）：左侧点阵地球
/// （可拖动、选中转向）+ 右侧地点列表，下方是选中地点的照片墙。
class _PlacesLoadingSkeleton extends StatelessWidget {
  const _PlacesLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const globe = DesktopSkeletonBox(
          height: 460,
          radius: DesktopMetrics.radiusHero,
        );
        final locations = Column(
          children: [
            for (var index = 0; index < 5; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    DesktopSkeletonBox(
                      width: 48,
                      height: 48,
                      radius: 10,
                      index: index * 3,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.68,
                            alignment: Alignment.centerLeft,
                            child: DesktopSkeletonBox(
                              height: 13,
                              index: index * 3 + 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FractionallySizedBox(
                            widthFactor: 0.40,
                            alignment: Alignment.centerLeft,
                            child: DesktopSkeletonBox(
                              height: 10,
                              index: index * 3 + 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                ),
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxWidth >= 900)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: globe),
                  const SizedBox(width: 28),
                  SizedBox(width: 320, child: locations),
                ],
              )
            else ...[
              globe,
              const SizedBox(height: 18),
              locations,
            ],
            const SizedBox(height: 28),
            const DesktopSkeletonBox(width: 190, height: 24),
            const SizedBox(height: 8),
            const DesktopSkeletonBox(width: 110, height: 12),
            const SizedBox(height: 14),
            const DesktopSkeletonPhotoGrid(targetHeight: 168),
          ],
        );
      },
    );
  }
}

class _PlacesSection extends StatefulWidget {
  const _PlacesSection({required this.groups, required this.onOpen});

  final List<PhotoGroup> groups;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onOpen;

  @override
  State<_PlacesSection> createState() => _PlacesSectionState();
}

class _PlacesSectionState extends State<_PlacesSection> {
  String? _selected;

  List<DesktopGlobePlace> get _places {
    final result = <DesktopGlobePlace>[];
    for (final group in widget.groups) {
      final photo =
          group.photos
              .where(
                (item) => item.gpsLatitude != null && item.gpsLongitude != null,
              )
              .firstOrNull;
      if (photo == null) {
        continue;
      }
      result.add(
        DesktopGlobePlace(
          name: group.groupKey,
          count: group.photoCount,
          latitude: photo.gpsLatitude!,
          longitude: photo.gpsLongitude!,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    if (widget.groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 54),
        child: DesktopEmpty(
          icon: DesktopIcons.pin,
          message: l10n.photosNoPlaces,
          actionLabel: null,
        ),
      );
    }
    final places = _places;
    final selectedName =
        _selected ??
        (places.isNotEmpty ? places.first.name : widget.groups.first.groupKey);
    final selectedGroup =
        widget.groups
            .where((group) => group.groupKey == selectedName)
            .firstOrNull ??
        widget.groups.first;

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in widget.groups)
          _PlaceRow(
            group: group,
            selected: group.groupKey == selectedName,
            onTap: () => setState(() => _selected = group.groupKey),
          ),
      ],
    );

    final photos = selectedGroup.photos;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final globe = Container(
          height: 460,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: skin.raise,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
            border: Border.all(color: skin.line),
          ),
          child: DesktopPlacesGlobe(
            places: places,
            selected: selectedName,
            onSelect: (name) => setState(() => _selected = name),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: globe),
                  const SizedBox(width: 28),
                  SizedBox(width: 320, child: list),
                ],
              )
            else ...[
              globe,
              const SizedBox(height: 18),
              list,
            ],
            const SizedBox(height: 28),
            Text(
              selectedName.isEmpty ? l10n.desktopPhotosLocation : selectedName,
              style: DesktopType.sectionTitle(skin.text),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.desktopPhotosPlaceCount(selectedGroup.photoCount),
              style: DesktopType.caption(skin.text3),
            ),
            const SizedBox(height: 14),
            if (photos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: DesktopEmpty(
                  icon: DesktopIcons.image,
                  message: l10n.photosNoPlaces,
                  actionLabel: null,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < photos.length && i < 18; i++)
                    SizedBox(
                      width: 168,
                      height: 168,
                      child: DesktopStagger(
                        index: i,
                        child: DesktopHoverLift(
                          onTap: () => widget.onOpen(photos[i], photos),
                          child: DesktopImage(
                            url: photos[i].coverUrl,
                            cacheWidth: 512,
                            borderRadius: BorderRadius.circular(
                              DesktopMetrics.radiusSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final PhotoGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: DesktopMotion.of(context, DesktopMotion.fast),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              decoration: BoxDecoration(
                color:
                    selected
                        ? skin.raise2
                        : hovered
                        ? skin.raise
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(DesktopMetrics.radius),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: DesktopImage(
                      url:
                          group.photos.isEmpty
                              ? null
                              : group.photos.first.coverUrl,
                      cacheWidth: 192,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.groupKey.isEmpty
                              ? l10n.desktopPhotosLocation
                              : group.groupKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.rowTitle(skin.text),
                        ),
                        Text(
                          l10n.desktopPhotosPlaceCount(group.photoCount),
                          style: DesktopType.caption(skin.text3),
                        ),
                      ],
                    ),
                  ),
                  Icon(DesktopIcons.chevron, size: 15, color: skin.text3),
                ],
              ),
            ),
          ),
    );
  }
}

class _JustifiedPhotos extends StatefulWidget {
  const _JustifiedPhotos({
    required this.photos,
    required this.targetHeight,
    required this.selection,
    required this.onActivate,
    required this.onToggleSelect,
    this.orderContext,
    this.onOrderChanged,
    this.showCaption = true,
    this.showFavorite = true,
    this.showSelectionControls = true,
  });

  final List<PhotoItem> photos;
  final double targetHeight;
  final Set<String> selection;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final String? orderContext;
  final _PhotoOrderChanged? onOrderChanged;
  final bool showCaption;
  final bool showFavorite;
  final bool showSelectionControls;

  @override
  State<_JustifiedPhotos> createState() => _JustifiedPhotosState();
}

class _JustifiedPhotosState extends State<_JustifiedPhotos> {
  List<String>? _dragOrder;
  String? _lastSwapTarget;
  DateTime? _lastSwapAt;
  bool _dropAccepted = false;
  int _flipGeneration = 0;
  final Map<String, GlobalKey<State<StatefulWidget>>> _tileKeys = {};
  Map<String, Offset> _flipOffsets = const {};
  Rect? _dragOriginRect;
  OverlayEntry? _settleOverlay;

  void _startDrag(_PhotoDragPayload payload) {
    _dragOriginRect = _rectFor(payload.draggedId);
    setState(() {
      _dragOrder = List<String>.of(payload.orderIds);
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _dropAccepted = false;
    });
  }

  void _trackTarget(_PhotoDragPayload payload, String targetId) {
    if (targetId == payload.draggedId ||
        payload.contextKey != widget.orderContext ||
        _lastSwapTarget == targetId) {
      return;
    }
    final now = DateTime.now();
    final lastSwapAt = _lastSwapAt;
    if (lastSwapAt != null &&
        now.difference(lastSwapAt) < DesktopMotion.photoReorderSwapCooldown) {
      return;
    }
    final currentOrder = _dragOrder ?? payload.orderIds;
    final oldPositions = _positionsFor(currentOrder);
    final nextOrder = movePhotoDisplayOrder(
      order: currentOrder,
      draggedId: payload.draggedId,
      targetId: targetId,
      selectedIds: payload.selectedIds,
    );
    if (_sameOrder(currentOrder, nextOrder)) return;
    setState(() {
      _dragOrder = nextOrder;
      _lastSwapTarget = targetId;
      _lastSwapAt = now;
    });
    final generation = ++_flipGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _flipGeneration) return;
      final offsets = <String, Offset>{};
      for (final entry in oldPositions.entries) {
        final newPosition = _positionFor(entry.key);
        if (newPosition == null) continue;
        final offset = entry.value - newPosition;
        if (offset.distance > 1) offsets[entry.key] = offset;
      }
      setState(() => _flipOffsets = offsets);
    });
  }

  void _autoScroll(Offset pointer) {
    final scrollable = Scrollable.maybeOf(context);
    final renderObject = scrollable?.context.findRenderObject();
    if (scrollable == null || renderObject is! RenderBox) return;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final bottom = top + renderObject.size.height;
    final distanceFromTop = top + 80 - pointer.dy;
    final distanceFromBottom = pointer.dy - (bottom - 80);
    final delta =
        distanceFromTop > 0
            ? -((distanceFromTop / 5).ceil().clamp(1, 18))
            : distanceFromBottom > 0
            ? (distanceFromBottom / 5).ceil().clamp(1, 18)
            : 0;
    if (delta == 0) return;
    final position = scrollable.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next != position.pixels) position.jumpTo(next);
  }

  Map<String, Offset> _positionsFor(List<String> ids) {
    final positions = <String, Offset>{};
    for (final id in ids) {
      final position = _positionFor(id);
      if (position != null) positions[id] = position;
    }
    return positions;
  }

  Offset? _positionFor(String id) {
    return _rectFor(id)?.topLeft;
  }

  Rect? _rectFor(String id) {
    final object = _tileKeys[id]?.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return null;
    return object.localToGlobal(Offset.zero) & object.size;
  }

  void _settleDragFeedback(
    _PhotoDragPayload payload,
    DraggableDetails details, {
    required bool accepted,
  }) {
    final targetRect = accepted ? _rectFor(payload.draggedId) : _dragOriginRect;
    if (targetRect == null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayObject = overlay?.context.findRenderObject();
    if (overlay == null ||
        overlayObject is! RenderBox ||
        !overlayObject.hasSize) {
      return;
    }

    _removeSettleOverlay();
    final targetTopLeft = overlayObject.globalToLocal(targetRect.topLeft);
    final startTopLeft = overlayObject.globalToLocal(details.offset);
    final target = targetTopLeft & targetRect.size;
    final start = Rect.fromLTWH(
      startTopLeft.dx,
      startTopLeft.dy,
      payload.feedbackWidth,
      payload.feedbackHeight,
    );
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (overlayContext) => TweenAnimationBuilder<Rect>(
            tween: _PhotoRectTween(begin: start, end: target),
            duration: DesktopMotion.of(
              overlayContext,
              DesktopMotion.photoReorderSettle,
            ),
            curve: DesktopMotion.ease,
            onEnd: () {
              if (identical(_settleOverlay, entry)) _removeSettleOverlay();
            },
            builder:
                (context, rect, child) => Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: rect.width,
                      height: rect.height,
                      child: FittedBox(fit: BoxFit.fill, child: child),
                    ),
                  ),
                ),
            child: _PhotoDragFeedback(
              photos: payload.movingPhotos,
              width: payload.feedbackWidth,
              height: payload.feedbackHeight,
            ),
          ),
    );
    _settleOverlay = entry;
    overlay.insert(entry);
  }

  void _removeSettleOverlay() {
    final entry = _settleOverlay;
    _settleOverlay = null;
    entry?.remove();
    entry?.dispose();
  }

  void _finishDrag(_PhotoDragPayload payload, DraggableDetails details) {
    if (!mounted) return;
    final order = _dragOrder;
    final accepted = _dropAccepted && details.wasAccepted;
    _settleDragFeedback(payload, details, accepted: accepted);
    final onOrderChanged = widget.onOrderChanged;
    if (accepted &&
        order != null &&
        !_sameOrder(payload.orderIds, order) &&
        onOrderChanged != null) {
      unawaited(
        onOrderChanged(payload.contextKey, order, payload.movingPhotos.length),
      );
    }
    setState(() {
      _dragOrder = null;
      _lastSwapTarget = null;
      _lastSwapAt = null;
      _dropAccepted = false;
    });
    _dragOriginRect = null;
  }

  @override
  void dispose() {
    _removeSettleOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos =
        _dragOrder == null
            ? widget.photos
            : applyPhotoDisplayOrder(widget.photos, _dragOrder);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rows = _layout(width, photos);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        flex: (row[i].ratio * 1000).round(),
                        child: LayoutBuilder(
                          builder: (context, tileConstraints) {
                            final photo = row[i].photo;
                            final card = DesktopStagger(
                              index: i,
                              child: _PhotoTile(
                                photo: photo,
                                height: widget.targetHeight,
                                onTap:
                                    (selectedPhoto) => widget.onActivate(
                                      selectedPhoto,
                                      photos,
                                    ),
                                onToggleSelect: widget.onToggleSelect,
                                selected: widget.selection.contains(photo.id),
                                selectionActive: widget.selection.isNotEmpty,
                                showCaption: widget.showCaption,
                                showFavorite: widget.showFavorite,
                                showSelectionControls:
                                    widget.showSelectionControls,
                              ),
                            );
                            final orderContext = widget.orderContext;
                            final onOrderChanged = widget.onOrderChanged;
                            if (orderContext == null ||
                                onOrderChanged == null ||
                                photos.length < 2) {
                              return card;
                            }
                            final selectedIds = widget.selection;
                            final movingPhotos =
                                selectedIds.contains(photo.id) &&
                                        selectedIds.length > 1
                                    ? photos
                                        .where(
                                          (item) =>
                                              selectedIds.contains(item.id),
                                        )
                                        .toList(growable: false)
                                    : <PhotoItem>[photo];
                            final payload = _PhotoDragPayload(
                              contextKey: orderContext,
                              orderIds: photos
                                  .map((item) => item.id)
                                  .toList(growable: false),
                              draggedId: photo.id,
                              selectedIds: selectedIds,
                              movingPhotos: movingPhotos,
                              feedbackWidth:
                                  movingPhotos.length > 1 &&
                                          tileConstraints.maxWidth > 190
                                      ? 190
                                      : tileConstraints.maxWidth,
                              feedbackHeight:
                                  widget.targetHeight *
                                  (movingPhotos.length > 1 &&
                                          tileConstraints.maxWidth > 190
                                      ? 190
                                      : tileConstraints.maxWidth) /
                                  tileConstraints.maxWidth,
                            );
                            final tileKey = _tileKeys.putIfAbsent(
                              photo.id,
                              () => GlobalObjectKey<State<StatefulWidget>>(
                                'photo-order-${photo.id}',
                              ),
                            );
                            final draggable =
                                LongPressDraggable<_PhotoDragPayload>(
                                  key: tileKey,
                                  data: payload,
                                  delay: DesktopMotion.photoReorderHold,
                                  dragAnchorStrategy: pointerDragAnchorStrategy,
                                  feedback: _PhotoDragFeedback(
                                    photos: movingPhotos,
                                    width: tileConstraints.maxWidth,
                                    height: widget.targetHeight,
                                  ),
                                  onDragStarted: () => _startDrag(payload),
                                  onDragEnd:
                                      (details) =>
                                          _finishDrag(payload, details),
                                  childWhenDragging: Opacity(
                                    opacity: 0.35,
                                    child: card,
                                  ),
                                  child: card,
                                );
                            return TweenAnimationBuilder<Offset>(
                              tween: Tween<Offset>(
                                begin: _flipOffsets[photo.id] ?? Offset.zero,
                                end: Offset.zero,
                              ),
                              duration: DesktopMotion.of(
                                context,
                                DesktopMotion.photoReorderFlip,
                              ),
                              curve: DesktopMotion.ease,
                              builder:
                                  (context, offset, child) =>
                                      Transform.translate(
                                        offset: offset,
                                        child: child,
                                      ),
                              child: DragTarget<_PhotoDragPayload>(
                                onWillAcceptWithDetails:
                                    (details) =>
                                        details.data.contextKey ==
                                            orderContext &&
                                        details.data.draggedId != photo.id,
                                onMove: (details) {
                                  _trackTarget(details.data, photo.id);
                                  _autoScroll(details.offset);
                                },
                                onAcceptWithDetails: (_) {
                                  _dropAccepted = true;
                                },
                                builder:
                                    (context, candidates, rejected) =>
                                        draggable,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
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
      if (ratioSum * widget.targetHeight >= width) {
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

class _PhotoDragPayload {
  const _PhotoDragPayload({
    required this.contextKey,
    required this.orderIds,
    required this.draggedId,
    required this.selectedIds,
    required this.movingPhotos,
    required this.feedbackWidth,
    required this.feedbackHeight,
  });

  final String contextKey;
  final List<String> orderIds;
  final String draggedId;
  final Set<String> selectedIds;
  final List<PhotoItem> movingPhotos;
  final double feedbackWidth;
  final double feedbackHeight;
}

class _PhotoRectTween extends Tween<Rect> {
  _PhotoRectTween({required Rect begin, required Rect end})
    : super(begin: begin, end: end);

  @override
  Rect lerp(double t) => Rect.lerp(begin!, end!, t)!;
}

class _PhotoDragFeedback extends StatelessWidget {
  const _PhotoDragFeedback({
    required this.photos,
    required this.width,
    required this.height,
  });

  final List<PhotoItem> photos;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final stack = photos.length > 1;
    final targetWidth = stack && width > 190 ? 190.0 : width;
    final targetHeight = width <= 0 ? height : height * targetWidth / width;
    final stackCount = photos.length.clamp(1, 4).toInt();
    final skin = DesktopSkin.of(context);
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: targetWidth,
        height: targetHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = stackCount - 1; index >= 0; index--)
              Positioned(
                left: index * 5,
                top: index * 5,
                right: (stackCount - index - 1) * 5,
                bottom: (stackCount - index - 1) * 5,
                child: Transform.rotate(
                  angle: stack ? (index - 1) * 0.025 : 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: DesktopCover(
                      url: photos[index].coverUrl,
                      kind: DesktopCoverKind.network,
                      fallbackIcon: DesktopIcons.image,
                    ),
                  ),
                ),
              ),
            if (stack)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: skin.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${photos.length}',
                    style: DesktopType.caption(skin.accentInk),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SizedPhoto {
  const _SizedPhoto({required this.photo, required this.ratio});

  final PhotoItem photo;
  final double ratio;
}
