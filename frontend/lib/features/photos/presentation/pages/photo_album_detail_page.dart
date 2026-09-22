import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/core/widgets/app_empty_state.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_dialog.dart';

/// 相册详情页面
class PhotoAlbumDetailPage extends ConsumerWidget {
  const PhotoAlbumDetailPage({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(photoAlbumDetailProvider(albumId));
    return Scaffold(
      backgroundColor: context.photosColors.surface,
      body: detailAsync.when(
        data:
            (detail) => _AlbumDetailBody(
              album: detail.album,
              photos: detail.photos,
              albumId: albumId,
            ),
        error:
            (error, stackTrace) => AppErrorView(
              message: describeUserFacingError(error).displayMessage,
              onRetry: () => ref.invalidate(photoAlbumDetailProvider(albumId)),
            ),
        loading: () => const AppLoading.grid(),
      ),
    );
  }
}

class _AlbumDetailBody extends ConsumerStatefulWidget {
  const _AlbumDetailBody({
    required this.album,
    required this.photos,
    required this.albumId,
  });

  final PhotoAlbum album;
  final List<PhotoItem> photos;
  final String albumId;

  @override
  ConsumerState<_AlbumDetailBody> createState() => _AlbumDetailBodyState();
}

class _AlbumDetailBodyState extends ConsumerState<_AlbumDetailBody> {
  late List<PhotoItem> _photos;
  int _page = 0;
  bool _isLoadingMore = false;
  Object? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _photos = List<PhotoItem>.of(widget.photos);
  }

  @override
  void didUpdateWidget(covariant _AlbumDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 详情 Provider 刷新（增删照片后）以服务端首页为准并重置分页。
    if (oldWidget.albumId != widget.albumId ||
        !identical(oldWidget.photos, widget.photos)) {
      _photos = List<PhotoItem>.of(widget.photos);
      _page = 0;
      _isLoadingMore = false;
      _loadMoreError = null;
    }
  }

