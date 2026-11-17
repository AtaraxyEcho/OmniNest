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

/// 判断地址是否为内联封面数据地址（`data:image/...;base64,`）。
///
/// 内嵌标签封面在入库前会以这种形式整段进出接口与本地缓存，
/// 需要按字节的场合（快照、远端上报）单独识别并剔除。
bool isInlineCoverDataUrl(String url) => url.startsWith('data:image/');

/// 本地封面的缩略图路径：稳定 API 路径追加后缀，外部地址与空值原样返回。
///
/// 后端在缩略图不可派生时回退原图，因此本方法不表达"缩略图一定存在"。已经带后缀的
/// 地址原样返回：展示地址可能被再次喂回本方法（如卡片复用），拼出二级后缀会直接 404。
String? musicCoverThumbnailPath(String? coverUrl) {
  final url = coverUrl?.trim();
  if (url == null || url.isEmpty || !isMusicCoverApiPath(url)) {
    return coverUrl;
  }
  if (url.endsWith(musicCoverThumbnailSuffix)) {
    return url;
  }
  return '$url$musicCoverThumbnailSuffix';
}
