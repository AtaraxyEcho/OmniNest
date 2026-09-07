import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';

/// 缩略图动态解码宽：容器实际宽 × DPR，按 128px 步进向上取整，
/// 封顶 1024 与后端缩略图源图（1024 WebP）对齐。
///
/// 量化避免 Hero 飞行与窗口 resize 期间约束逐帧变化时反复更换解码键
/// 造成重复解码；向上取整保证解码尺寸永不小于显示需求。
int thumbnailDecodeWidth(double tileWidth, double devicePixelRatio) {
  final rawWidth = tileWidth.isFinite ? tileWidth * devicePixelRatio : 400.0;
  return ((rawWidth / 128).ceil() * 128).clamp(128, 1024);
}

/// Frame 缩略图：按容器实际宽度动态解码的封面网络图。
///
/// 解码宽随布局宽度与 DPR 自适应（128px 量化、上限 1024），替换此前
/// 各处固定低分辨率解码；占位与错误态使用 Frame 卡片底色。
class PhotoThumbImage extends StatelessWidget {
  const PhotoThumbImage({
    required this.imageUrl,
    this.cacheKey,
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
    super.key,
  });

  final String imageUrl;

  /// 磁盘缓存键；缺省时以 URL 为键。同一资源的多处展示应传同一键以共享缓存。
  final String? cacheKey;

  /// 入场淡入时长；网格/回收站/地点卡为零延迟秒开。
  final Duration fadeInDuration;

  /// 离场淡出时长；仅在图片源变化时触发。
  final Duration fadeOutDuration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CachedNetworkImage(
          imageUrl: imageUrl,
          cacheKey: cacheKey,
          memCacheWidth: thumbnailDecodeWidth(
            constraints.maxWidth,
            MediaQuery.devicePixelRatioOf(context),
          ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          useOldImageOnUrlChange: true,
          fadeInDuration: fadeInDuration,
          fadeOutDuration: fadeOutDuration,
          placeholder:
              (context, url) => ColoredBox(color: context.frameColors.card),
          errorWidget:
              (context, url, error) =>
                  ColoredBox(color: context.frameColors.card),
        );
      },
    );
  }
}
