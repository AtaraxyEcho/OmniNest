import 'package:flutter/material.dart';
import 'package:omninest/app/theme/backdrop_scrim_colors.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';
import 'package:omninest/features/backdrop/presentation/bundled_wallpaper_poster.dart';

/// 背景库瓦片的预览层。
///
/// 三种素材形态各有取景方式：服务端素材优先缩略图、退到原图、再退到占位；
/// 内置默认壁纸用随包封面帧；其余（理论上不会出现的形态）同样落到占位。
class BackdropTilePreview extends StatelessWidget {
  const BackdropTilePreview({required this.backdrop, super.key});

  final AppBackdropAsset backdrop;

  @override
  Widget build(BuildContext context) {
    if (backdrop.sourceType == AppBackdropSourceType.server) {
      final thumbnailUrl = backdrop.thumbnailPath;
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        return AppBackdropImage(
          url: thumbnailUrl,
          cacheKey: 'backdrop-preview:${backdrop.id}',
          fit: BoxFit.cover,
          fallbackUrl: backdrop.path.isNotEmpty ? backdrop.path : null,
        );
      }
      if (backdrop.mediaType != AppBackdropMediaType.video &&
          backdrop.path.isNotEmpty) {
        return AppBackdropImage(
          url: backdrop.path,
          cacheKey: 'backdrop-preview-full:${backdrop.id}',
          fit: BoxFit.cover,
        );
      }
      return const _BackdropVideoPlaceholder();
    }
    if (backdrop.sourceType == AppBackdropSourceType.bundled) {
      return const BundledWallpaperPoster();
    }
    return const _BackdropVideoPlaceholder();
  }
}

class _BackdropVideoPlaceholder extends StatelessWidget {
  const _BackdropVideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BackdropStageColors.panelStart,
            BackdropStageColors.panelEnd,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: Colors.white.withValues(alpha: 0.62),
          size: 34,
        ),
      ),
    );
  }
}
