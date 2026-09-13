import 'package:web/web.dart' as web;

/// Web 端在新标签页打开下载页。
void openDownloadUrl(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
