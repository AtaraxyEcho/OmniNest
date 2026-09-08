import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// Frame 照片卡片：图片按纵横比自撑高度，悬停/多选/选中时显示遮罩层。
///
/// 遮罩层内含左上选择圆圈（20px，选中陶土色填充 + 白勾）与右上心形
/// （收藏陶土色填充，未收藏白色描边）；底部展示标题（暂代拍摄地点）
/// 与拍摄日期；选中态叠加 2px 陶土色内描边。
class PhotoGridTile extends StatefulWidget {
  const PhotoGridTile({
    required this.photo,
    required this.onTap,
    this.onLongPress,
    this.onToggleSelection,
    this.onToggleFavorite,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.aspectRatio,
    this.enableHero = false,
    super.key,
  });

  final PhotoItem photo;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 选择圆圈点击：无论是否处于多选模式都切换选中（设计稿 onToggle 语义）。
  final VoidCallback? onToggleSelection;

  /// 心形点击：切换收藏。
  final VoidCallback? onToggleFavorite;
  final bool isSelectionMode;
  final bool isSelected;

  /// 瀑布流布局使用：非空时图格按该纵横比自撑高度。
  final double? aspectRatio;

  /// 从图库进入详情时的共享元素过渡开关。
  final bool enableHero;

  @override
  State<PhotoGridTile> createState() => _PhotoGridTileState();
}

class _PhotoGridTileState extends State<PhotoGridTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    final photo = widget.photo;
    final overlayVisible =
        _hovering || widget.isSelectionMode || widget.isSelected;
    final date = photo.dateTaken ?? photo.createdAt;
    final dateText =
        date == null
            ? null
            : DateFormat.yMMMMd(
              Localizations.localeOf(context).toString(),
            ).format(date);

    final body = ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo.hasCover)
            PhotoThumbImage(
              imageUrl: photo.coverUrl!,
              cacheKey: photo.coverCacheKey,
            )
          else
            const _Placeholder(),

          // 悬停/多选/选中时的遮罩层
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !overlayVisible,
              child: AnimatedOpacity(
                opacity: overlayVisible ? 1 : 0,
                duration:
                    MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.22),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SelectionCircle(
                              selected: widget.isSelected,
                              onTap: widget.onToggleSelection,
                              semanticLabel: l10n.photosToggleSelection,
                            ),
                            _FavoriteHeart(
                              favorite: photo.favorite,
                              onTap: widget.onToggleFavorite,
                              semanticLabel:
                                  photo.favorite
                                      ? l10n.photosUnfavorite
                                      : l10n.photosFavorite,
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              photo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTypography.bodyLarge,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                            if (dateText != null)
                              Text(
                                dateText,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: AppTypography.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 选中态 2px 陶土色内描边
          if (widget.isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                    border: Border.fromBorderSide(
                      BorderSide(color: colors.accent, width: 2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    Widget card = GestureDetector(
      excludeFromSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child:
          widget.enableHero
              ? Hero(tag: 'photo-cover-${photo.id}', child: body)
              : body,
    );

    if (widget.aspectRatio != null && widget.aspectRatio! > 0) {
      card = AspectRatio(aspectRatio: widget.aspectRatio!, child: card);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: card,
    );
  }
}

/// 选择圆圈：20px 圆形，未选白色 75% 底 + 白色 50% 边框，选中陶土色底 + 白勾。
class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool selected;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  selected
                      ? colors.accent
                      : Colors.white.withValues(alpha: 0.75),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child:
                selected
                    ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    )
                    : null,
          ),
        ),
      ),
    );
  }
}

/// 收藏心形：收藏陶土色填充，未收藏白色描边。
class _FavoriteHeart extends StatelessWidget {
  const _FavoriteHeart({
    required this.favorite,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool favorite;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final customActions =
        onTap == null
            ? null
            : <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(label: semanticLabel): onTap!,
            };
    return Semantics(
      customSemanticsActions: customActions,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: IconTheme(
            data: const IconThemeData(size: 16),
            child:
                favorite
                    ? Icon(Icons.favorite, color: colors.accent)
                    : Icon(
                      Icons.favorite_border,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
          ),
        ),
      ),
    );
  }
}

/// 无封面时的占位图
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.frameColors.card);
  }
}
