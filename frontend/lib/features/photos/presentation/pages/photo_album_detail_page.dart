import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
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
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

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

class _AlbumDetailBody extends ConsumerWidget {
  const _AlbumDetailBody({
    required this.album,
    required this.photos,
    required this.albumId,
  });

  final PhotoAlbum album;
  final List<PhotoItem> photos;
  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // 顶部栏
        _AlbumTopBar(
          album: album,
          onBack: () => context.popOrGo('/photos'),
          onDelete: () => _confirmDelete(context, ref),
          onSlideshow: () {
            if (photos.isEmpty) return;
            context.push(
              '/photos/slideshow',
              extra: {'photos': photos, 'initialIndex': 0},
            );
          },
          onShare: () => _showShareDialog(context, ref, albumId),
        ),
        // 照片网格
        Expanded(
          child:
              photos.isEmpty
                  ? AppEmptyState(
                    message: AppLocalizations.of(context).photosAlbumEmpty,
                    icon: Icons.photo_library_outlined,
                  )
                  : CustomScrollView(
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
                              itemCount: photos.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                    childAspectRatio: 1,
                                  ),
                              itemBuilder: (context, index) {
                                final photo = photos[index];
                                return PhotoGridTile(
                                  key: ValueKey(photo.id),
                                  photo: photo,
                                  onTap: () {
                                    // 浏览范围 = 当前相册的照片序列。
                                    ref
                                        .read(photoBrowseScopeProvider.notifier)
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
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: context.photosColors.surfaceContainerHigh,
            title: Text(
              AppLocalizations.of(context).photosDeleteAlbumTitle,
              style: TextStyle(color: context.photosColors.onSurface),
            ),
            content: Text(
              AppLocalizations.of(context).photosDeleteAlbumConfirm(album.name),
              style: TextStyle(color: context.photosColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(context).photosCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.photosColors.danger,
                ),
                child: Text(AppLocalizations.of(context).photosDelete),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .deleteAlbum(albumId);
        if (context.mounted) {
          context.pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).photosDeletedAlbum(album.name),
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

    String expiryOption = 'never';

    final password = await showDialog<String>(
      context: context,
      builder:
          (ctx) => PhotoDialogTextField(
            builder:
                (ctx, passwordController) => StatefulBuilder(
                  builder:
                      (ctx, setDialogState) => AlertDialog(
                        backgroundColor:
                            context.photosColors.surfaceContainerHigh,
                        title: Text(
                          AppLocalizations.of(context).photosShareAlbum,
                          style: TextStyle(
                            color: context.photosColors.onSurface,
                          ),
                        ),
                        content: SizedBox(
                          width: 400,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 密码字段
                              TextField(
                                controller: passwordController,
                                style: TextStyle(
                                  color: context.photosColors.onSurface,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      AppLocalizations.of(
                                        context,
                                      ).photosSharePassword,
                                  hintText:
                                      AppLocalizations.of(
                                        context,
                                      ).photosSharePasswordHint,
                                  hintStyle: TextStyle(
                                    color: context.photosColors.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                obscureText: true,
                              ),
                              SizedBox(height: 12),
                              // 过期时间
                              Text(
                                AppLocalizations.of(context).photosShareExpiry,
                                style: TextStyle(
                                  color: context.photosColors.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SegmentedButton<String>(
                                segments: [
                                  ButtonSegment(
                                    value: '1d',
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).photosShareExpiry1d,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: '7d',
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).photosShareExpiry7d,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: '30d',
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).photosShareExpiry30d,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'never',
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).photosShareExpiryNever,
                                    ),
                                  ),
                                ],
                                selected: {expiryOption},
                                onSelectionChanged:
                                    (v) => setDialogState(
                                      () => expiryOption = v.first,
                                    ),
                                style: ButtonStyle(
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                        if (states.contains(
                                          WidgetState.selected,
                                        )) {
                                          return context
                                              .photosColors
                                              .primaryContainer;
                                        }
                                        return context
                                            .photosColors
                                            .onSurfaceVariant;
                                      }),
                                ),
                              ),
                              // 现有链接
                              if (shares.isNotEmpty) ...[
                                SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  ).photosExistingShareLinks,
                                  style: TextStyle(
                                    color:
                                        context.photosColors.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 8),
                                ...shares.map(
                                  (share) => ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      share.token,
                                      style: TextStyle(
                                        color: context.photosColors.onSurface,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).photosShareAccessCount(
                                        share.accessCount,
                                      ),
                                      style: TextStyle(
                                        color:
                                            context
                                                .photosColors
                                                .onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip:
                                          AppLocalizations.of(
                                            context,
                                          ).coreDelete,
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: context.photosColors.danger,
                                      ),
                                      onPressed: () async {
                                        try {
                                          await ref
                                              .read(
                                                photoCenterControllerProvider
                                                    .notifier,
                                              )
                                              .revokeAlbumShare(share.id);
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx, true);
                                          }
                                        } on Exception catch (error) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(
                                              ctx,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  describeUserFacingError(
                                                    error,
                                                  ).displayMessage,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              AppLocalizations.of(context).photosCancel,
                            ),
                          ),
                          FilledButton(
                            onPressed:
                                () => Navigator.pop(
                                  ctx,
                                  passwordController.text.trim(),
                                ),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  context.photosColors.primaryContainer,
                              foregroundColor:
                                  context.photosColors.onPrimaryContainer,
                            ),
                            child: Text(
                              AppLocalizations.of(context).photosCreateLink,
                            ),
                          ),
                        ],
                      ),
                ),
          ),
    );