  bool get _hasMore => _photos.length < widget.album.photoCount;

  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final nextPage = _page + 1;
      final result = await ref
          .read(photoCenterControllerProvider.notifier)
          .listAlbumPhotos(albumId: widget.albumId, page: nextPage);
      if (!mounted) {
        return;
      }
      final existingIds = _photos.map((photo) => photo.id).toSet();
      setState(() {
        _page = result.page;
        _photos = [
          ..._photos,
          for (final photo in result.items)
            if (existingIds.add(photo.id)) photo,
        ];
        _isLoadingMore = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final album = widget.album;
    final albumId = widget.albumId;
    return Column(
      children: [
        // 顶部栏
        _AlbumTopBar(
          album: album,
          onBack: () => context.popOrGo('/photos'),
          onDelete: () => _confirmDelete(context, ref),
          onSlideshow: () {
            if (photos.isEmpty) return;
            // 声明影集来源：缺省会被按全库语义处理，播放列表在 build 时
            // 被全库照片整体替换，越出影集范围。
            context.push(
              '/photos/slideshow',
              extra: {
                'photos': photos,
                'initialIndex': 0,
                'source': PhotoBrowseSource.album,
                'sourceKey': albumId,
              },
            );
          },
          onShare: () => _showShareDialog(context, ref, albumId),
          onAddPhotos: () async {
            await context.push('/photos/albums/$albumId/add');
            // 选择页返回后刷新详情，无论是否新增都以服务端数据为准。
            ref.invalidate(photoAlbumDetailProvider(albumId));
          },
        ),
        // 照片网格
        Expanded(
          child:
              photos.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppEmptyState(
                          message:
                              AppLocalizations.of(context).photosAlbumEmpty,
                          icon: Icons.photo_library_outlined,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            await context.push('/photos/albums/$albumId/add');
                            ref.invalidate(photoAlbumDetailProvider(albumId));
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            AppLocalizations.of(context).photosAddPhotos,
                          ),
                        ),
                      ],
                    ),
                  )
                  : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth != 0 ||
                          notification.metrics.axis != Axis.vertical ||
                          notification.metrics.extentAfter >= 480) {
                        return false;
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        unawaited(_loadMorePhotos());
                      });
                      return false;
                    },
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final columns =
                                  constraints.crossAxisExtent >= 1600
                                      ? 7
                                      : constraints.crossAxisExtent >= 1300
                                      ? 6
                                      : constraints.crossAxisExtent >= 1000
                                      ? 5
                                      : constraints.crossAxisExtent >= 700
                                      ? 4
                                      : constraints.crossAxisExtent >= 500
                                      ? 3
                                      : 2;
                              return SliverGrid.builder(
                                itemCount:
                                    photos.length +
                                    1 +
                                    (_isLoadingMore || _loadMoreError != null
                                        ? 1
                                        : 0),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 1,
                                    ),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _AddPhotoTile(
                                      onTap: () async {
                                        await context.push(
                                          '/photos/albums/$albumId/add',
                                        );
                                        ref.invalidate(
                                          photoAlbumDetailProvider(albumId),
                                        );
                                      },
                                    );
                                  }
                                  if (index == photos.length + 1) {
                                    return Center(
                                      child:
                                          _isLoadingMore
                                              ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                              : TextButton(
                                                onPressed:
                                                    () => unawaited(
                                                      _loadMorePhotos(),
                                                    ),
                                                child: Text(
                                                  AppLocalizations.of(
                                                    context,
                                                  ).photosOperationFailed,
                                                ),
                                              ),
                                    );
                                  }
                                  final photo = photos[index - 1];
                                  return PhotoGridTile(
                                    key: ValueKey(photo.id),
                                    photo: photo,
                                    onTap: () {
                                      // 浏览范围 = 当前已加载的相册照片序列。
                                      ref
                                          .read(
                                            photoBrowseScopeProvider.notifier,
                                          )
                                          .set(
                                            photos,
                                            PhotoBrowseSource.album,
                                            sourceKey: album.id,
                                          );
                                      context.push('/photos/${photo.id}');
                                    },
                                    onLongPress:
                                        () => _confirmRemoveFromAlbum(
                                          context,
                                          ref,
                                          photo,
                                        ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosDeleteAlbumTitle,
      body: l10n.photosDeleteAlbumConfirm(widget.album.name),
      confirmLabel: l10n.photosDelete,
      destructive: true,
    );
    if (confirmed && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .deleteAlbum(widget.albumId);
        if (context.mounted) {
          context.pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                ).photosDeletedAlbum(widget.album.name),
              ),
            ),
          );
        }
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosDeleteFailed),
            ),
          );
        }
      }
    }
  }

  Future<void> _showShareDialog(
    BuildContext context,
    WidgetRef ref,
    String albumId,
  ) async {
    // 先加载现有分享链接
    List<PhotoShareLink> shares = [];
    try {
      shares = await ref
          .read(photoCenterControllerProvider.notifier)
          .listAlbumShares(albumId);
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(describeUserFacingError(error).displayMessage),
          ),
        );
      }
    }

    if (!context.mounted) return;

    final result = await showPhotoShareDialog(
      context,
      title: AppLocalizations.of(context).photosShareAlbum,
      shares: shares,
      onRevoke:
          (shareId) => ref
              .read(photoCenterControllerProvider.notifier)
              .revokeAlbumShare(shareId),
      onRevokeAll:
          () => ref
              .read(photoCenterControllerProvider.notifier)
              .revokeAllAlbumShares(albumId),
    );

    if (!context.mounted) return;
    if (result == null) return;
    // 密码留空 = 显式创建无密码链接。
    final (password, expiryOption) = result;
    final expiresAt = resolveShareExpiry(expiryOption);

    try {
      final link = await ref
          .read(photoCenterControllerProvider.notifier)
          .createAlbumShare(
            albumId,
            password: password.isEmpty ? null : password,
            expiresAt: expiresAt,
          );
      final baseUrl = await ref.read(webShareBaseUrlResolverProvider).resolve();
      if (context.mounted) {
        // 影集分享走 SPA hash 路由（/shared/photos/:token）；基址取
        // 服务器下发的对外 Web 地址，未配置时回退到客户端推导值。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).photosShareLinkCreated(
                '$baseUrl/#/shared/photos/${link.token}',
              ),
            ),
          ),
        );
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).photosShareLinkFailed),
          ),
        );
      }
    }
  }

  Future<void> _confirmRemoveFromAlbum(
    BuildContext context,
    WidgetRef ref,
    PhotoItem photo,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosRemoveFromAlbum,
      body: l10n.photosRemoveFromAlbumConfirm(photo.title),
      confirmLabel: l10n.photosRemove,
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .removePhotoFromAlbum(albumId: widget.albumId, photoId: photo.id);
        // 页面可能在等待期间被关闭，ref 失效前先终止。
        if (!context.mounted) return;
        // 刷新相册详情
        ref.invalidate(photoAlbumDetailProvider(widget.albumId));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                ).photosRemovedFromAlbum(photo.title),
              ),
            ),
          );
        }
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosOperationFailed),
            ),
          );
        }
      }
    }
  }
}

/// 相册详情顶部栏
/// 网格首格的“添加照片”卡片，点击进入候选照片选择页。
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: context.photosColors.surfaceContainerHigh.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: context.photosColors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).photosAddPhotos,
              style: TextStyle(
                color: context.photosColors.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumTopBar extends StatelessWidget {
  const _AlbumTopBar({
    required this.album,
    required this.onBack,
    required this.onDelete,
    required this.onSlideshow,
    required this.onShare,
    required this.onAddPhotos,
  });

  final PhotoAlbum album;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final VoidCallback onSlideshow;
  final VoidCallback onShare;
  final VoidCallback onAddPhotos;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.photosColors.surfaceContainer.withValues(alpha: 0.70),
        border: Border(
          bottom: BorderSide(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  tooltip: AppLocalizations.of(context).photosBack,
                  onPressed: onBack,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: context.photosColors.onSurface,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.photosColors.onSurface,
                          fontSize: AppTypography.titleMedium,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).photosAlbumPhotoCountLabel(album.photoCount),
                        style: TextStyle(
                          color: context.photosColors.onSurfaceVariant,
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).photosAddPhotos,
                  onPressed: onAddPhotos,
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    color: context.photosColors.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).photosSlideshow,
                  onPressed: onSlideshow,
                  icon: Icon(
                    Icons.slideshow_outlined,
                    color: context.photosColors.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).photosShareAlbum,
                  onPressed: onShare,
                  icon: Icon(
                    Icons.share_outlined,
                    color: context.photosColors.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip:
                      AppLocalizations.of(context).photosDeleteAlbumTooltip,
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: context.photosColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
