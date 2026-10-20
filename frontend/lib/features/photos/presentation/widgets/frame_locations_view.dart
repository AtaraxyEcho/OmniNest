import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_empty_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_masonry_grid.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// Frame 地点视图：按地点分组的卡片网格 + 单地点照片瀑布流（设计稿 LocationsView）。
///
/// 地点与张数取自服务端 `photos/groups/page?by=location`，不受已加载窗口限制；
/// 明细瀑布流用服务端预览与窗口内同城照片的并集，因此张数可能小于卡片计数。
class FrameLocationsView extends ConsumerStatefulWidget {
  const FrameLocationsView({
    required this.onOpenPhoto,
    this.onToggleFavorite,
    super.key,
  });

  final ValueChanged<PhotoItem> onOpenPhoto;

  /// null 时隐藏收藏入口（无 activity:write 的角色）。
  final ValueChanged<PhotoItem>? onToggleFavorite;

  @override
  ConsumerState<FrameLocationsView> createState() => _FrameLocationsViewState();
}

class _FrameLocationsViewState extends ConsumerState<FrameLocationsView> {
  /// 服务端把无 GPS 的照片归到这个桶名，明细匹配必须用同一字面量。
  static const String _unknownLocationKey = '未知位置';

  String? _selectedLocation;

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(photoLocationGroupsProvider);
    final groups = groupsAsync.asData?.value ?? const <PhotoGroup>[];
    final photos =
        ref.watch(photoCenterControllerProvider).asData?.value.visiblePhotos ??
        const <PhotoItem>[];
    final byCity = _groupByCity(photos);
    final locations = <_LocationEntry>[
      for (final group in groups)
        if (group.groupKey.isNotEmpty)
          _LocationEntry(
            name: group.groupKey,
            totalCount: group.photoCount,
            photos: _resolvePhotos(group, byCity[group.groupKey]),
          ),
    ];
    if (locations.isEmpty) {
      return FrameEmptyView(
        icon: Icons.place_outlined,
        message: AppLocalizations.of(context).photosFrameLocationsEmpty,
        hint: AppLocalizations.of(context).photosFrameLocationsEmptyHint,
      );
    }

    final selected = _selectedLocation;
    final entry =
        locations.where((location) => location.name == selected).firstOrNull;
    if (entry == null) {
      return _LocationGrid(
        locations: locations,
        onSelected: (name) => setState(() => _selectedLocation = name),
      );
    }
    // 内层返回语义：地点详情先回地点列表，不直接离开照片模块
    // （页级 PopScope 看不到本视图的私有选中态）。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _selectedLocation = null);
      },
      child: _LocationDetail(
        location: entry.name,
        photos: entry.photos,
        onBack: () => setState(() => _selectedLocation = null),
        onOpenPhoto: (photo) {
          // 地点视图的浏览/幻灯片范围限定为当前地点的照片，
          // 与影集/时间线的区域隔离语义一致；幻灯片侧对 locations
          // 来源保留子集，不再回退全库替换。
          ref
              .read(photoBrowseScopeProvider.notifier)
              .set(
                entry.photos,
                PhotoBrowseSource.locations,
                sourceKey: entry.name,
              );
          widget.onOpenPhoto(photo);
        },
        onToggleFavorite: widget.onToggleFavorite,
      ),
    );
  }

  /// 按服务端同城口径给窗口内照片建索引：只看 `city`，缺失即未知位置。
  Map<String, List<PhotoItem>> _groupByCity(List<PhotoItem> photos) {
    final groups = <String, List<PhotoItem>>{};
    for (final photo in photos) {
      final city = photo.gpsLocation?['city']?.toString().trim();
      final key = (city == null || city.isEmpty) ? _unknownLocationKey : city;
      (groups[key] ??= <PhotoItem>[]).add(photo);
    }
    return groups;
  }

  /// 明细照片 = 窗口内同城照片 + 服务端预览补齐，按 id 去重。
  List<PhotoItem> _resolvePhotos(PhotoGroup group, List<PhotoItem>? inWindow) {
    final byId = <String, PhotoItem>{
      for (final photo in inWindow ?? const <PhotoItem>[]) photo.id: photo,
    };
    for (final photo in group.photos) {
      byId.putIfAbsent(photo.id, () => photo);
    }
    return byId.values.toList(growable: false);
  }
}

/// 一个地点的展示数据：名称、服务端总张数、可渲染的照片集合。
class _LocationEntry {
  const _LocationEntry({
    required this.name,
    required this.totalCount,
    required this.photos,
  });

  final String name;
  final int totalCount;
  final List<PhotoItem> photos;
}

/// 一级页面：地点卡片网格。
class _LocationGrid extends StatelessWidget {
  const _LocationGrid({required this.locations, required this.onSelected});

  final List<_LocationEntry> locations;
  final ValueChanged<String> onSelected;

  int _columnCountFor(double width) {
    if (width > 1280) return 4;
    if (width > 900) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCountFor(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemCount: locations.length,
          itemBuilder: (context, index) {
            final entry = locations[index];
            return _LocationCard(
              name: entry.name,
              cover: entry.photos.firstOrNull,
              countLabel: l10n.photosTagsPhotoCount(entry.totalCount),
              onSelected: () => onSelected(entry.name),
            );
          },
        );
      },
    );
  }
}

/// 单个地点卡片：封面 + 底部地名与张数，悬停轻微放大。
class _LocationCard extends StatefulWidget {
  const _LocationCard({
    required this.name,
    required this.cover,
    required this.countLabel,
    required this.onSelected,
  });

  final String name;
  final PhotoItem? cover;
  final String countLabel;
  final VoidCallback onSelected;

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.cover;
    final cover = item?.coverUrl ?? item?.sourceUrl;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedScale(
                scale: _hover ? 1.05 : 1,
                duration:
                    MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child:
                    item != null && cover != null && cover.isNotEmpty
                        ? PhotoThumbImage(
                          imageUrl: cover,
                          // 缓存键与来源资源对应，避免污染封面/原图的磁盘缓存。
                          cacheKey:
                              cover == item.coverUrl
                                  ? item.coverCacheKey
                                  : item.sourceCacheKey,
                        )
                        : ColoredBox(color: context.frameColors.card),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.48),
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.countLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                    ],
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

/// 二级页面：单地点照片瀑布流。
class _LocationDetail extends StatelessWidget {
  const _LocationDetail({
    required this.location,
    required this.photos,
    required this.onBack,
    required this.onOpenPhoto,
    this.onToggleFavorite,
  });

  final String location;
  final List<PhotoItem> photos;
  final VoidCallback onBack;
  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoItem>? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: TextButton.icon(
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_rounded, size: 18, color: colors.sub),
            label: Text(
              AppLocalizations.of(context).photosLocationsBack,
              style: TextStyle(
                color: colors.sub,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                location,
                style: TextStyle(
                  fontFamily: FramePalette.serifFamily,
                  fontFamilyFallback: FramePalette.serifFallback,
                  color: colors.ink,
                  fontSize: AppTypography.titleLarge,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                AppLocalizations.of(
                  context,
                ).photosTagsPhotoCount(photos.length),
                style: TextStyle(
                  color: colors.muted,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FrameMasonryGrid(
            photos: photos,
            onOpenPhoto: onOpenPhoto,
            onToggleFavorite: onToggleFavorite,
          ),
        ),
      ],
    );
  }
}