    if (password != null && password.isNotEmpty && context.mounted) {
      DateTime? expiresAt;
      if (expiryOption == '1d') {
        expiresAt = DateTime.now().add(const Duration(days: 1));
      } else if (expiryOption == '7d') {
        expiresAt = DateTime.now().add(const Duration(days: 7));
      } else if (expiryOption == '30d') {
        expiresAt = DateTime.now().add(const Duration(days: 30));
      }

      try {
        final link = await ref
            .read(photoCenterControllerProvider.notifier)
            .createAlbumShare(
              albumId,
              password: password.isEmpty ? null : password,
              expiresAt: expiresAt,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).photosShareLinkCreated(link.token),
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
  }

  Future<void> _confirmRemoveFromAlbum(
    BuildContext context,
    WidgetRef ref,
    PhotoItem photo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: context.photosColors.surfaceContainerHigh,
            title: Text(
              AppLocalizations.of(context).photosRemoveFromAlbum,
              style: TextStyle(color: context.photosColors.onSurface),
            ),
            content: Text(
              AppLocalizations.of(
                context,
              ).photosRemoveFromAlbumConfirm(photo.title),
              style: TextStyle(color: context.photosColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(context).photosCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(context).photosRemove),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .removePhotoFromAlbum(albumId: albumId, photoId: photo.id);
        // 页面可能在等待期间被关闭，ref 失效前先终止。
        if (!context.mounted) return;
        // 刷新相册详情
        ref.invalidate(photoAlbumDetailProvider(albumId));
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
class _AlbumTopBar extends StatelessWidget {
  const _AlbumTopBar({
    required this.album,
    required this.onBack,
    required this.onDelete,
    required this.onSlideshow,
    required this.onShare,
  });

  final PhotoAlbum album;
  final VoidCallback onBack;
  final VoidCallback onDelete;
  final VoidCallback onSlideshow;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.photosColors.surfaceContainer.withValues(alpha: 0.70),
        border: Border(
          bottom: BorderSide(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  AppLocalizations.of(
                    context,
                  ).photosAlbumPhotoCountLabel(album.photoCount),
                  style: TextStyle(
                    color: context.photosColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
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
            tooltip: AppLocalizations.of(context).photosDeleteAlbumTooltip,
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: context.photosColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
