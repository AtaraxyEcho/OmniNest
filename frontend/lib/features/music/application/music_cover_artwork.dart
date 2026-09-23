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
