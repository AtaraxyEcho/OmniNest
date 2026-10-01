import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 照片详情 Hero 飞行载体：按飞行方向选择内容，保证两端画质连续。
///
/// 进入（push）：底层是网格瓦片的起始子树，与点击前所见完全一致，
/// 首帧不空、无加载指示器入镜；上层以飞行进度交叉淡入查看器封面
/// 档清晰图（解码宽与查看器封面层一致，共享同一次解码），就绪后
/// 在飞行中渐进覆盖缩略图，落位时查看器封面层同步命中无缝接管。
/// 清晰图未就绪或加载失败时保持透明，底层缩略图始终可见。
///
/// 退出（pop）：直接飞行查看器侧起始子树，清晰大图平滑缩小落回
/// 格子；而不是先瞬间降级为拉伸的小尺寸缩略图再缩小。
///
/// 自定义 shuttle 不带 Material 底与阴影：默认 Material flight 与
/// InteractiveViewer 的变换叠加会在对角线残留白色接缝。
class PhotoHeroFlightShuttle extends StatelessWidget {
  const PhotoHeroFlightShuttle({
    required this.photo,
    required this.animation,
    required this.flightDirection,
    required this.fromChild,
    required this.coverDecodeWidth,
    super.key,
  });

  final PhotoItem photo;

  /// 飞行进度：push 由 0 渐至 1，驱动清晰层交叉淡入。
  final Animation<double> animation;

  final HeroFlightDirection flightDirection;

  /// 起始侧 Hero 子树：push 为网格瓦片图片，pop 为查看器图片。
  final Widget fromChild;

  /// 与查看器封面层一致的解码宽，保证飞行层与落位层命中同一缓存条目。
  final int coverDecodeWidth;

  @override
  Widget build(BuildContext context) {
    if (flightDirection == HeroFlightDirection.pop) {
      return fromChild;
    }
    final coverUrl = photo.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) {
      return fromChild;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        fromChild,
        FadeTransition(
          opacity: animation,
          child: CachedNetworkImage(
            imageUrl: coverUrl,
            cacheKey: photo.coverCacheKey,
            memCacheWidth: coverDecodeWidth,
            fit: BoxFit.contain,
            useOldImageOnUrlChange: true,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
