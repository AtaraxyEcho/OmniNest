import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 指定年月的照片浏览页 — 从时间线月份进入。
class PhotoPeriodPage extends ConsumerStatefulWidget {
  const PhotoPeriodPage({required this.year, required this.month, super.key});

  final int year;
  final int month;

  @override
  ConsumerState<PhotoPeriodPage> createState() => _PhotoPeriodPageState();
}

class _PhotoPeriodPageState extends ConsumerState<PhotoPeriodPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(photoPeriodProvider.notifier).open(widget.year, widget.month);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoPeriodProvider);
    final photos = state.photos;
    final title = MaterialLocalizations.of(
      context,
    ).formatMonthYear(DateTime(widget.year, widget.month));

    return Scaffold(
      backgroundColor: context.photosColors.surface,
      body: RefreshIndicator(
        displacement: 40,
        strokeWidth: 2.5,
        color: context.photosColors.primaryContainer,
        onRefresh:
            () => ref
                .read(photoPeriodProvider.notifier)
                .open(widget.year, widget.month),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 640) {
              unawaited(ref.read(photoPeriodProvider.notifier).loadMore());
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
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
                  title,
                  style: TextStyle(
                    color: context.photosColors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                flexibleSpace: Container(
                  color: context.photosColors.surface.withValues(alpha: 0.78),
                ),
              ),
              if (state.error != null && photos.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.photosColors.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed:
                              () => ref
                                  .read(photoPeriodProvider.notifier)
                                  .open(widget.year, widget.month),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(AppLocalizations.of(context).coreRetry),
                        ),
                      ],
                    ),
                  ),
                )
              else if (state.isInitialLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (photos.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context).photosNoPhotos,
                      style: TextStyle(
                        color: context.photosColors.onSurfaceVariant,
                        fontSize: 14,
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
                          // 浏览范围 = 已加载的该月照片（时间线口径）。
                          ref
                              .read(photoBrowseScopeProvider.notifier)
                              .set(
                                photos,
                                PhotoBrowseSource.timeline,
                                sourceKey: '${widget.year}-${widget.month}',
                              );
                          context.push('/photos/${photo.id}');
                        },
                      );
                    }, childCount: photos.length),
                  ),
                ),
              if (state.hasMore || state.isLoadingMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Center(
                      child:
                          state.isLoadingMore
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
                                            .read(photoPeriodProvider.notifier)
                                            .loadMore(),
                                child: Text(
                                  AppLocalizations.of(context).photosLoadMore(
                                    photos.length,
                                    state.totalElements,
                                  ),
                                ),
                              ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
