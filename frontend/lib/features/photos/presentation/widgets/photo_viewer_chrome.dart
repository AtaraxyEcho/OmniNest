import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/domain/photo.dart';

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
    required this.onShare,
    required this.showInfo,
    required this.compact,
    this.countText,
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
  final VoidCallback onShare;
  final bool showInfo;
  final bool compact;

  /// 当前位置计数（如 3 / 24）；紧凑档提供时替换日期行（信息减法）。
  final String? countText;

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

    // 装饰面铺满含状态栏，SafeArea 只避让内容，避免顶栏与系统栏断层。
    return DecoratedBox(
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
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (compact && countText != null)
                        Text(
                          countText != null && date != null
                              ? '$countText · ${viewerShortDate(date)}'
                              : countText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dateColor,
                            fontSize: AppTypography.labelSmall,
                          ),
                        )
                      else if (date != null)
                        Text(
                          viewerShortDate(date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dateColor,
                            fontSize: AppTypography.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
                // 紧凑档：溢出菜单收编为底部动作行，头部仅留幻灯片直达。
                if (compact)
                  IconButton(
                    tooltip: AppLocalizations.of(context).photosSlideshow,
                    onPressed: onSlideshow,
                    icon: Icon(
                      Icons.play_arrow_rounded,
                      color: iconColor,
                      size: 22,
                    ),
                    visualDensity: VisualDensity.compact,
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
                  // Heart/Share/Download 前置组与设计稿（幻灯片顶栏）一致。
                  IconButton(
                    tooltip: AppLocalizations.of(context).photosSharePhoto,
                    onPressed: onShare,
                    icon: Icon(
                      Icons.share_outlined,
                      color: iconColor,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).photosDownloadPhoto,
                    onPressed: onDownload,
                    icon: Icon(
                      Icons.download_outlined,
                      color: iconColor,
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
                    icon: Icon(
                      Icons.play_arrow_rounded,
                      color: iconColor,
                      size: 22,
                    ),
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
          ),
        ),
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

/// 紧凑档底部动作行（样例 photo-actions）：心/分享/下载/编辑/加相册/
/// 信息/删除 七钮，玻璃渐变横贯底部，替代原溢出菜单。
class PhotoViewerBottomActions extends StatelessWidget {
  const PhotoViewerBottomActions({
    super.key,
    required this.photo,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onDownload,
    required this.onEdit,
    required this.onAddToAlbum,
    required this.onToggleInfo,
    required this.onDelete,
    required this.showInfo,
  });

  final PhotoItem photo;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback onAddToAlbum;
  final VoidCallback onToggleInfo;
  final VoidCallback onDelete;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isDark
            ? Colors.white.withValues(alpha: 0.78)
            : context.photosColors.onSurfaceVariant;
    final activeColor = context.frameColors.accent;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              isDark
                  ? [Colors.transparent, Colors.black.withValues(alpha: 0.55)]
                  : [
                    Colors.transparent,
                    context.photosColors.surfaceContainer.withValues(
                      alpha: 0.92,
                    ),
                  ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip:
                    photo.favorite
                        ? l10n.photosUnfavorite
                        : l10n.photosFavorite,
                onPressed: onToggleFavorite,
                icon: Icon(
                  photo.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: photo.favorite ? activeColor : iconColor,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: l10n.photosSharePhoto,
                onPressed: onShare,
                icon: Icon(Icons.share_outlined, color: iconColor, size: 22),
              ),
              IconButton(
                tooltip: l10n.photosDownloadPhoto,
                onPressed: onDownload,
                icon: Icon(Icons.download_outlined, color: iconColor, size: 22),
              ),
              IconButton(
                tooltip: l10n.photosEdit,
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, color: iconColor, size: 22),
              ),
              IconButton(
                tooltip: l10n.photosAddToAlbum,
                onPressed: onAddToAlbum,
                icon: Icon(
                  Icons.create_new_folder_outlined,
                  color: iconColor,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: showInfo ? l10n.photosHideInfo : l10n.photosShowInfo,
                onPressed: onToggleInfo,
                icon: Icon(
                  Icons.info_outline_rounded,
                  color: showInfo ? activeColor : iconColor,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: l10n.photosDelete,
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: iconColor,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frame 查看器左右切换按钮：44px 圆形、半透明底、白色线形图标（样例 photo-nav）。
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
            shape: CircleBorder(side: BorderSide(color: border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Tooltip(
                message: tooltip,
                child: SizedBox(
                  width: 44,
                  height: 44,
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

/// 托管查看器舞台底色（样例 `.photo-viewer` 的 #050807 实底）。
const Color photoViewerHostedStageColor = FramePalette.stage;

/// 托管查看器横幅（样例 photo-viewer > header）：关闭圆钮 + 居中的
/// 地名与「N of M · 时间」副题 + 幻灯片直达圆钮。
class PhotoViewerHostedHeader extends StatelessWidget {
  const PhotoViewerHostedHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onSlideshow,
    super.key,
  });

  final String title;

  /// 已本地化的位置与拍摄时间组合文案。
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onSlideshow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MobileModuleHeader(
      title: title,
      subtitle: subtitle,
      backTooltip: l10n.coreClose,
      onBack: onBack,
      actions: [
        MobileGlassIconButton(
          tooltip: l10n.photosSlideshow,
          icon: Icons.play_arrow_rounded,
          onPressed: onSlideshow,
        ),
      ],
    );
  }
}

/// 托管查看器动作行（样例 `.photo-actions`）：7 个 48 玻璃圆钮居中排布，
/// 宽度不足时整行横向滚动（样例 nowrap + overflow-x:auto）。
class PhotoViewerHostedActions extends StatelessWidget {
  const PhotoViewerHostedActions({
    required this.photo,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onDownload,
    required this.onEdit,
    required this.onAddToAlbum,
    required this.onToggleInfo,
    required this.onDelete,
    required this.showInfo,
    super.key,
  });

  final PhotoItem photo;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback onAddToAlbum;
  final VoidCallback onToggleInfo;
  final VoidCallback onDelete;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <Widget>[
      _HostedViewerActionButton(
        icon:
            photo.favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
        tooltip: photo.favorite ? l10n.photosUnfavorite : l10n.photosFavorite,
        active: photo.favorite,
        onTap: onToggleFavorite,
      ),
      _HostedViewerActionButton(
        icon: Icons.share_outlined,
        tooltip: l10n.photosSharePhoto,
        onTap: onShare,
      ),
      _HostedViewerActionButton(
        icon: Icons.download_outlined,
        tooltip: l10n.photosDownloadPhoto,
        onTap: onDownload,
      ),
      _HostedViewerActionButton(
        icon: Icons.edit_outlined,
        tooltip: l10n.photosEdit,
        onTap: onEdit,
      ),
      _HostedViewerActionButton(
        icon: Icons.add_rounded,
        tooltip: l10n.photosAddToAlbum,
        onTap: onAddToAlbum,
      ),
      _HostedViewerActionButton(
        icon: Icons.info_outline_rounded,
        tooltip: showInfo ? l10n.photosHideInfo : l10n.photosShowInfo,
        active: showInfo,
        onTap: onToggleInfo,
      ),
      _HostedViewerActionButton(
        icon: Icons.delete_outline_rounded,
        tooltip: l10n.photosDelete,
        onTap: onDelete,
      ),
    ];
    return DecoratedBox(
      // 样例动作行不实铺底栏，靠底部渐变把照片与钮群分层。
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [FramePalette.stageFadeStart, FramePalette.stageFadeEnd],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (
                          var index = 0;
                          index < actions.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 10),
                          actions[index],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 托管动作行圆钮：样例 `.icon-button` 48 圆 + 白 10% 描边；激活项
/// （已收藏/信息面板展开）用酸绿前景与描边。
class _HostedViewerActionButton extends StatelessWidget {
  const _HostedViewerActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(
            icon,
            size: 20,
            color:
                active
                    ? MobileEnvPalette.dark.accent
                    : MobileEnvPalette.dark.ink,
          ),
          style: IconButton.styleFrom(
            backgroundColor: MobileEnvPalette.dark.iconButtonGlass,
            foregroundColor:
                active
                    ? MobileEnvPalette.dark.accent
                    : MobileEnvPalette.dark.ink,
            side: BorderSide(
              color:
                  active
                      ? MobileEnvPalette.dark.accent.withValues(alpha: 0.45)
                      : MobileEnvPalette.dark.line10,
            ),
            minimumSize: const Size.square(48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
