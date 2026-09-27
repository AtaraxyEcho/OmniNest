import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_empty_view.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_masonry_layout.dart';

const double _masonryColumnGap = 10;

/// Vertical gap as a fixed fraction of column width.
///
/// Placement depends only on the photo list and column count so resize
/// only scales coordinates instead of re-running the greedy layout.
const double _masonryGapLogical = 0.05;

/// Frame 瀑布流网格：按设计稿 CSS columns 布局。
///
/// 默认 4 列，容器 ≤1280px 时 3 列，≤900px 时 2 列；列距 10px、
/// 图格下边距 10px、容器内边距 16px（md 及以上 24px）。
///
/// 全表贪心分柱只在列表/列数变化时计算；渲染用 [SliverLayoutBuilder]
/// 按滚动视口裁剪，只构建可见 [PhotoGridTile]，列坐标连续无空洞。
class FrameMasonryGrid extends ConsumerStatefulWidget {
  const FrameMasonryGrid({
    required this.photos,
    required this.onOpenPhoto,
    this.onToggleFavorite,
    this.emptyMessage,
    this.emptySubtitle,
    super.key,
  });

  final List<PhotoItem> photos;
  final ValueChanged<PhotoItem> onOpenPhoto;

  /// null 时隐藏收藏入口（无 activity:write 的角色）。
  final ValueChanged<PhotoItem>? onToggleFavorite;

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
  List<MasonryPlacedTile> _placed = const [];
  double _totalLogicalHeight = 0;

  /// 已挂载但已离开 cache 窗口的 tile：分帧卸载，避免单批语义更新过大。
  final Set<String> _hysteresisIds = <String>{};
  Set<String> _lastKeepIds = <String>{};

  static const int _maxUnloadPerFrame = 4;

  void _ensureLayout(int columns) {
    if (_hasLayout &&
        identical(_layoutPhotos, widget.photos) &&
        _layoutColumns == columns) {
      return;
    }
    _layoutPhotos = widget.photos;
    _layoutColumns = columns;
    _hasLayout = true;
    _hysteresisIds.clear();
    _lastKeepIds = <String>{};
    _placed = placeMasonryTiles(
      widget.photos,
      columns,
      gapLogical: _masonryGapLogical,
    );
    _totalLogicalHeight = masonryTotalLogicalHeight(_placed);
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
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical ||
            notification.metrics.extentAfter >= 640) {
          return false;
        }
        // 滚动通知可能落在 layout 阶段，延迟加载避免 Navigator/Focus 断言。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(photoCenterControllerProvider.notifier)
              .loadMoreVisiblePhotos();
        });
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
                final contentWidth = (constraints.crossAxisExtent - padding * 2)
                    .clamp(0.0, double.infinity);
                final columnWidth =
                    columns <= 0
                        ? 0.0
                        : (contentWidth - _masonryColumnGap * (columns - 1)) /
                            columns;
                _ensureLayout(columns);
                final placed = _placed;
                final totalHeight = columnWidth * _totalLogicalHeight;
                // 视口 + 固定预取，滚动时仅构建相交 tile。
                const cachePad = 600.0;
                final cacheTop = (constraints.scrollOffset - cachePad).clamp(
                  0.0,
                  double.infinity,
                );
                final cacheBottom =
                    constraints.scrollOffset +
                    constraints.remainingPaintExtent +
                    cachePad;
                final visible = <Widget>[];
                final wantedIds = <String>{};
                for (final tile in placed) {
                  final top = tile.logicalTop * columnWidth;
                  final height = tile.logicalExtent * columnWidth;
                  if (top + height < cacheTop || top > cacheBottom) {
                    continue;
                  }
                  wantedIds.add(tile.photo.id);
                }
                // 离开 cache 的 tile 先进滞后集继续挂载，每帧最多卸载
                // [_maxUnloadPerFrame] 个，避免滚动时单批语义更新触发
                // Windows 桥 "will not be in the tree"。
                for (final id in _lastKeepIds) {
                  if (!wantedIds.contains(id)) {
                    _hysteresisIds.add(id);
                  }
                }
                _hysteresisIds.removeAll(wantedIds);
                final drop = _hysteresisIds.take(_maxUnloadPerFrame).toSet();
                _hysteresisIds.removeAll(drop);
                final keepIds = <String>{...wantedIds, ..._hysteresisIds};
                _lastKeepIds = keepIds;
                if (_hysteresisIds.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                  });
                }
                for (final tile in placed) {
                  final top = tile.logicalTop * columnWidth;
                  final height = tile.logicalExtent * columnWidth;
                  if (!keepIds.contains(tile.photo.id)) {
                    continue;
                  }
                  final left = tile.column * (columnWidth + _masonryColumnGap);
                  visible.add(
                    Positioned(
                      key: ValueKey(tile.photo.id),
                      left: left,
                      top: top,
                      width: columnWidth,
                      height: height,
                      child: PhotoGridTile(
                        photo: tile.photo,
                        enableHero: true,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedIds.contains(tile.photo.id),
                        onTap: () {
                          if (isSelectionMode) {
                            ref
                                .read(photoCenterControllerProvider.notifier)
                                .togglePhotoSelection(tile.photo.id);
                          } else {
                            widget.onOpenPhoto(tile.photo);
                          }
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          _toggleSelect(tile.photo, isSelectionMode);
                        },
                        onToggleSelection:
                            () => _toggleSelect(tile.photo, isSelectionMode),
                        onToggleFavorite:
                            widget.onToggleFavorite == null
                                ? null
                                : () => widget.onToggleFavorite!(tile.photo),
                      ),
                    ),
                  );
                }
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: SizedBox(
                      height: totalHeight > 0 ? totalHeight : 1,
                      width: contentWidth,
                      child: Stack(clipBehavior: Clip.none, children: visible),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
