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
    this.onToggleFavorite,
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

  /// null 时收藏入口整体隐藏（无 activity:write 的角色）。
  final ValueChanged<PhotoItem>? onToggleFavorite;
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
          MobileShellScope.isHosted(context)
              ? _HostedTimelineBody(
                key: const ValueKey('frame-timeline'),
                state: state,
              )
              : PhotoTimelineView(
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
            hasMore: state.albumsHasMore,
            isLoadingMore: state.isLoadingMoreAlbums,
            onLoadMore:
                () =>
                    ref
                        .read(photoCenterControllerProvider.notifier)
                        .loadMoreAlbums(),
          ),
        ),
        FrameView.trash => FrameTrashView(
          key: const ValueKey('frame-trash'),
          photos: state.trashPhotos,
          totalCount: state.trashTotalElements,
          isLoading: state.isLoadingTrash,
          errorMessage: state.trashPageError,
          onRestore: onRestoreFromTrash,
          onDeleteForever: onDeleteForeverFromTrash,
          onEmptyTrash: onEmptyTrash,
          hasMore: state.hasMoreTrash,
          isLoadingMore: state.isLoadingMoreTrash,
          onLoadMore:
              () =>
                  ref
                      .read(photoCenterControllerProvider.notifier)
                      .loadMoreTrash(),
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

  /// 托管 Library 段主体（样例定位修订）：工具行 + 全图片瀑布流本体，
  /// 多选反馈（点击切换/长按进入）与滚动加载由网格内置承载。
  Widget _hostedLibraryBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final photos = state.visiblePhotos;
    final notifier = ref.read(photoCenterControllerProvider.notifier);
    return Column(
      children: [
        // 样例 .photo-toolbar：计数（选择态显示已选数）+ 选择胶囊
        // （选中态酸绿描边，选择态追加全选）。
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.isSelectionMode
                      ? l10n.photosSelectedCount(state.selectedPhotoIds.length)
                      : l10n.photosHostedToolbarCount(state.photoTotalElements),
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.inkMuted,
                  ),
                ),
              ),
              if (state.isSelectionMode) ...[
                _ToolbarPillButton(
                  icon: Icons.check_rounded,
                  label: l10n.photosSelectAll,
                  onPressed: () => notifier.toggleSelectAllVisible(),
                ),
                const SizedBox(width: 7),
              ],
              _ToolbarPillButton(
                icon: Icons.checklist_rounded,
                label:
                    state.isSelectionMode
                        ? l10n.photosDone
                        : l10n.photosSelectPhotos,
                active: state.isSelectionMode,
                onPressed: () => notifier.toggleSelectionMode(),
              ),
            ],
          ),
        ),
        Expanded(
          child: FrameMasonryGrid(
            key: const ValueKey('frame-grid-hosted'),
            photos: photos,
            onOpenPhoto: (photo) {
              ref
                  .read(photoBrowseScopeProvider.notifier)
                  .set(photos, PhotoBrowseSource.library);
              onOpenPhoto(photo);
            },
            onToggleFavorite: onToggleFavorite,
            emptyMessage: l10n.photosNoPhotos,
            emptySubtitle: l10n.photosNoPhotosHint,
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isFavorites = state.tab == PhotoTab.favorites;
    // 取不到不等于没有：集合请求失败时列表为空，继续渲染空状态会把
    // "加载失败"说成"还没有照片"，用户以为数据丢了。
    if (state.visiblePhotos.isEmpty && state.errorMessage != null) {
      return AppErrorView(
        message: state.errorMessage!,
        onRetry:
            () => ref.read(photoCenterControllerProvider.notifier).refresh(),
      );
    }
    // 托管 Library 段（样例 photos-overlay Library）：工具行 + 马赛克 +
    // 相册轨 + 时刻行；收藏页签与桌面仍走瀑布网格。
    if (compact &&
        !isFavorites &&
        MobileShellScope.isHosted(context) &&
        state.frameView == FrameView.grid) {
      return _hostedLibraryBody(context, ref, l10n);
    }
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

/// 工具行胶囊钮（样例 .photo-toolbar button：r11·白 6% 底·白 9% 描边·
/// 图标 15 + 9px 文字；选中态酸绿底 10% + 酸绿 38% 描边）。
class _ToolbarPillButton extends StatelessWidget {
  const _ToolbarPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          active
              ? context.env.accentInk.withValues(alpha: 0.1)
              : context.env.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color:
              active
                  ? context.env.accentInk.withValues(alpha: 0.38)
                  : context.env.line09,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              Icon(icon, size: 15, color: context.env.ink),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9, // ignore: font_size_whitelist
                  color: context.env.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 托管态时间线（样例 Timeline 档）：月份眉标 + 三列方形照片网格，
/// 瓦片点击进入该月范围的查看器。
class _HostedTimelineBody extends ConsumerWidget {
  const _HostedTimelineBody({required this.state, super.key});

  final PhotoCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = state.timeline;
    if (timeline == null) {
      return Center(
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(context.env.inkMuted),
        ),
      );
    }
    final languageCode = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        for (final year in timeline.years)
          for (final month in year.months) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
              child: Text(
                DateFormat.yMMMM(
                  languageCode,
                ).format(DateTime(year.year, month.month)).toUpperCase(),
                style: TextStyle(
                  fontSize: 9, // ignore: font_size_whitelist
                  height: 1.45,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: context.env.groupLabelInk,
                ),
              ),
            ),
            SamplePhotoGrid(
              tiles: [
                for (final photo in month.previewPhotos)
                  SamplePhotoTile(
                    imageUrl: photo.coverUrl ?? photo.sourceUrl,
                    onTap: () {
                      ref
                          .read(photoBrowseScopeProvider.notifier)
                          .set(
                            month.previewPhotos,
                            PhotoBrowseSource.timeline,
                            sourceKey: '${year.year}-${month.month}',
                          );
                      context.push('/photos/${photo.id}');
                    },
                  ),
              ],
            ),
            // 月份只下发预览，整月内容走 period 页；仅在确有剩余时给跳转。
            if (month.photoCount > month.previewPhotos.length)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PhotoHostedPillButton(
                    icon: Icons.expand_more_rounded,
                    label: AppLocalizations.of(
                      context,
                    ).photosViewAllMonth(month.photoCount),
                    onTap:
                        () => unawaited(
                          context.push(
                            '/photos/period/${year.year}/${month.month}',
                          ),
                        ),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}
