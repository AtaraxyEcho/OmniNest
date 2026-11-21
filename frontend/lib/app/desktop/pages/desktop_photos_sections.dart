part of 'desktop_photos_page.dart';

/// 回收站分区（样例 `seg === "Trash"`）：告警横幅 + Justified 照片墙 + 悬停 Restore 胶囊。
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
    final warnColor = Color.lerp(skin.accent, const Color(0xFFE0A458), 0.72)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: warnColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(DesktopMetrics.radius),
            border: Border.all(color: warnColor.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Icon(DesktopIcons.info, size: 16, color: warnColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.photosTrashHint,
                  style: DesktopType.caption(skin.text2),
                ),
              ),
              const SizedBox(width: 12),
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
                      const targetHeight = 200.0;
                      const gap = 8.0;
                      final rows = _layoutTrashRows(
                        constraints.maxWidth,
                        photos,
                        targetHeight,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: gap),
                              child: Row(
                                children: [
                                  for (var i = 0; i < row.length; i++) ...[
                                    if (i > 0) const SizedBox(width: gap),
                                    Expanded(
                                      flex: (row[i].ratio * 1000).round(),
                                      child: _TrashPhotoTile(
                                        photo: row[i].photo,
                                        height: targetHeight,
                                        onRestore:
                                            () => onRestore(row[i].photo),
                                        onPurge: () => onPurge(row[i].photo),
                                      ),
                                    ),
                                  ],
                                ],
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

  List<List<({PhotoItem photo, double ratio})>> _layoutTrashRows(
    double width,
    List<PhotoItem> photos,
    double targetHeight,
  ) {
    final rows = <List<({PhotoItem photo, double ratio})>>[];
    var current = <({PhotoItem photo, double ratio})>[];
    var ratioSum = 0.0;
    for (final photo in photos) {
      final w = photo.width ?? 0;
      final h = photo.height ?? 0;
      final ratio = w > 0 && h > 0 ? (w / h).clamp(0.5, 2.2) : 1.5;
      current.add((photo: photo, ratio: ratio));
      ratioSum += ratio;
      if (ratioSum * targetHeight >= width) {
        rows.add(current);
        current = <({PhotoItem photo, double ratio})>[];
        ratioSum = 0;
      }
    }
    if (current.isNotEmpty) {
      rows.add(current);
    }
    return rows;
  }
}

class _TrashPhotoTile extends StatelessWidget {
  const _TrashPhotoTile({
    required this.photo,
    required this.height,
    required this.onRestore,
    required this.onPurge,
  });

  final PhotoItem photo;
  final double height;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder: (context, hovered) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DesktopImage(
                  url: photo.coverUrl,
                  cacheWidth: 640,
                  fallbackIcon: DesktopIcons.image,
                ),
                AnimatedOpacity(
                  duration: DesktopMotion.of(context, DesktopMotion.soft),
                  opacity: hovered ? 1.0 : 0.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: onRestore,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 14,
                                    sigmaY: 14,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: skin.pop.withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: skin.line2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          DesktopIcons.undo,
                                          size: 14,
                                          color: skin.text,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          l10n.photosRestore,
                                          style: DesktopType.denseStrong(
                                            skin.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: DesktopIconButton(
                            icon: DesktopIcons.trash,
                            size: 30,
                            iconSize: 15,
                            tooltip: l10n.photosDeleteForever,
                            onPressed: onPurge,
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 8,
                          child: Text(
                            photo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(Colors.white),
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
      },
    );
  }
}

/// 地点分区（样例 `Photos.tsx` 的 `seg === "Places"`）：左侧点阵地球
/// （可拖动、选中转向）+ 右侧地点列表，下方是选中地点的完整分页 Justified 照片墙。
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

class _PlacesSection extends ConsumerStatefulWidget {
  const _PlacesSection({required this.groups, required this.onOpen});

  final List<PhotoGroup> groups;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onOpen;

  @override
  ConsumerState<_PlacesSection> createState() => _PlacesSectionState();
}

class _PlacesSectionState extends ConsumerState<_PlacesSection> {
  static const int _pageSize = 60;

  String? _selected;
  int _requestToken = 0;
  bool _loading = false;
  bool _hasMore = false;
  int _nextPage = 0;
  List<PhotoItem>? _loadedPhotos;
  int? _loadedTotal;
  String? _loadedLocation;
  final Map<String, ({double lat, double lon})> _resolvedCoords = {};

  String? get _effectiveSelectedName {
    if (widget.groups.isEmpty) {
      return null;
    }
    if (_selected != null &&
        widget.groups.any((group) => group.groupKey == _selected)) {
      return _selected;
    }
    final places = _places;
    return places.isNotEmpty ? places.first.name : widget.groups.first.groupKey;
  }

