import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 通过浏览器原生下载能力保存 CSV，返回文件名。
Future<String?> saveAdminCsvBytes({
  required String suggestedName,
  required Uint8List bytes,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = suggestedName
        ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // 部分浏览器在 click() 之后才异步启动下载；同步 revoke 会让下载拿到
  // 已失效的 blob URL。延后一个短窗再释放，既保证下载成功也不长期持有 Blob。
  unawaited(
    Future<void>.delayed(const Duration(seconds: 1), () {
      web.URL.revokeObjectURL(url);
    }),
  );
  return suggestedName;
}
