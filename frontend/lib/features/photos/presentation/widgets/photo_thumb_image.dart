import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/photos/application/photo_cover_recovery.dart';
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
/// 各处固定低分辨率解码；占位使用 Frame 卡片底色，错误态在底色上
/// 叠加可辨识的裂图图标，并上报封面自愈控制器（节流触发实时合并
/// 刷新，用现签 URL 替换列表中的过期签名对象）。
class PhotoThumbImage extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
          errorListener: (_) {
            // 加载失败可能是签名 URL 过期：post-frame 后上报，避免在
            // 图片流回调（可发生于 build 期）中直接改写 provider 状态。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                ref
                    .read(photoCoverRecoveryProvider.notifier)
                    .reportFailure();
              }
            });
          },
          placeholder:
              (context, url) => ColoredBox(color: context.frameColors.card),
          errorWidget:
              (context, url, error) => ColoredBox(
                color: context.frameColors.card,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: context.frameColors.sub.withValues(alpha: 0.55),
                  ),
                ),
              ),
        );
      },
    );
  }
}