  List<DesktopGlobePlace> get _places {
    final result = <DesktopGlobePlace>[];
    for (final group in widget.groups) {
      final photoWithGps =
          group.photos
              .where(
                (item) => item.gpsLatitude != null && item.gpsLongitude != null,
              )
              .firstOrNull;
      final cached = _resolvedCoords[group.groupKey];
      final lat = photoWithGps?.gpsLatitude ?? cached?.lat;
      final lon = photoWithGps?.gpsLongitude ?? cached?.lon;
      if (lat == null || lon == null) {
        continue;
      }
      result.add(
        DesktopGlobePlace(
          name: group.groupKey,
          count: group.photoCount,
          latitude: lat,
          longitude: lon,
          coverPhoto: group.photos.firstOrNull ?? photoWithGps,
        ),
      );
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    final initial = _effectiveSelectedName;
    if (initial != null) {
      unawaited(_loadLocationPage(initial, reset: true));
    }
  }

  @override
  void didUpdateWidget(covariant _PlacesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _effectiveSelectedName;
    if (current != null && current != _loadedLocation) {
      unawaited(_loadLocationPage(current, reset: true));
    }
  }

  void _selectLocation(String location) {
    if (_selected == location && _loadedLocation == location) {
      return;
    }
    setState(() {
      _selected = location;
    });
    unawaited(_loadLocationPage(location, reset: true));
  }

  Future<void> _loadLocationPage(String location, {required bool reset}) async {
    if (!reset && (_loading || !_hasMore)) {
      return;
    }
    final token = ++_requestToken;
    final targetPage = reset ? 0 : _nextPage;
    setState(() {
      _loading = true;
      if (reset) {
        _loadedLocation = location;
        _loadedPhotos = null;
        _loadedTotal = null;
        _nextPage = 0;
        _hasMore = false;
      }
    });

    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listByLocationPage(location, page: targetPage, size: _pageSize);
      if (!mounted || token != _requestToken) {
        return;
      }
      final base =
          reset
              ? <PhotoItem>[]
              : List<PhotoItem>.from(_loadedPhotos ?? const <PhotoItem>[]);
      final existingIds = base.map((item) => item.id).toSet();
      for (final item in page.items) {
        if (existingIds.add(item.id)) {
          base.add(item);
        }
      }
      final gpsPhoto =
          base
              .where(
                (item) => item.gpsLatitude != null && item.gpsLongitude != null,
              )
              .firstOrNull;
      setState(() {
        _loadedLocation = location;
        _loadedPhotos = base;
        _loadedTotal = page.totalElements;
        _nextPage = page.page + 1;
        _hasMore = page.hasMore;
        _loading = false;
        if (gpsPhoto != null && !_resolvedCoords.containsKey(location)) {
          _resolvedCoords[location] = (
            lat: gpsPhoto.gpsLatitude!,
            lon: gpsPhoto.gpsLongitude!,
          );
        }
      });
    } on Object {
      if (!mounted || token != _requestToken) {
        return;
      }
      setState(() {
        _loading = false;
      });
    }
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
    final selectedName = _effectiveSelectedName ?? widget.groups.first.groupKey;
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
            onTap: () => _selectLocation(group.groupKey),
          ),
      ],
    );

    final photos =
        (_loadedLocation == selectedName && _loadedPhotos != null)
            ? _loadedPhotos!
            : selectedGroup.photos;
    final displayCount =
        (_loadedLocation == selectedName && _loadedTotal != null)
            ? math.max(_loadedTotal!, photos.length)
            : selectedGroup.photoCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final globe = SizedBox(
          height: 460,
          child: Center(
            child: DesktopPlacesGlobe(
              places: places,
              selected: selectedName,
              onSelect: _selectLocation,
            ),
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
              l10n.desktopPhotosPlaceCount(displayCount),
              style: DesktopType.caption(skin.text3),
            ),
            const SizedBox(height: 14),
            if (photos.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: DesktopEmpty(
                  icon: DesktopIcons.image,
                  message: l10n.photosNoPlaces,
                  actionLabel: null,
                ),
              )
            else ...[
              _JustifiedPhotos(
                photos: photos,
                targetHeight: 180,
                selection: const <String>{},
                onActivate:
                    (photo, groupPhotos) => widget.onOpen(photo, groupPhotos),
                onToggleSelect: (_) {},
                showSelectionControls: false,
              ),
              if (_hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: DesktopButton(
                      label: l10n.adminLoadMore(photos.length, displayCount),
                      variant: DesktopButtonVariant.soft,
                      busy: _loading,
                      onPressed:
                          _loading
                              ? null
                              : () => unawaited(
                                _loadLocationPage(selectedName, reset: false),
                              ),
                    ),
                  ),
                ),
            ],
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
