import 'package:web/web.dart' as web;

/// Web 非安全上下文（http 且非 localhost 源）没有 navigator.clipboard，
/// Clipboard.setData 会抛 copy_fail；回退到旧 execCommand 复制。
/// 调用点都处于用户点击回调内，满足 execCommand 的用户手势要求。
bool clipboardFallbackCopy(String text) {
  final web.HTMLTextAreaElement textarea;
  try {
    textarea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
  } catch (_) {
    return false;
  }
  textarea.value = text;
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  textarea.style.left = '-9999px';
  web.document.body?.appendChild(textarea);
  textarea.select();
  try {
    return web.document.execCommand('copy');
  } catch (_) {
    return false;
  } finally {
    textarea.remove();
  }
}
