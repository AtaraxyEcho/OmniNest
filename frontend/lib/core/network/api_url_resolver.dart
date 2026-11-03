/// 服务端相对资源地址的解析工具。
///
/// 后端对本地媒体库、字幕、海报和音乐封面等资源下发的是根相对路径
/// （例如 `/api/v1/public/video/items/{id}/stream?token=...`）。客户端需要把它
/// 换算成绝对地址，同时**保留子路径部署前缀**：当 `OMNINEST_WEB_BASE_HREF=/omninest/`
/// 时 `apiBaseUrl` 是 `https://host/omninest/api/v1`，直接按 origin 拼接会丢掉
/// `/omninest`，导致播放、字幕与封面全部 404。
library;

/// 从 API baseUrl 推导站点根地址（含子路径前缀，不含 `/api/v1`）。
///
/// 例：`https://host/omninest/api/v1` → `https://host/omninest`；
/// `https://host/api/v1` → `https://host`。
String resolveApiSiteRoot(String apiBaseUrl) {
  final normalizedBase = _trimTrailingSlash(apiBaseUrl);
  final baseUri = Uri.tryParse(normalizedBase);
  if (baseUri == null || !baseUri.hasScheme || baseUri.authority.isEmpty) {
    return normalizedBase;
  }
  const apiSuffix = '/api/v1';
  final path =
      baseUri.path.endsWith(apiSuffix)
          ? baseUri.path.substring(0, baseUri.path.length - apiSuffix.length)
          : baseUri.path;
  return '${baseUri.scheme}://${baseUri.authority}$path';
}

/// 把后端下发的相对资源路径解析为绝对 URL。
///
/// - 已带 scheme 的地址原样返回（CDN 直链、MinIO 预签名地址）。
/// - 以 `/api/` 开头的根相对路径拼到站点根上，保留子路径部署前缀。
/// - 其它以 `/` 开头的路径视为相对 API 基址（`baseUrl` 已含 `/api/v1`）。
/// - 不带 `/` 的路径直接追加到 API 基址后。
///
/// [apiBaseUrl] 无法解析时原样返回 [url]，交由调用方按失败处理。
String resolveServerApiUrl(String apiBaseUrl, String url) {
  if (url.isEmpty) {
    return url;
  }
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) {
    return url;
  }
  final normalizedBase = _trimTrailingSlash(apiBaseUrl);
  final baseUri = Uri.tryParse(normalizedBase);
  if (baseUri == null || !baseUri.hasScheme || baseUri.authority.isEmpty) {
    return url;
  }
  if (url.startsWith('/api/')) {
    return '${resolveApiSiteRoot(normalizedBase)}$url';
  }
  if (url.startsWith('/')) {
    return '$normalizedBase$url';
  }
  return '$normalizedBase/$url';
}

String _trimTrailingSlash(String value) {
  var normalized = value;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
