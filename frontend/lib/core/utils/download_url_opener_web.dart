import 'package:omninest/core/utils/download_url_policy.dart';
import 'package:web/web.dart' as web;

/// Web 端在新标签页打开下载页。
///
/// 返回是否真正打开：协议不合法、被浏览器弹窗拦截（`window.open` 返回 null）
/// 时都返回 false，调用方需降级为复制链接。
///
/// 协议必须先过 [isSafeDownloadTarget]：下载地址来自外部元数据或后台配置，
/// `javascript:` 与 `data:text/html` 直接交给 `window.open` 会在本页执行脚本。
bool openDownloadUrl(String url) {
  final trimmed = url.trim();
  if (!isSafeDownloadTarget(trimmed)) {
    return false;
  }
  return web.window.open(trimmed, '_blank', 'noopener,noreferrer') != null;
}
