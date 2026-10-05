import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_hosted_chrome.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

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
    final current = ref.read(photoAlbumPickerProvider);
    // 托管工具行的「完成」常驻，空选择与提交中直接忽略，避免把提交
    // 入口的禁用样式当成唯一防线。
    if (current.selectedIds.isEmpty || current.isSubmitting) {
      return;
    }
    final selectedCount = current.selectedIds.length;
    final success = await ref.read(photoAlbumPickerProvider.notifier).submit();
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (success) {
      showOmniFeedback(
        context,
        l10n.photosPickerAddSuccess(selectedCount),
        severity: OmniFeedbackSeverity.success,
      );
      if (mounted) {
        context.pop();
      }
    } else {
      final error = ref.read(photoAlbumPickerProvider).error;
      showOmniFeedback(
        context,
        error ?? l10n.photosAddPhotos,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoAlbumPickerProvider);
    final l10n = AppLocalizations.of(context);
    final hosted = photosHostedForm(context);
    return PhotoHostedScope(
      child: Scaffold(
        backgroundColor:
            hosted ? Colors.transparent : context.photosColors.surface,
        body:
            hosted
                ? _buildHostedBody(state, l10n)
                : _buildWorkstationBody(state, l10n),
        // 托管态提交走工具行「完成」，不再叠一条底部栏。
        bottomNavigationBar:
            hosted ? null : _buildWorkstationSubmitBar(l10n, state),
      ),
    );
  }

  /// 托管形态（样例 picker 页）：玻璃横幅 + photo-toolbar + 三列 picker-grid。
  Widget _buildHostedBody(PhotoAlbumPickerState state, AppLocalizations l10n) {
    final notifier = ref.read(photoAlbumPickerProvider.notifier);
    final selectedCount = state.selectedIds.length;
    return MobilePageSurface(
      backdropOpacity: 0.92,
      child: Column(
        children: [
          MobileModuleHeader(
            title: l10n.photosAddPhotos,
            subtitle: l10n.photosHostedToolbarCount(state.candidates.length),
            backTooltip: l10n.photosBack,
            onBack: () => context.pop(),
          ),
          PhotoHostedToolbarRow(
            minHeight: 40,
            label: state.error ?? l10n.photosSelectedCount(selectedCount),
            actions: [
              PhotoHostedPillButton(
                icon: Icons.check_rounded,
                label: l10n.photosSelectAll,
                onTap: notifier.selectAllCandidates,
              ),
              PhotoHostedPillButton(
                icon: Icons.checklist_rounded,
                label: l10n.photosDone,
                active: selectedCount > 0,
                onTap: () => unawaited(_submit()),
              ),
            ],
          ),
          Expanded(child: _buildHostedContent(state, l10n)),
        ],
      ),
    );
  }

  Widget _buildHostedContent(
    PhotoAlbumPickerState state,
    AppLocalizations l10n,
  ) {
    if (state.error != null && state.candidates.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          EnvEmptyState(
            icon: OmniIcons.close,
            title: l10n.photosOperationFailed,
            message: state.error,
            actionLabel: l10n.coreRetry,
            onAction:
                () => unawaited(
                  ref
                      .read(photoAlbumPickerProvider.notifier)
                      .open(widget.albumId),
                ),
          ),
        ],
      );
    }
    if (state.isInitialLoading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MobileEnvColors.inkMuted,
          ),
        ),
      );
    }
    if (state.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          EnvEmptyState(
            icon: OmniIcons.image,
            title: l10n.photosPickerNoCandidates,
          ),
        ],
      );
    }
    final candidates = state.candidates;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical ||
            notification.metrics.extentAfter >= 640) {
          return false;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          unawaited(ref.read(photoAlbumPickerProvider.notifier).loadMore());
        });
        return false;
      },
      child: PhotoHostedPhotoGrid(
        itemCount:
            candidates.length + (state.hasMore || state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= candidates.length) {
            return const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MobileEnvColors.inkMuted,
                ),
              ),
            );
          }
          final photo = candidates[index];
          return PhotoHostedSquareTile(
            key: ValueKey(photo.id),
            photo: photo,
            pickMode: true,
            picked: state.selectedIds.contains(photo.id),
            onTap:
                () => ref
                    .read(photoAlbumPickerProvider.notifier)
                    .toggle(photo.id),
          );
        },
      ),
    );
  }

  /// 工位形态：原有顶部栏 + 响应列数网格。
  Widget _buildWorkstationBody(
    PhotoAlbumPickerState state,
    AppLocalizations l10n,
  ) {
    final candidates = state.candidates;
    return Column(
      children: [
        // 顶部栏：返回 + 标题 + 已选计数
        DecoratedBox(
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
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          fontSize: AppTypography.titleMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      l10n.photosSelectedCount(state.selectedIds.length),
                      style: TextStyle(
                        color: context.photosColors.onSurfaceVariant,
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                        fontSize: AppTypography.bodyLarge,
                      ),
                    ),
                  )
                  : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth != 0 ||
                          notification.metrics.axis != Axis.vertical ||
                          notification.metrics.extentAfter >= 640) {
                        return false;
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        unawaited(
                          ref
                              .read(photoAlbumPickerProvider.notifier)
                              .loadMore(),
                        );
                      });
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
    );
  }

  /// 工位形态底部提交栏：错误回显 + 带计数的提交钮。
  Widget _buildWorkstationSubmitBar(
    AppLocalizations l10n,
    PhotoAlbumPickerState state,
  ) {
    // 底部提交栏
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.photosColors.surfaceContainer.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
            color: context.photosColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.error ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: AppTypography.bodySmall,
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
