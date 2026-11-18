import 'package:flutter/material.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// 内置默认壁纸图像。
///
/// 登录画幅、桌面壁纸层、背景库瓦片、移动端环境抽屉与天气面板共用同一张
/// 随包照片，避免不同入口加载出不一致的默认场景。
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
