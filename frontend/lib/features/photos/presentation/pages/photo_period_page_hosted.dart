part of 'photo_period_page.dart';

/// 整月浏览的托管形态（样例 photo-groups 年·月跳转的落点）：玻璃横幅 +
/// `.album-grid` 三列网格 + 网格内加载位，与相册详情托管形态同族。
///
/// 数据、分页与浏览范围口径与桌面形态一致，只换外壳：桌面走 SliverAppBar，
/// 托管走壳层环境表面。
extension _PhotoPeriodPageHosted on _PhotoPeriodPageState {
  Widget buildHostedPeriod(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(photoPeriodProvider);
    final title = MaterialLocalizations.of(
      context,
    ).formatMonthYear(DateTime(widget.year, widget.month));

    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: title,
            subtitle: l10n.photosAlbumPhotoCountLabel(state.totalElements),
            backTooltip: l10n.photosBack,
            onBack: () => context.popOrGo('/photos'),
          ),
          Expanded(child: _hostedPeriodBody(context, l10n, state)),
        ],
      ),
    );
  }

  Widget _hostedPeriodBody(
    BuildContext context,
    AppLocalizations l10n,
    PhotoPeriodState state,
  ) {
    final error = state.error;
    if (error != null && state.photos.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          EnvEmptyState(
            icon: OmniIcons.close,
            title: l10n.photosOperationFailed,
            message: error,
            actionLabel: l10n.coreRetry,
            onAction:
                () => unawaited(
                  ref
                      .read(photoPeriodProvider.notifier)
                      .open(widget.year, widget.month),
                ),
          ),
        ],
      );
    }
    if (state.isInitialLoading) {
      // 整页首屏只留一处动画指示（此前两块占位各带一个转圈）。
      return const AppLoading();
    }
    if (state.photos.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          EnvEmptyState(icon: OmniIcons.image, title: l10n.photosNoPhotos),
        ],
      );
    }
    return _hostedPeriodGrid(context, l10n, state);
  }

  Widget _hostedPeriodGrid(
    BuildContext context,
    AppLocalizations l10n,
    PhotoPeriodState state,
  ) {
    final photos = state.photos;
    final hasFooter = state.hasMore || state.isLoadingMore;
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleHostedScroll,
            child: PhotoHostedPhotoGrid(
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                return PhotoHostedSquareTile(
                  key: ValueKey(photo.id),
                  photo: photo,
                  onTap: () => _openHostedPhoto(context, state, photo),
                );
              },
            ),
          ),
        ),
        // 加载位排在网格之外：网格格只有 1/3 宽，塞进去会顶穿胶囊文案。
        if (hasFooter) _hostedLoadMoreRow(context, l10n, state),
      ],
    );
  }

  Widget _hostedLoadMoreRow(
    BuildContext context,
    AppLocalizations l10n,
    PhotoPeriodState state,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Center(
        child:
            state.isLoadingMore
                ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.env.inkMuted,
                  ),
                )
                : PhotoHostedPillButton(
                  icon: Icons.expand_more_rounded,
                  label: l10n.photosLoadMore(
                    state.photos.length,
                    state.totalElements,
                  ),
                  minHeight: 35,
                  radius: 10,
                  iconSize: 15,
                  onTap:
                      () => unawaited(
                        ref.read(photoPeriodProvider.notifier).loadMore(),
                      ),
                ),
      ),
    );
  }

  /// 浏览范围 = 该月已加载照片，与桌面形态和时间线口径一致。
  void _openHostedPhoto(
    BuildContext context,
    PhotoPeriodState state,
    PhotoItem photo,
  ) {
    ref
        .read(photoBrowseScopeProvider.notifier)
        .set(
          state.photos,
          PhotoBrowseSource.timeline,
          sourceKey: '${widget.year}-${widget.month}',
        );
    context.push('/photos/${photo.id}');
  }

  bool _handleHostedScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification.metrics.extentAfter >= 640) {
      return false;
    }
    // 滚动通知可能处于 layout 阶段，延迟加载避免 Navigator/Focus 断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(photoPeriodProvider.notifier).loadMore());
    });
    return false;
  }
}
