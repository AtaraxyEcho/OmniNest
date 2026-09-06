part of 'photos_page.dart';

/// Frame 视图内容分发：网格、时间线、地点、标签、影集与回收站。
///
/// 地点与回收站的完整交互在后续批次实现；标签视图已接入实时查询。
class _FrameViewContent extends ConsumerWidget {
  const _FrameViewContent({
    required this.state,
    required this.compact,
    required this.onOpenPhoto,
    required this.onOpenAlbum,
    required this.onDeleteAlbum,
    required this.onCreateAlbum,
    required this.onToggleFavorite,
    required this.onRestoreFromTrash,
    required this.onDeleteForeverFromTrash,
    required this.onEmptyTrash,
  });

  final PhotoCenterState state;
  final bool compact;
  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoAlbum> onOpenAlbum;
  final ValueChanged<PhotoAlbum> onDeleteAlbum;
  final VoidCallback onCreateAlbum;
  final ValueChanged<PhotoItem> onToggleFavorite;
  final ValueChanged<PhotoItem> onRestoreFromTrash;
  final ValueChanged<PhotoItem> onDeleteForeverFromTrash;
  final VoidCallback onEmptyTrash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedSwitcher(
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
      child: switch (state.frameView) {
        FrameView.grid || FrameView.favorites => _buildGrid(context, ref),
        FrameView.timeline => PhotoTimelineView(
          key: const ValueKey('frame-timeline'),
          onOpenPhoto: (photo) {
            // 时间线的浏览范围为当前已加载的各月份预览照片。
            final timeline = state.timeline;
            if (timeline != null) {
              final previews = <PhotoItem>[
                for (final year in timeline.years)
                  for (final month in year.months) ...month.previewPhotos,
              ];
              ref.read(photoBrowseScopeProvider.notifier).set(previews);
            }
            onOpenPhoto(photo);
          },
          state: state,
        ),
        FrameView.locations => FrameLocationsView(
          key: const ValueKey('frame-locations'),
          onOpenPhoto: onOpenPhoto,
          onToggleFavorite: onToggleFavorite,
        ),
        FrameView.tags => FrameTagsView(
          key: const ValueKey('frame-tags'),
          onOpenPhoto: onOpenPhoto,
          onToggleFavorite: onToggleFavorite,
        ),
        FrameView.albums => FrameAlbumsView(
          key: const ValueKey('frame-albums'),
          albums: state.albums,
          onOpenAlbum: onOpenAlbum,
          onDeleteAlbum: onDeleteAlbum,
          onCreateAlbum: onCreateAlbum,
        ),
        FrameView.trash => FrameTrashView(
          key: const ValueKey('frame-trash'),
          photos: state.trashPhotos,
          isLoading: state.isLoadingTrash,
          errorMessage: state.trashPageError,
          onRestore: onRestoreFromTrash,
          onDeleteForever: onDeleteForeverFromTrash,
          onEmptyTrash: onEmptyTrash,
        ),
      },
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isFavorites = state.tab == PhotoTab.favorites;
    final grid = FrameMasonryGrid(
      key: ValueKey(isFavorites ? 'frame-grid-favorites' : 'frame-grid-all'),
      photos: state.visiblePhotos,
      onOpenPhoto: (photo) {
        // 记录浏览范围：详情页的上一张/下一张与幻灯片以该序列为准。
        ref.read(photoBrowseScopeProvider.notifier).set(state.visiblePhotos);
        onOpenPhoto(photo);
      },
      onToggleFavorite: onToggleFavorite,
      emptyMessage: isFavorites ? l10n.photosNoFavorites : l10n.photosNoPhotos,
      emptySubtitle:
          isFavorites ? l10n.photosNoFavoritesHint : l10n.photosNoPhotosHint,
    );
    if (!compact) {
      return grid;
    }
    return RefreshIndicator(
      displacement: 48,
      strokeWidth: 2.5,
      color: context.frameColors.accent,
      onRefresh:
          () => ref.read(photoCenterControllerProvider.notifier).refresh(),
      child: grid,
    );
  }
}
