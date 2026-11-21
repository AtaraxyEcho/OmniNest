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
        DesktopSkeletonSwitcher(
          regionId: 'photos-trash',
          hasData: photos.isNotEmpty,
          loading: photos.isEmpty && loading,
          skeleton: const DesktopSkeletonPhotoGrid(
            targetHeight: 200,
            showGroupHeaders: false,
          ),
          child:
              photos.isEmpty
                  ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 54),
                    child: DesktopEmpty(
                      icon: DesktopIcons.trash,
                      message: l10n.photosTrashHint,
                      actionLabel: null,
                    ),
                  )
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      // 样例 `.album-grid`：`minmax(220px,1fr)` + 26 的单一 gap。
                      // 列数要按同一个 26 反推，否则最后一列会挤出容器。
                      const gap = 26.0;
                      final columns = ((constraints.maxWidth + gap) /
                              (220 + gap))
                          .floor()
                          .clamp(2, 7);
                      final width =
                          (constraints.maxWidth - (columns - 1) * gap) /
                          columns;
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
        ),
      ],
    );
  }
}

/// 地点分区（样例 `Photos.tsx` 的 `seg === "Places"`）：左侧点阵地球
/// （可拖动、选中转向）+ 右侧地点列表，下方是选中地点的 Justified 照片墙。
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
            const DesktopSkeletonPhotoGrid(
              targetHeight: 168,
              groups: 1,
              showGroupHeaders: false,
            ),
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
              _JustifiedPhotos(
                photos: photos,
                targetHeight: 180,
                selection: const <String>{},
                onActivate:
                    (photo, groupPhotos) => widget.onOpen(photo, groupPhotos),
                onToggleSelect: (_) {},
                showSelectionControls: false,
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
