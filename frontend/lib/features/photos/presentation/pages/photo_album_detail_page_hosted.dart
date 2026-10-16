part of 'photo_album_detail_page.dart';

/// 相册详情托管形态（样例 AlbumDetail）：photos-overlay 深玻璃表面 +
/// 玻璃横幅 + album-toolbar + album-grid 三列网格（首格保留加卡）。
extension _PhotoAlbumDetailHostedBuild on _AlbumDetailBodyState {
  Widget buildHostedAlbumDetail(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final album = widget.album;
    final photos = _photos;
    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: album.name,
            subtitle: l10n.photosAlbumPhotoCountLabel(album.photoCount),
            backTooltip: l10n.photosBack,
            onBack: () => context.popOrGo('/photos'),
            actions: [
              MobileGlassIconButton(
                tooltip: l10n.photosAddPhotos,
                icon: Icons.add_rounded,
                onPressed: () => unawaited(_openAlbumPhotoPicker()),
              ),
            ],
          ),
          PhotoHostedToolbarRow(
            label: _hostedMetaText(context, l10n),
            actions: [
              if (photos.isNotEmpty)
                PhotoHostedPillButton(
                  icon: Icons.slideshow_outlined,
                  label: l10n.photosSlideshow,
                  onTap: _startSlideshow,
                ),
              PhotoHostedPillButton(
                icon: Icons.share_outlined,
                label: l10n.photosShareAlbum,
                onTap:
                    () => unawaited(_showShareDialog(context, ref, album.id)),
              ),
              PhotoHostedPillButton(
                icon: Icons.delete_outline_rounded,
                label: l10n.photosDelete,
                onTap: () => unawaited(_confirmDelete(context, ref)),
              ),
            ],
          ),
          Expanded(
            child:
                photos.isEmpty
                    ? _hostedEmptyState(context, l10n)
                    : _hostedPhotoGrid(context, l10n),
          ),
        ],
      ),
    );
  }

  /// 工具行说明：相册描述优先，缺省回落到最近更新时间，两者皆无时
  /// 显示照片数（与横幅副题同源，不额外造文案）。
  String _hostedMetaText(BuildContext context, AppLocalizations l10n) {
    final album = widget.album;
    if (album.description.isNotEmpty) {
      return album.description;
    }
    final date = album.updatedAt ?? album.createdAt;
    if (date == null) {
      return l10n.photosAlbumPhotoCountLabel(album.photoCount);
    }
    return DateFormat.yMMMMd(
      Localizations.localeOf(context).toString(),
    ).format(date);
  }

  /// 空相册：样例 .empty-action 形态（EnvEmptyState），主按钮直连选择页。
  Widget _hostedEmptyState(BuildContext context, AppLocalizations l10n) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        EnvEmptyState(
          icon: OmniIcons.image,
          title: l10n.photosAlbumEmpty,
          message: l10n.photosAlbumEmptyHint,
          actionLabel: l10n.photosAddPhotos,
          onAction: () => unawaited(_openAlbumPhotoPicker()),
        ),
      ],
    );
  }

  /// 三列网格：首格加卡，末格按分页状态给加载指示或重试钮。
  Widget _hostedPhotoGrid(BuildContext context, AppLocalizations l10n) {
    final photos = _photos;
    final hasFooter = _isLoadingMore || _loadMoreError != null;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleGridScrollNotification,
      child: PhotoHostedPhotoGrid(
        itemCount: photos.length + 1 + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return PhotoHostedAddTile(
              label: l10n.photosAddPhotos,
              onTap: () => unawaited(_openAlbumPhotoPicker()),
            );
          }
          if (index > photos.length) {
            return _hostedGridFooter(context, l10n);
          }
          final photo = photos[index - 1];
          return PhotoHostedSquareTile(
            key: ValueKey(photo.id),
            photo: photo,
            onTap: () => _openPhotoViewer(photo),
            onLongPress: () => _confirmRemoveFromAlbum(context, ref, photo),
          );
        },
      ),
    );
  }

  Widget _hostedGridFooter(BuildContext context, AppLocalizations l10n) {
    if (_isLoadingMore) {
      return Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.env.inkMuted,
          ),
        ),
      );
    }
    return Center(
      child: PhotoHostedPillButton(
        icon: Icons.refresh_rounded,
        label: l10n.coreRetry,
        minHeight: 35,
        radius: 10,
        iconSize: 15,
        onTap: () => unawaited(_loadMorePhotos()),
      ),
    );
  }
}

/// 托管态相册详情加载骨架：与主页托管加载同形（样例深底 + 占位块）。
class _HostedAlbumLoading extends StatelessWidget {
  const _HostedAlbumLoading();

  @override
  Widget build(BuildContext context) {
    return const MobilePageSurface(
      backdropOpacity: 0.92,
      // 整页首屏只留一处动画指示（此前两块占位各带一个转圈）。
      child: AppLoading(),
    );
  }
}

/// 托管态相册详情错误面：玻璃横幅 + 空态行动（样例 .empty-action）。
class _HostedAlbumError extends StatelessWidget {
  const _HostedAlbumError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: l10n.photosAlbums,
            subtitle: l10n.photosOperationFailed,
            backTooltip: l10n.photosBack,
            onBack: () => context.popOrGo('/photos'),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                EnvEmptyState(
                  icon: OmniIcons.close,
                  title: l10n.photosOperationFailed,
                  message: message,
                  actionLabel: l10n.coreRetry,
                  onAction: onRetry,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 相册二次确认：托管态走底部玻璃面板，工位态保持 Frame 确认窗。
Future<bool> _confirmAlbumAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) {
  if (photosHostedForm(context)) {
    return showMobileConfirmSheet(
      context,
      title: title,
      message: body,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
  }
  return showFrameConfirmDialog(
    context,
    title: title,
    body: body,
    confirmLabel: confirmLabel,
    destructive: destructive,
  );
}
