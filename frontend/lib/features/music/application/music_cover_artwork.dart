import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/music/domain/music_cover_paths.dart';

/// 封面取图的应用层出口。
///
/// 只有本地稳定鉴权 API 路径需要专域缓存管理器（拼 baseUrl、附带鉴权头并复用 401
/// 刷新链）；外部 CDN 地址与未注入下载客户端时返回 null，表现层回退默认缓存路径。
final musicCoverCacheManagerProvider = Provider.family<CacheManager?, String>(
  (ref, url) => isMusicCoverApiPath(url) ? MusicCoverCache.maybeInstance : null,
);

/// 与 [musicCoverCacheManagerProvider] 配对的 Web 渲染方式。
///
/// Web 端 `CachedNetworkImage` 默认 `HtmlImage`：浏览器按页面 origin 直接请求相对
/// 路径且不携带 Bearer，鉴权封面必然 401。命中专域管理器时必须切 `HttpGet`，让字节
/// 经由管理器下载。未命中（CDN 直链、非音乐地址）保持默认，行为与历史一致。
ImageRenderMethodForWeb musicCoverRenderMethodForWeb(CacheManager? manager) =>
    manager == null
        ? ImageRenderMethodForWeb.HtmlImage
        : ImageRenderMethodForWeb.HttpGet;

/// 把封面地址解析成系统可读的本地文件地址。
///
/// `audio_service` 的 Android 端用 `BitmapFactory.decodeFile(uri.path)` 取封面，
/// 不会自行下载网络地址，也未鉴权的 API 路径本来也取不到；因此交给系统媒体会话的
/// 封面必须先经缓存管理器落盘，再以 `file://` 形式下发。
Future<Uri?> resolveMusicCoverFileUri(String url) async {
  final manager =
      isMusicCoverApiPath(url)
          ? MusicCoverCache.maybeInstance
          : DefaultCacheManager();
  if (manager == null) {
    return null;
  }
  final file = await manager.getSingleFile(url);
  return Uri.file(file.path);
}
