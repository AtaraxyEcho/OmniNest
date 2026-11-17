import 'package:web/web.dart' as web;

/// 通过浏览器原生下载能力保存照片批量 ZIP。
Future<void> downloadPhotoBatchInBrowser({
  required String url,
  required String fileName,
}) async {
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = fileName
        ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
