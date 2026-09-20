import 'package:flutter/services.dart';

import 'package:omninest/core/utils/clipboard_fallback_stub.dart'
    if (dart.library.js_interop) 'package:omninest/core/utils/clipboard_fallback_web.dart'
    as fallback;

/// 写入系统剪贴板，成功返回 true。
///
/// Web 端 Flutter 的 [Clipboard.setData] 依赖 navigator.clipboard，
/// 仅在安全上下文（https 或 localhost）可用；局域网 http 访问时抛
/// PlatformException(copy_fail)。此时回退到 DOM execCommand 复制，
/// 调用点必须处于用户手势回调内。
Future<bool> copyTextToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on Exception {
    return fallback.clipboardFallbackCopy(text);
  }
}
