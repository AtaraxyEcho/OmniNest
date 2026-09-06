import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 影集"添加照片"选择页：分页候选集 + 多选 + 提交。
class PhotoAlbumPhotoPickerPage extends ConsumerStatefulWidget {
  const PhotoAlbumPhotoPickerPage({required this.albumId, super.key});

  final String albumId;

  @override
  ConsumerState<PhotoAlbumPhotoPickerPage> createState() =>
      _PhotoAlbumPhotoPickerPageState();
}

class _PhotoAlbumPhotoPickerPageState
    extends ConsumerState<PhotoAlbumPhotoPickerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(photoAlbumPickerProvider.notifier).open(widget.albumId);
      }
    });
  }

  Future<void> _submit() async {
    final selectedCount = ref.read(photoAlbumPickerProvider).selectedIds.length;
    final success = await ref.read(photoAlbumPickerProvider.notifier).submit();
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.photosPickerAddSuccess(selectedCount))),
      );
      if (mounted) {
        context.pop();
      }
    } else {
      final error = ref.read(photoAlbumPickerProvider).error;
      messenger.showSnackBar(
        SnackBar(content: Text(error ?? l10n.photosAddPhotos)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoAlbumPickerProvider);
    final candidates = state.candidates;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: context.photosColors.surface,
      body: Column(
        children: [
          // 顶部栏：返回 + 标题 + 已选计数
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.photosColors.surfaceContainer.withValues(
                alpha: 0.70,
              ),
              border: Border(
                bottom: BorderSide(
                  color: context.photosColors.outlineVariant.withValues(
                    alpha: 0.32,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.photosBack,
                  onPressed: () => context.pop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: context.photosColors.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.photosAddPhotos,
                    style: TextStyle(
                      color: context.photosColors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  l10n.photosPickerAddCount(state.selectedIds.length),
                  style: TextStyle(
                    color: context.photosColors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // 候选网格
          Expanded(
            child:
                state.error != null && candidates.isEmpty
                    ? AppErrorView(
                      message: state.error!,
                      onRetry:
                          () => ref
                              .read(photoAlbumPickerProvider.notifier)
                              .open(widget.albumId),
                    )
                    : state.isInitialLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.isEmpty
                    ? Center(
                      child: Text(
                        l10n.photosPickerNoCandidates,
                        style: TextStyle(
                          color: context.photosColors.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    )
                    : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 640) {
                          unawaited(
                            ref
                                .read(photoAlbumPickerProvider.notifier)
                                .loadMore(),
                          );
                        }
                        return false;
                      },
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth >= 1600
                                  ? 7
                                  : constraints.maxWidth >= 1300
                                  ? 6
                                  : constraints.maxWidth >= 1000
                                  ? 5
                                  : constraints.maxWidth >= 700
                                  ? 4
                                  : constraints.maxWidth >= 500
                                  ? 3
                                  : 2;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 1,
                                ),
                            itemCount:
                                candidates.length +
                                (state.hasMore || state.isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= candidates.length) {
                                return const Center(
                                  child: SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final photo = candidates[index];
                              final selected = state.selectedIds.contains(
                                photo.id,
                              );
                              return _CandidateTile(
                                photo: photo,
                                selected: selected,
                                onTap:
                                    () => ref
                                        .read(photoAlbumPickerProvider.notifier)
                                        .toggle(photo.id),
                              );
                            },
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
      // 底部提交栏
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          decoration: BoxDecoration(
            color: context.photosColors.surfaceContainer.withValues(alpha: 0.9),
            border: Border(
              top: BorderSide(
                color: context.photosColors.outlineVariant.withValues(
                  alpha: 0.32,
                ),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.error ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed:
                    state.selectedIds.isEmpty || state.isSubmitting
                        ? null
                        : _submit,
                icon:
                    state.isSubmitting
                        ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  l10n.photosPickerAddCount(state.selectedIds.length),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 候选照片格：点击切换选中，选中时叠加对勾与描边。
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.photo,
    required this.selected,
    required this.onTap,
  });

  final PhotoItem photo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoGridTile(photo: photo, onTap: onTap),
          if (selected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.photosColors.primaryContainer,
                  width: 3,
                ),
              ),
            ),
          if (selected)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: context.photosColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: context.photosColors.surface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
