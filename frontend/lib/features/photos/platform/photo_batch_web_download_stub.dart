/// 非 Web 平台不支持浏览器原生下载。
Future<void> downloadPhotoBatchInBrowser({
  required String url,
  required String fileName,
}) {
  throw UnsupportedError('当前平台不支持浏览器原生下载');
}
