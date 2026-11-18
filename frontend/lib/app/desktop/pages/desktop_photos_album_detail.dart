part of 'desktop_photos_page.dart';

/// 相册详情内嵌在 Albums 分区中，保留样例顶部分类栏与照片墙布局。
class _DesktopAlbumDetail extends ConsumerStatefulWidget {
  const _DesktopAlbumDetail({
    required this.albumId,
    required this.onBack,
    required this.onShare,
    required this.onDelete,
    required this.onOpenPhoto,
    required this.onOrderChanged,
  });

  final String albumId;
  final VoidCallback onBack;
  final ValueChanged<PhotoAlbum> onShare;
  final ValueChanged<PhotoAlbum> onDelete;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onOpenPhoto;
  final _PhotoOrderChanged onOrderChanged;

  @override
  ConsumerState<_DesktopAlbumDetail> createState() =>
      _DesktopAlbumDetailState();
}

class _DesktopAlbumDetailState extends ConsumerState<_DesktopAlbumDetail> {
  PhotoAlbum? _album;
  List<PhotoItem> _photos = const [];
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _initialLoadFinished = false;
  Object? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAlbum());
  }

  @override
  void didUpdateWidget(covariant _DesktopAlbumDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId) {
      _album = null;
      _photos = const [];
      _page = 0;
      _loading = true;
      _loadingMore = false;
      _initialLoadFinished = false;
      _loadError = null;
      unawaited(_loadAlbum());
    }
  }

  Future<void> _loadAlbum() async {
    final generation = ++_loadGeneration;
    try {
      final detail = await ref.read(
        photoAlbumDetailProvider(widget.albumId).future,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _album = detail.album;
        _photos = List<PhotoItem>.of(detail.photos);
        _page = 0;
        _loading = false;
        _initialLoadFinished = true;
        _loadError = null;
      });
      await _loadRemaining(generation: generation);
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _initialLoadFinished = true;
        _loadError = error;
      });
    }
  }

  void _retryLoadAlbum() {
    setState(() {
      _loading = true;
      _initialLoadFinished = false;
      _loadError = null;
    });
    ref.invalidate(photoAlbumDetailProvider(widget.albumId));
    unawaited(_loadAlbum());
  }

  void _replaceFromRefresh(PhotoAlbumDetail detail) {
    if (!_initialLoadFinished || !mounted) return;
    final currentAlbum = _album;
    final sameFirstPage =
        currentAlbum?.updatedAt == detail.album.updatedAt &&
        currentAlbum?.photoCount == detail.album.photoCount &&
        detail.photos.length <= _photos.length &&
        detail.photos.asMap().entries.every(
          (entry) => entry.value.id == _photos[entry.key].id,
        );
    if (sameFirstPage) return;
    final generation = ++_loadGeneration;
    setState(() {
      _album = detail.album;
      _photos = List<PhotoItem>.of(detail.photos);
      _page = 0;
      _loading = false;
      _loadingMore = false;
      _loadError = null;
    });
    unawaited(_loadRemaining(generation: generation));
  }

  Future<void> _loadRemaining({required int generation}) async {
    final album = _album;
    if (_loadingMore || album == null || _photos.length >= album.photoCount) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadError = null;
    });
    try {
      while (mounted && _photos.length < album.photoCount) {
        final nextPage = _page + 1;
        final result = await ref
            .read(photoCenterControllerProvider.notifier)
            .listAlbumPhotos(albumId: widget.albumId, page: nextPage);
        if (!mounted || generation != _loadGeneration) return;
        final seen = _photos.map((photo) => photo.id).toSet();
        final added = [
          for (final photo in result.items)
            if (seen.add(photo.id)) photo,
        ];
        setState(() {
          _page = result.page;
          _photos = [..._photos, ...added];
        });
        if (result.items.isEmpty || added.isEmpty) break;
      }
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadError = error);
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(photoAlbumDetailProvider(widget.albumId), (previous, next) {
      final detail = next.asData?.value;
      if (detail != null) _replaceFromRefresh(detail);
    });
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final orderContext = 'album:${widget.albumId}';
    final orders = ref.watch(photoDisplayOrderProvider);
    final orderedPhotos = applyPhotoDisplayOrder(_photos, orders[orderContext]);
    final album = _album;
    if (_loading && album == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DesktopSkeletonBox(width: 112, height: 12),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DesktopSkeletonBox(width: 240, height: 30),
                    const SizedBox(height: 8),
                    const DesktopSkeletonBox(width: 120, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const DesktopSkeletonBox(width: 84, height: 34),
              const SizedBox(width: 8),
              const DesktopSkeletonBox(width: 96, height: 34),
            ],
          ),
          const SizedBox(height: 18),
          const DesktopSkeletonPhotoGrid(targetHeight: 200),
        ],
      );
    }
    if (album == null) {
      return DesktopEmpty(
        icon: DesktopIcons.image,
        message: l10n.photosOperationFailed,
        actionLabel: l10n.commonRetry,
        onAction: _retryLoadAlbum,
        large: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopLink(
          label: l10n.photosTabAlbums,
          icon: DesktopIcons.left,
          trailing: false,
          onPressed: widget.onBack,
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name, style: DesktopType.display(skin.text)),
                  const SizedBox(height: 3),
                  Text(
                    l10n.desktopPhotosAlbumDetailCaption(album.photoCount),
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 8,
              children: [
                DesktopButton(
                  label: l10n.filesShare,
                  icon: DesktopIcons.share,
                  variant: DesktopButtonVariant.soft,
                  onPressed: () => widget.onShare(album),
                ),
                DesktopButton(
                  label: l10n.photosDeleteAlbumTitle,
                  icon: DesktopIcons.trash,
                  variant: DesktopButtonVariant.ghost,
                  onPressed: () => widget.onDelete(album),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_photos.isEmpty)
          DesktopEmpty(
            icon: DesktopIcons.image,
            message: l10n.photosAlbumEmpty,
            description: l10n.photosAlbumEmptyHint,
            actionLabel: l10n.desktopPhotosLibrary,
            onAction: widget.onBack,
            large: true,
          )
        else
          IgnorePointer(
            ignoring: _loadingMore,
            child: _JustifiedPhotos(
              photos: orderedPhotos,
              targetHeight: 200,
              selection: const <String>{},
              onActivate: (photo, photos) => widget.onOpenPhoto(photo, photos),
              onToggleSelect: (_) {},
              orderContext: orderContext,
              onOrderChanged: widget.onOrderChanged,
              showCaption: false,
              showFavorite: false,
              showSelectionControls: false,
            ),
          ),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_loadError != null && _photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: DesktopButton(
                label: l10n.commonRetry,
                variant: DesktopButtonVariant.soft,
                onPressed:
                    () =>
                        unawaited(_loadRemaining(generation: _loadGeneration)),
              ),
            ),
          ),
      ],
    );
  }
}
