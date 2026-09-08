import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 全部照片浏览页 — 从首页 "View All" 进入
class PhotoBrowsePage extends ConsumerWidget {
  const PhotoBrowsePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(photoCenterControllerProvider);

    return Scaffold(
      backgroundColor: context.photosColors.surface,
      body: stateAsync.when(
        data: (data) {
          final photos = data.photos;
          return RefreshIndicator(
            displacement: 40,
            strokeWidth: 2.5,
            color: context.photosColors.primaryContainer,
            onRefresh: () async {
              await ref.read(photoCenterControllerProvider.notifier).refresh();
              await Future<void>.delayed(const Duration(milliseconds: 200));
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 640) {
                  unawaited(
                    ref
                        .read(photoCenterControllerProvider.notifier)
                        .loadMoreVisiblePhotos(),
                  );
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 顶栏
                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    leading: IconButton(
                      onPressed: () => context.popOrGo('/photos'),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: context.photosColors.onSurfaceVariant,
                      ),
                      tooltip: AppLocalizations.of(context).photosBack,
                    ),
                    title: Text(
                      AppLocalizations.of(context).photosAllPhotos,
                      style: TextStyle(
                        color: context.photosColors.onSurface,
                        fontSize: AppTypography.titleLarge,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    flexibleSpace: Container(
                      color: context.photosColors.surface.withValues(
                        alpha: 0.78,
                      ),
                    ),
                  ),
                  // 照片网格
                  if (photos.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context).photosNoPhotos,
                          style: TextStyle(
                            color: context.photosColors.onSurfaceVariant,
                            fontSize: AppTypography.bodyLarge,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 1,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final photo = photos[index];
                          return PhotoGridTile(
                            key: ValueKey(photo.id),
                            photo: photo,
                            onTap: () {
                              // 浏览范围 = 全部照片（v5.1：所有入口显式写入）。
                              ref
                                  .read(photoBrowseScopeProvider.notifier)
                                  .set(photos, PhotoBrowseSource.library);
                              context.push('/photos/${photo.id}');
                            },
                          );
                        }, childCount: photos.length),
                      ),
                    ),
                  if (data.hasMorePhotos || data.isLoadingMorePhotos)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Center(
                          child:
                              data.isLoadingMorePhotos
                                  ? const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : TextButton(
                                    onPressed:
                                        () =>
                                            ref
                                                .read(
                                                  photoCenterControllerProvider
                                                      .notifier,
                                                )
                                                .loadMoreVisiblePhotos(),
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).photosLoadMore(
                                        photos.length,
                                        data.photoTotalElements,
                                      ),
                                    ),
                                  ),
                        ),
                      ),
                    ),
                  if (data.photoPageError case final error?)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        error:
            (error, stackTrace) => AppErrorView(
              message: describeUserFacingError(error).displayMessage,
              onRetry: () => ref.invalidate(photoCenterControllerProvider),
            ),
        loading: () => const AppLoading.grid(),
      ),
    );
  }
}
