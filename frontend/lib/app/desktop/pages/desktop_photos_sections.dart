part of 'desktop_photos_page.dart';

/// 回收站分区（样例 `seg === "Trash"`）：保留期提示 + 可还原/永久删除的网格。
class _TrashSection extends StatelessWidget {
  const _TrashSection({
    required this.state,
    required this.onRestore,
    required this.onPurge,
    required this.purging,
    required this.onPurgeAll,
  });

  final PhotoCenterState? state;
  final ValueChanged<PhotoItem> onRestore;
  final ValueChanged<PhotoItem> onPurge;
  final bool purging;
  final VoidCallback onPurgeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final photos = state?.trashPhotos ?? const <PhotoItem>[];
    if (state?.isLoadingTrash == true && photos.isEmpty) {
      return const SizedBox(height: 80);
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
        if (photos.isEmpty)
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
class _PlacesSection extends StatefulWidget {
  const _PlacesSection({required this.groups, required this.onOpen});

  final List<PhotoGroup> groups;
  final ValueChanged<PhotoItem> onOpen;

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
                          onTap: () => widget.onOpen(photos[i]),
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

class _JustifiedPhotos extends StatelessWidget {
  const _JustifiedPhotos({
    required this.photos,
    required this.targetHeight,
    required this.selection,
    required this.onActivate,
    required this.onToggleSelect,
    this.showCaption = true,
    this.showFavorite = true,
    this.showSelectionControls = true,
  });

  final List<PhotoItem> photos;
  final double targetHeight;
  final Set<String> selection;
  final ValueChanged<PhotoItem> onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final bool showCaption;
  final bool showFavorite;
  final bool showSelectionControls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rows = _layout(width);
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
                        child: DesktopStagger(
                          index: i,
                          child: _PhotoTile(
                            photo: row[i].photo,
                            height: targetHeight,
                            onTap: onActivate,
                            onToggleSelect: onToggleSelect,
                            selected: selection.contains(row[i].photo.id),
                            selectionActive: selection.isNotEmpty,
                            showCaption: showCaption,
                            showFavorite: showFavorite,
                            showSelectionControls: showSelectionControls,
                          ),
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

  List<List<_SizedPhoto>> _layout(double width) {
    final rows = <List<_SizedPhoto>>[];
    var current = <_SizedPhoto>[];
    var ratioSum = 0.0;
    for (final photo in photos) {
      final ratio = _ratioOf(photo);
      current.add(_SizedPhoto(photo: photo, ratio: ratio));
      ratioSum += ratio;
      if (ratioSum * targetHeight >= width) {
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
}

class _SizedPhoto {
  const _SizedPhoto({required this.photo, required this.ratio});

  final PhotoItem photo;
  final double ratio;
}
