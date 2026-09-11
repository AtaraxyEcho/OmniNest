import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_empty_view.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_masonry_layout.dart';

/// 每列每窗最多构建的图格数；整窗约 columns × 该值，控制视口附近 build 量。
const int _masonryWindowPerColumn = 8;

/// Frame 瀑布流网格：按设计稿 CSS columns 布局。
///
/// 默认 4 列，容器 ≤1280px 时 3 列，≤900px 时 2 列；列距 10px、
/// 图格下边距 10px、容器内边距 16px（md 及以上 24px）。
///
/// 整表贪心分柱只在列表/列数变化时计算；渲染按垂直窗口懒构建，
/// 避免大图库一次性 build 全部 [PhotoGridTile]。
class FrameMasonryGrid extends ConsumerStatefulWidget {
  const FrameMasonryGrid({
    required this.photos,
    required this.onOpenPhoto,
    required this.onToggleFavorite,
    this.emptyMessage,
    this.emptySubtitle,
    super.key,
  });

  final List<PhotoItem> photos;
  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoItem> onToggleFavorite;

  /// 空态主文案；缺省为"还没有照片"。
  final String? emptyMessage;

  /// 空态补充文案。
  final String? emptySubtitle;

  @override
  ConsumerState<FrameMasonryGrid> createState() => _FrameMasonryGridState();
}

class _FrameMasonryGridState extends ConsumerState<FrameMasonryGrid> {
  List<PhotoItem>? _layoutPhotos;
  int _layoutColumns = 0;
  bool _hasLayout = false;
  List<List<List<PhotoItem>>> _windows = const [];

  void _ensureLayout(int columns) {
    if (_hasLayout &&
        identical(_layoutPhotos, widget.photos) &&
        _layoutColumns == columns) {
      return;
    }
    _layoutPhotos = widget.photos;
    _layoutColumns = columns;
    _hasLayout = true;
    final tracks = assignMasonryColumns(widget.photos, columns);
    _windows = windowMasonryColumns(
      tracks,
      windowSize: _masonryWindowPerColumn,
    );
  }

  int _columnCountFor(double width) {
    if (width > 1280) return 4;
    if (width > 900) return 3;
    return 2;
  }

  void _toggleSelect(PhotoItem photo, bool isSelectionMode) {
    final notifier = ref.read(photoCenterControllerProvider.notifier);
    if (!isSelectionMode) {
      notifier.toggleSelectionMode();
    }
    notifier.togglePhotoSelection(photo.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 仅订阅多选相关字段，避免 tab/分页/收藏等无关变更重建整网。
    final selection = ref.watch(
      photoCenterControllerProvider.select((value) {
        final data = value.asData?.value;
        if (data == null) {
          return (isSelectionMode: false, selectedIds: const <String>{});
        }
        return (
          isSelectionMode: data.isSelectionMode,
          selectedIds: data.selectedPhotoIds,
        );
      }),
    );
    final isSelectionMode = selection.isSelectionMode;
    final selectedIds = selection.selectedIds;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 640) {
          ref
              .read(photoCenterControllerProvider.notifier)
              .loadMoreVisiblePhotos();
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.photos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: FrameEmptyView(
                icon: Icons.image_outlined,
                message: widget.emptyMessage ?? l10n.photosNoPhotos,
                hint: widget.emptySubtitle,
              ),
            )
          else
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.crossAxisExtent > 768 ? 24.0 : 16.0;
                final columns = _columnCountFor(constraints.crossAxisExtent);
                _ensureLayout(columns);
                final windows = _windows;
                return SliverPadding(
                  padding: EdgeInsets.all(padding),
                  sliver: SliverList.builder(
                    itemCount: windows.length,
                    itemBuilder: (context, windowIndex) {
                      final windowTracks = windows[windowIndex];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var columnIndex = 0;
                              columnIndex < windowTracks.length;
                              columnIndex++
                            ) ...[
                              if (columnIndex > 0) const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  children: [
                                    for (final photo
                                        in windowTracks[columnIndex])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: PhotoGridTile(
                                          key: ValueKey(photo.id),
                                          photo: photo,
                                          aspectRatio: photoMasonryAspectRatio(
                                            photo,
                                          ),
                                          enableHero: true,
                                          isSelectionMode: isSelectionMode,
                                          isSelected: selectedIds.contains(
                                            photo.id,
                                          ),
                                          onTap: () {
                                            if (isSelectionMode) {
                                              ref
                                                  .read(
                                                    photoCenterControllerProvider
                                                        .notifier,
                                                  )
                                                  .togglePhotoSelection(
                                                    photo.id,
                                                  );
                                            } else {
                                              widget.onOpenPhoto(photo);
                                            }
                                          },
                                          onLongPress: () {
                                            HapticFeedback.mediumImpact();
                                            _toggleSelect(
                                              photo,
                                              isSelectionMode,
                                            );
                                          },
                                          onToggleSelection:
                                              () => _toggleSelect(
                                                photo,
                                                isSelectionMode,
                                              ),
                                          onToggleFavorite:
                                              () => widget.onToggleFavorite(
                                                photo,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
