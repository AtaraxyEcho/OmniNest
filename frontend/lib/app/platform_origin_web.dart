import 'package:web/web.dart' as web;

/// 获取浏览器当前页面的 origin（scheme + host + port）。
String? getBrowserOrigin() => web.window.location.origin;

/// 获取站点内页面路径前缀：`--base-href=/omninest/` 部署返回 `/omninest/`，
/// 根部署返回 `/`。子路径部署下 API 与 WS 必须跟着同一前缀，否则请求会打到
/// 站点根上未被反代暴露的路径。
String getPageBasePath() {
  final baseUri = Uri.tryParse(web.document.baseURI);
  final path =
      (baseUri != null && baseUri.path.isNotEmpty)
          ? baseUri.path
          : Uri.base.path;
  return path.isEmpty ? '/' : path;
}
