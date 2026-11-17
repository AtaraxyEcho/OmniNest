import 'package:flutter/material.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// 内置默认壁纸的封面帧。
///
/// 默认壁纸是随包视频，封面帧是它在界面上的静态表示，被五处共用：视频首帧
/// 就绪前垫底、播放失败后的兜底、素材库瓦片、移动端环境抽屉预览、天气面板
/// 取景。集中在一处，免得每加一处置景就重新推一遍 `Image.asset` 的参数。
class BundledWallpaperPoster extends StatelessWidget {
  const BundledWallpaperPoster({
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    super.key,
  });

  /// 视频层下的垫底用宿主同一套 `BoxFit`，瓦片与取景固定 `cover`。
  final BoxFit fit;

  final AlignmentGeometry alignment;

  /// 只铺一条窄带时按窄带宽度解码，避免把整张 1920 宽封面帧解进图片缓存。
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      bundledDefaultWallpaperPosterAssetPath,
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
    );
  }
}
