import 'package:web/web.dart' as web;

/// Web 端在新标签页打开下载页。
///
/// 返回是否真正打开：浏览器弹窗拦截时 `window.open` 返回 null，调用方需
/// 降级为复制链接。
bool openDownloadUrl(String url) {
  return web.window.open(url, '_blank', 'noopener,noreferrer') != null;
}
