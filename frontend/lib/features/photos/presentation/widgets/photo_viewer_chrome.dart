import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/domain/photo.dart';

enum _PhotoMenuAction { info, edit, slideshow, addToAlbum, download, delete }

/// 详情页顶部栏：设计稿 PhotoViewer 样式的半透明浮层。
class PhotoViewerTopBar extends StatelessWidget {
  const PhotoViewerTopBar({
    super.key,
    required this.photo,
    required this.onClose,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.onToggleInfo,
    required this.onAddToAlbum,
    required this.onEdit,
    required this.onSlideshow,
    required this.onDownload,
    required this.showInfo,
    required this.compact,
  });

  final PhotoItem photo;
  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;
  final VoidCallback onToggleInfo;
  final VoidCallback onAddToAlbum;
  final VoidCallback onEdit;
  final VoidCallback onSlideshow;
  final VoidCallback onDownload;
  final bool showInfo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor =
        isDark
            ? Colors.black.withValues(alpha: 0.38)
            : context.photosColors.surfaceContainer.withValues(alpha: 0.92);
    final iconColor =
        isDark
            ? Colors.white.withValues(alpha: 0.70)
            : context.photosColors.onSurfaceVariant;
    final activeColor = context.frameColors.accent;
    final titleColor =
        isDark
            ? Colors.white.withValues(alpha: 0.90)
            : context.photosColors.onSurface;
    final dateColor =
        isDark
            ? Colors.white.withValues(alpha: 0.50)
            : context.photosColors.onSurfaceVariant;
    final centerTitle =
        photo.locationDisplay(preferZh: _isZhLocale(context)) ?? photo.title;
    final date = photo.dateTaken ?? photo.createdAt;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: barColor,
        border:
            isDark
                ? null
                : Border(
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
            tooltip: AppLocalizations.of(context).coreClose,
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: iconColor),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  centerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (date != null)
                  Text(
                    viewerShortDate(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dateColor, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (compact)
            PopupMenuButton<_PhotoMenuAction>(
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              color: context.photosColors.surfaceContainerHigh,
              icon: Icon(Icons.more_vert_rounded, color: iconColor),
              onSelected: (action) {
                switch (action) {
                  case _PhotoMenuAction.info:
                    onToggleInfo();
                  case _PhotoMenuAction.edit:
                    onEdit();
                  case _PhotoMenuAction.slideshow:
                    onSlideshow();
                  case _PhotoMenuAction.addToAlbum:
                    onAddToAlbum();
                  case _PhotoMenuAction.download:
                    onDownload();
                  case _PhotoMenuAction.delete:
                    onDelete();
                }
              },
              itemBuilder:
                  (context) => [
                    PopupMenuItem(
                      value: _PhotoMenuAction.info,
                      child: Text(
                        showInfo
                            ? AppLocalizations.of(context).photosHideInfo
                            : AppLocalizations.of(context).photosShowInfo,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.edit,
                      child: Text(AppLocalizations.of(context).photosEdit),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.slideshow,
                      child: Text(AppLocalizations.of(context).photosSlideshow),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.addToAlbum,
                      child: Text(
                        AppLocalizations.of(context).photosAddToAlbum,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.download,
                      child: Text(
                        AppLocalizations.of(context).photosDownloadPhoto,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PhotoMenuAction.delete,
                      child: Text(
                        AppLocalizations.of(context).photosDelete,
                        style: TextStyle(color: context.photosColors.danger),
                      ),
                    ),
                  ],
            )
          else ...[
            IconButton(
              tooltip:
                  photo.favorite
                      ? AppLocalizations.of(context).photosUnfavorite
                      : AppLocalizations.of(context).photosFavorite,
              onPressed: onToggleFavorite,
              icon: Icon(
                photo.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: photo.favorite ? activeColor : iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip:
                  showInfo
                      ? AppLocalizations.of(context).photosHideInfo
                      : AppLocalizations.of(context).photosShowInfo,
              onPressed: onToggleInfo,
              icon: Icon(
                Icons.info_outline_rounded,
                color: showInfo ? activeColor : iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosEdit,
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: iconColor, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosSlideshow,
              onPressed: onSlideshow,
              icon: Icon(Icons.play_arrow_rounded, color: iconColor, size: 22),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosAddToAlbum,
              onPressed: onAddToAlbum,
              icon: Icon(
                Icons.create_new_folder_outlined,
                color: iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosDownloadPhoto,
              onPressed: onDownload,
              icon: Icon(Icons.download_outlined, color: iconColor, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).photosDelete,
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: iconColor,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// 幻灯片播放状态徽章：底部居中，黑色半透明胶囊。
class PhotoViewerSlideshowBadge extends StatelessWidget {
  const PhotoViewerSlideshowBadge({
    super.key,
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_arrow_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.80),
          ),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).photosSlideshowBadge(current, total),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isZhLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh';
}

String viewerShortDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Frame 查看器左右切换按钮：42px 方形、圆角 8、35% 黑底、白色 60% 线形图标。
class PhotoViewerArrowButton extends StatelessWidget {
  const PhotoViewerArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.alignRight,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrim =
        isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.35);
    final border =
        isDark
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.10);
    final iconColor =
        isDark
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.88);
    return Positioned.fill(
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: scrim,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Tooltip(
                message: tooltip,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(icon, size: 22, color: iconColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
