import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 照片时间线视图，按年→月分组展示
class PhotoTimelineView extends ConsumerStatefulWidget {
  const PhotoTimelineView({
    super.key,
    required this.onOpenPhoto,
    required this.state,
  });

  final ValueChanged<PhotoItem> onOpenPhoto;
  final PhotoCenterState state;

  @override
  ConsumerState<PhotoTimelineView> createState() => _PhotoTimelineViewState();
}

class _PhotoTimelineViewState extends ConsumerState<PhotoTimelineView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(photoCenterControllerProvider.notifier).loadTimeline();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.state.timeline;
    if (timeline == null) {
      if (widget.state.timelinePageError != null) {
        return _TimelineInitialError(message: widget.state.timelinePageError!);
      }
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (timeline.years.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timeline_outlined,
                  size: 64,
                  color: context.photosColors.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).photosNoTimelineData,
                  style: TextStyle(
                    color: context.photosColors.onSurfaceVariant,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).photosNoTimelineHint,
                  style: TextStyle(
                    color: context.photosColors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 800) {
          ref.read(photoCenterControllerProvider.notifier).loadMoreTimeline();
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // 与设计稿一致：按月平铺（November 2024），不再插入年份分组头。
          for (final year in timeline.years)
            for (final month in year.months) ...[
              _MonthHeader(year: year.year, month: month),
              _MonthPhotoGrid(
                photos: month.previewPhotos,
                onOpenPhoto: widget.onOpenPhoto,
              ),
            ],
          SliverToBoxAdapter(child: _TimelineFooter(state: widget.state)),
        ],
      ),
    );
  }
}

class _TimelineInitialError extends ConsumerWidget {
  const _TimelineInitialError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height - 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
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
                        .read(photoCenterControllerProvider.notifier)
                        .loadTimeline(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(AppLocalizations.of(context).coreRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineFooter extends ConsumerWidget {
  const _TimelineFooter({required this.state});

  final PhotoCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMoreTimeline) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.timelinePageError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed:
                () =>
                    ref
                        .read(photoCenterControllerProvider.notifier)
                        .loadMoreTimeline(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              AppLocalizations.of(context).photosLoadMore(
                state.timeline?.monthCount ?? 0,
                state.timelineTotalElements,
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 40);
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.year, required this.month});

  final int year;
  final PhotoMonthGroup month;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Row(
          children: [
            Expanded(
              // 点击月份标题进入该月完整照片列表。
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap:
                    () => context.push('/photos/period/$year/${month.month}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMonthYear(DateTime(year, month.month)),
                        style: TextStyle(
                          color: context.photosColors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.photosColors.primaryContainer
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${month.photoCount}',
                          style: TextStyle(
                            color: context.photosColors.primaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: context.photosColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPhotoGrid extends StatelessWidget {
  const _MonthPhotoGrid({required this.photos, required this.onOpenPhoto});

  final List<PhotoItem> photos;
  final ValueChanged<PhotoItem> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    return SliverToBoxAdapter(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >= 1200
                  ? 6
                  : constraints.maxWidth >= 900
                  ? 5
                  : constraints.maxWidth >= 600
                  ? 4
                  : 3;
          final displayPhotos =
              photos.length > columns * 2
                  ? photos.sublist(0, columns * 2)
                  : photos;
          return GridView.builder(
            itemCount: displayPhotos.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final photo = displayPhotos[index];
              return PhotoGridTile(
                key: ValueKey(photo.id),
                photo: photo,
                onTap: () => onOpenPhoto(photo),
              );
            },
          );
        },
      ),
    );
  }
}
