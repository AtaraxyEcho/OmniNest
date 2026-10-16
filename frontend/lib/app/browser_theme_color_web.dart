import 'dart:ui' show Color;

import 'package:web/web.dart' as web;

/// 同步浏览器界面栏（地址栏/状态栏）配色：写 `<meta name="theme-color">`。
///
/// 页面没有该 meta 时不新建：首屏配色由 `web/index.html` 决定，运行期只负责
/// 跟随应用极性改它的值，不改变页面结构。
void setBrowserThemeColor(Color color) {
  final meta = web.document.querySelector('meta[name="theme-color"]');
  if (meta == null) {
    return;
  }
  final rgb = color.toARGB32() & 0xFFFFFF;
  meta.setAttribute('content', '#${rgb.toRadixString(16).padLeft(6, '0')}');
}
