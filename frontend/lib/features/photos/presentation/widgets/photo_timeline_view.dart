import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
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
      return _TimelinePlaceholder(child: const CircularProgressIndicator());
    }
    if (timeline.years.isEmpty) {
      return _TimelinePlaceholder(
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
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).photosNoTimelineHint,
              style: TextStyle(
                color: context.photosColors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical ||
            notification.metrics.extentAfter >= 800) {
          return false;
        }
        // 滚动通知可能落在 layout 阶段；延迟到帧末再改状态，避免 Navigator/Focus 断言。
        _scheduleLoadMoreTimeline();
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
              SliverToBoxAdapter(
                child: _MonthHeader(year: year.year, month: month),
              ),
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

  void _scheduleLoadMoreTimeline() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(photoCenterControllerProvider.notifier).loadMoreTimeline();
    });
  }
}

class _TimelineInitialError extends ConsumerWidget {
  const _TimelineInitialError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TimelinePlaceholder(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.photosColors.onSurfaceVariant,
              fontSize: AppTypography.bodyLarge,
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
    );
  }
}

/// 视口占位：按可用高度撑满以下拉刷新，内容垂直居中；
/// 不再用「屏高-120」猜测 chrome 占用。
class _TimelinePlaceholder extends StatelessWidget {
  const _TimelinePlaceholder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.hasBoundedHeight ? constraints.maxHeight : 480.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: SizedBox(height: height, child: Center(child: child)),
        );
      },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Expanded(
            // 点击月份标题进入该月完整照片列表。
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openPeriod(context),
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
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.photosColors.primaryContainer.withValues(
                          alpha: 0.14,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${month.photoCount}',
                        style: TextStyle(
                          color: context.photosColors.primaryContainer,
                          fontSize: AppTypography.bodySmall,
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
    );
  }

  void _openPeriod(BuildContext context) {
    final target = '/photos/period/$year/${month.month}';
    // 避免在手势/LayoutBuilder 回调中同步 push，降低 Navigator/Focus 重建断言风险。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      context.push(target);
    });
  }
}

class _MonthPhotoGrid extends StatelessWidget {
  const _MonthPhotoGrid({required this.photos, required this.onOpenPhoto});

  final List<PhotoItem> photos;
  final ValueChanged<PhotoItem> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    // slivers 槽位只能接受 RenderSliver；须用 SliverLayoutBuilder，
    // 不能用 LayoutBuilder（RenderBox），否则 Viewport 协议不匹配并连带 Focus 断言。
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns =
            width >= 1200
                ? 6
                : width >= 900
                ? 5
                : width >= 600
                ? 4
                : 3;
        final displayPhotos =
            photos.length > columns * 2
                ? photos.sublist(0, columns * 2)
                : photos;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final photo = displayPhotos[index];
              return PhotoGridTile(
                key: ValueKey(photo.id),
                photo: photo,
                onTap: () => onOpenPhoto(photo),
              );
            }, childCount: displayPhotos.length),
          ),
        );
      },
    );
  }
}
