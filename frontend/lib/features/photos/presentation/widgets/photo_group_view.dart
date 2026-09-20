import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 照片分组视图，支持按时间/位置/格式/标签分组
class PhotoGroupView extends ConsumerStatefulWidget {
  const PhotoGroupView({
    super.key,
    required this.onOpenPhoto,
    required this.state,
  });

  final ValueChanged<PhotoItem> onOpenPhoto;
  final PhotoCenterState state;

  @override
  ConsumerState<PhotoGroupView> createState() => _PhotoGroupViewState();
}

class _PhotoGroupViewState extends ConsumerState<PhotoGroupView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final currentGroupBy = widget.state.groupBy;
        ref
            .read(photoCenterControllerProvider.notifier)
            .loadGroups(currentGroupBy);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.state.groups;
    final groupBy = widget.state.groupBy;

    return Column(
      children: [
        // 分组维度切换
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  GroupBy.values
                      .map(
                        (by) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              photoGroupByLabel(
                                AppLocalizations.of(context),
                                by,
                              ),
                            ),
                            selected: groupBy == by,
                            onSelected: (selected) {
                              if (selected) {
                                ref
                                    .read(
                                      photoCenterControllerProvider.notifier,
                                    )
                                    .loadGroups(by);
                              }
                            },
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ),
        // 分组列表
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0 ||
                  notification.metrics.axis != Axis.vertical ||
                  notification.metrics.extentAfter >= 800) {
                return false;
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ref
                    .read(photoCenterControllerProvider.notifier)
                    .loadMoreGroups();
              });
              return false;
            },
            child:
                groups == null ||
                        (groups.isEmpty && widget.state.groupPageError != null)
                    ? _GroupInitialState(state: widget.state)
                    : groups.isEmpty && widget.state.isLoadingGroups
                    ? const Center(child: CircularProgressIndicator())
                    : groups.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.group_work_outlined,
                            size: 64,
                            color: context.photosColors.onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                          SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context).photosNoGroupData,
                            style: TextStyle(
                              color: context.photosColors.onSurfaceVariant,
                              fontSize: AppTypography.titleMedium,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 40),
                      itemCount: groups.length + 1,
                      itemBuilder: (context, index) {
                        if (index == groups.length) {
                          return _GroupFooter(state: widget.state);
                        }
                        final group = groups[index];
                        return _GroupSection(
                          group: group,
                          onOpenPhoto: widget.onOpenPhoto,
                        );
                      },
                    ),
          ),
        ),
      ],
    );
  }
}

class _GroupInitialState extends ConsumerWidget {
  const _GroupInitialState({required this.state});

  final PhotoCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = state.groupPageError;
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error,
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
                    .loadGroups(state.groupBy, force: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(AppLocalizations.of(context).coreRetry),
          ),
        ],
      ),
    );
  }
}

class _GroupFooter extends ConsumerWidget {
  const _GroupFooter({required this.state});

  final PhotoCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMoreGroups) {
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
    if (state.groupPageError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed:
                () =>
                    ref
                        .read(photoCenterControllerProvider.notifier)
                        .loadMoreGroups(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              AppLocalizations.of(context).photosLoadMore(
                state.groups?.length ?? 0,
                state.groupTotalElements,
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group, required this.onOpenPhoto});

  final PhotoGroup group;
  final ValueChanged<PhotoItem> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Text(
                group.groupKey,
                style: TextStyle(
                  color: context.photosColors.onSurface,
                  fontSize: AppTypography.titleMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.photosColors.primaryContainer.withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.photoCount}',
                  style: TextStyle(
                    color: context.photosColors.primaryContainer,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
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
                group.photos.length > 12
                    ? group.photos.sublist(0, 12)
                    : group.photos;
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
      ],
    );
  }
}
