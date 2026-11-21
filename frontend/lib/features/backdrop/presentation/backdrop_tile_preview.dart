import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/theme/backdrop_scrim_colors.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';
import 'package:omninest/features/backdrop/presentation/bundled_wallpaper_poster.dart';

/// 背景库瓦片的预览层。
///
/// 三种素材形态各有取景方式：服务端素材优先缩略图、退到原图、再退到占位；
/// 内置默认壁纸用随包照片；其余（理论上不会出现的形态）同样落到占位。
///
/// [blurSigma] 复刻壁纸层的用户模糊：设置页的取景框是唯一能看到「模糊滑杆
/// 起没起作用」的地方（默认作用域下设置页自己不铺壁纸），因此由预览自己
/// 承担这段模糊，调用方只需给出与 `AppBackdropSurface` 相同的 sigma 语义。
class BackdropTilePreview extends StatelessWidget {
  const BackdropTilePreview({
    required this.backdrop,
    this.maxDecodeWidth = 720,
    this.blurSigma = 0,
    super.key,
  });

  final AppBackdropAsset backdrop;

  /// 预览解码档位；宽幅取景框传 1440，素材库瓦片保持 720。
  final int maxDecodeWidth;

  /// 复刻壁纸用户模糊的 sigma；`<= 0.05` 视为不模糊（与壁纸层阈值一致）。
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview();
    if (blurSigma <= 0.05) {
      return preview;
    }
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
        tileMode: TileMode.decal,
      ),
      child: preview,
    );
  }

  Widget _buildPreview() {
    if (backdrop.sourceType == AppBackdropSourceType.server) {
      final thumbnailUrl = backdrop.thumbnailPath;
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        return AppBackdropImage(
          url: thumbnailUrl,
          cacheKey: 'backdrop-preview:${backdrop.id}',
          fit: BoxFit.cover,
          // 瓦片只有百来像素宽，按显示器物理像素解码会为每个素材留一张
          // 4K 位图；720 档已远超显示采样率，像素上不引入可辨差异。
          maxDecodeWidth: maxDecodeWidth,
          fallbackUrl: backdrop.path.isNotEmpty ? backdrop.path : null,
        );
      }
      if (backdrop.mediaType != AppBackdropMediaType.video &&
          backdrop.path.isNotEmpty) {
        return AppBackdropImage(
          url: backdrop.path,
          cacheKey: 'backdrop-preview-full:${backdrop.id}',
          fit: BoxFit.cover,
          maxDecodeWidth: maxDecodeWidth,
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
