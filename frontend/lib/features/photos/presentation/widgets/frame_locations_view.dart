import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_empty_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_masonry_grid.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// Frame 地点视图：按地点分组的卡片网格 + 单地点照片瀑布流（设计稿 LocationsView）。
///
/// 分组基于已加载照片的逆地理地名，按界面语言中/英展示；
/// 无 GPS 信息的照片不参与分组。
class FrameLocationsView extends ConsumerStatefulWidget {
  const FrameLocationsView({
    required this.onOpenPhoto,
    required this.onToggleFavorite,
    super.key,
  });

  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoItem> onToggleFavorite;

  @override
  ConsumerState<FrameLocationsView> createState() => _FrameLocationsViewState();
}

class _FrameLocationsViewState extends ConsumerState<FrameLocationsView> {
  String? _selectedLocation;

  @override
  Widget build(BuildContext context) {
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    final photos =
        ref.watch(photoCenterControllerProvider).asData?.value.visiblePhotos ??
        const <PhotoItem>[];
    final groups = _groupByLocation(photos, preferZh);
    if (groups.isEmpty) {
      return FrameEmptyView(
        icon: Icons.place_outlined,
        message: AppLocalizations.of(context).photosFrameLocationsEmpty,
        hint: AppLocalizations.of(context).photosFrameLocationsEmptyHint,
      );
    }

    final selected = _selectedLocation;
    if (selected == null || !groups.containsKey(selected)) {
      return _LocationGrid(
        groups: groups,
        onSelected: (name) => setState(() => _selectedLocation = name),
      );
    }
    return _LocationDetail(
      location: selected,
      photos: groups[selected]!,
      onBack: () => setState(() => _selectedLocation = null),
      onOpenPhoto: (photo) {
        // 地点视图的浏览/幻灯片范围限定为当前地点的照片，
        // 与影集/时间线的区域隔离语义一致；幻灯片侧对 locations
        // 来源保留子集，不再回退全库替换。
        ref
            .read(photoBrowseScopeProvider.notifier)
            .set(
              groups[selected]!,
              PhotoBrowseSource.locations,
              sourceKey: selected,
            );
        widget.onOpenPhoto(photo);
      },
      onToggleFavorite: widget.onToggleFavorite,
    );
  }

  List<PhotoItem> locationPhotos(
    Map<String, List<PhotoItem>> groups,
    String location,
  ) {
    return groups[location] ?? const <PhotoItem>[];
  }

  /// 按 地名 → 照片 分组；地名取自逆地理结果并按界面语言选择。
  Map<String, List<PhotoItem>> _groupByLocation(
    List<PhotoItem> photos,
    bool preferZh,
  ) {
    final groups = <String, List<PhotoItem>>{};
    for (final photo in photos) {
      final name = photo.locationDisplay(preferZh: preferZh);
      if (name == null || name.isEmpty) {
        continue;
      }
      (groups[name] ??= []).add(photo);
    }
    final names =
        groups.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final name in names) name: groups[name]!};
  }
}

/// 一级页面：地点卡片网格。
class _LocationGrid extends StatelessWidget {
  const _LocationGrid({required this.groups, required this.onSelected});

  final Map<String, List<PhotoItem>> groups;
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
        final locations = groups.entries.toList(growable: false);
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
              name: entry.key,
              photos: entry.value,
              countLabel: l10n.photosTagsPhotoCount(entry.value.length),
              onSelected: () => onSelected(entry.key),
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
    required this.photos,
    required this.countLabel,
    required this.onSelected,
  });

  final String name;
  final List<PhotoItem> photos;
  final String countLabel;
  final VoidCallback onSelected;

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.photos.first;
    final cover = item.coverUrl ?? item.sourceUrl;
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
                    cover != null && cover.isNotEmpty
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
    required this.onToggleFavorite,
  });

  final String location;
  final List<PhotoItem> photos;
  final VoidCallback onBack;
  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoItem> onToggleFavorite;

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
