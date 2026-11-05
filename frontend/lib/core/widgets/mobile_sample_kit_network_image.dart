part of 'mobile_sample_kit.dart';

/// 样例组件共用网络封面。
///
/// 统一走磁盘缓存并按布局宽度限制解码尺寸：样例组件铺满照片网格与横滑轨，
/// 直接 `Image.network` 全尺寸解码原图会造成掉帧；预签名 URL 的查询参数每次
/// 刷新都会变化，缓存键只保留路径，避免同一张图反复下载。
class _SampleNetworkImage extends StatelessWidget {
  const _SampleNetworkImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
        return CachedNetworkImage(
          imageUrl: url,
          cacheKey: _stableImageCacheKey(url),
          fit: BoxFit.cover,
          // 布局约束随窗口连续变化：严格跟随会反复换解码键、重复解码，
          // 统一量化到离散档位后同一视觉区间共用已解码位图。
          memCacheWidth: quantizedDecodeWidth(
            logicalWidth: logicalWidth,
            devicePixelRatio: devicePixelRatio,
          ),
          errorWidget: (_, _, _) => const ColoredBox(color: _mediaPlaceholder),
        );
      },
    );
  }
}

/// 去掉预签名查询串后的稳定缓存键。
String _stableImageCacheKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.hasScheme) {
    return uri.replace(query: '', fragment: '').toString();
  }
  final queryIndex = url.indexOf('?');
  return queryIndex < 0 ? url : url.substring(0, queryIndex);
}
