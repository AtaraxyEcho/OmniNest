/// 音乐封面稳定 API 路径的共同约定。
///
/// 后端把本地封面统一暴露在 `GET /api/v1/music/covers/{fileId}`，缩略图是同一
/// 资源下的稳定子路径；客户端只拼接路径，不感知派生实现。
library;

/// 音乐封面稳定 API 路径前缀（后端 `GET /api/v1/music/covers/{fileId}`）。
const String musicCoverApiPathPrefix = '/api/v1/music/covers/';

/// 缩略图子路径后缀（后端 `GET /api/v1/music/covers/{fileId}/thumbnail`）。
const String musicCoverThumbnailSuffix = '/thumbnail';

/// 判断地址是否为本地音乐封面的稳定鉴权 API 路径。
///
/// 后端 DTO 返回相对路径；网易云等外部 CDN 封面为绝对地址，
/// 天然不匹配本前缀，Authorization 头不会外发给第三方域名。
bool isMusicCoverApiPath(String url) => url.startsWith(musicCoverApiPathPrefix);

/// 本地封面的缩略图路径：稳定 API 路径追加后缀，外部地址与空值原样返回。
///
/// 后端在缩略图不可派生时回退原图，因此本方法不表达"缩略图一定存在"。
String? musicCoverThumbnailPath(String? coverUrl) {
  final url = coverUrl?.trim();
  if (url == null || url.isEmpty || !isMusicCoverApiPath(url)) {
    return coverUrl;
  }
  return '$url$musicCoverThumbnailSuffix';
}
