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
      // 视图切换会整棵替换内容，退场子树排除语义。
      layoutBuilder: excludeExitingSemanticsStack,
      child: switch (state.frameView) {
        FrameView.grid || FrameView.favorites => _buildGrid(context, ref),
        FrameView.timeline => _compactRefreshable(
          ref,
          () => ref
              .read(photoCenterControllerProvider.notifier)
              .loadTimeline(force: true),
          PhotoTimelineView(
            key: const ValueKey('frame-timeline'),
            onOpenPhoto: (photo) {
              // 时间线的浏览/幻灯片范围限定为点击照片所在月份，
              // 与 period 页口径一致（sourceKey = 年-月）。
              final timeline = state.timeline;
              if (timeline != null) {
                final month = _findTimelineMonthOf(timeline, photo.id);
                if (month != null) {
                  ref
                      .read(photoBrowseScopeProvider.notifier)
                      .set(
                        month.$2.previewPhotos,
                        PhotoBrowseSource.timeline,
                        sourceKey: '${month.$1}-${month.$2.month}',
                      );
                }
              }
              onOpenPhoto(photo);
            },
            state: state,
          ),
        ),
        FrameView.locations => _compactRefreshable(
          ref,
          () => ref.read(photoCenterControllerProvider.notifier).refresh(),
          FrameLocationsView(
            key: const ValueKey('frame-locations'),
            onOpenPhoto: onOpenPhoto,
            onToggleFavorite: onToggleFavorite,
          ),
        ),
        FrameView.tags => _compactRefreshable(
          ref,
          () => ref.read(photoCenterControllerProvider.notifier).refresh(),
          FrameTagsView(
            key: const ValueKey('frame-tags'),
            onOpenPhoto: onOpenPhoto,
            onToggleFavorite: onToggleFavorite,
          ),
        ),
        FrameView.albums => _compactRefreshable(
          ref,
          () => ref.read(photoCenterControllerProvider.notifier).refresh(),
          FrameAlbumsView(
            key: const ValueKey('frame-albums'),
            albums: state.albums,
            onOpenAlbum: onOpenAlbum,
            onDeleteAlbum: onDeleteAlbum,
            onCreateAlbum: onCreateAlbum,
          ),
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

  /// 紧凑档为视图包下拉刷新；宽屏沿用原布局。
  Widget _compactRefreshable(
    WidgetRef ref,
    Future<void> Function() onRefresh,
    Widget child,
  ) {
    if (!compact) {
      return child;
    }
    return Builder(
      builder: (context) {
        return RefreshIndicator(
          displacement: 48,
          strokeWidth: 2.5,
          color: context.frameColors.accent,
          onRefresh: onRefresh,
          child: child,
        );
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
        ref
            .read(photoBrowseScopeProvider.notifier)
            .set(
              state.visiblePhotos,
              isFavorites
                  ? PhotoBrowseSource.favorites
                  : PhotoBrowseSource.library,
            );
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

/// 在时间线中定位照片所属的 (年, 月分组)；跨月唯一，找不到返回 null。
(int, PhotoMonthGroup)? _findTimelineMonthOf(
  PhotoTimeline timeline,
  String photoId,
) {
  for (final year in timeline.years) {
    for (final month in year.months) {
      if (month.previewPhotos.any((item) => item.id == photoId)) {
        return (year.year, month);
      }
    }
  }
  return null;
}
