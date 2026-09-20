/// Portal 可聚焦模块。
///
/// Portal 只承接模块的轻量入口和预览，完整操作仍回到各模块页面。
enum PortalFocusModule {
  reader,
  video,
  photos,
  music,
  files,
  weather,
  tasks,
  admin,
}

/// Portal 焦点项图标语义。
enum PortalFocusIcon { reader, video, photos, music }

/// Portal 焦点内容项。
class PortalFocusItem {
  const PortalFocusItem({
    required this.icon,
    required this.module,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.route,
    required this.actionLabel,
    required this.variant,
    this.heroEyebrow,
    this.heroBody,
    this.readerItemId,
    this.coverCacheKey,
  });

  final PortalFocusIcon icon;
  final PortalFocusModule module;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String route;
  final String actionLabel;
  final int variant;
  final String? heroEyebrow;
  final String? heroBody;
  final String? readerItemId;

  /// 封面稳定缓存键：以内容标识（影片/照片/曲目 ID）构造，与会过期的
  /// 签名 URL 解耦；URL 重签后命中同一缓存条目，避免重复下载与错失恢复。
  final String? coverCacheKey;
}
