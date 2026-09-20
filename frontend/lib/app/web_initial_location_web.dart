import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// 读取 index.html 在引擎归一化 history 之前捕获的原始地址，
/// 解析 hash 深链作为冷启动初始路由。
///
/// 返回 null 表示无有效深链（裸根路径访问），由调用方回落到门户。
String? readWebInitialLocation() {
  final initialHref =
      (globalContext.getProperty('__omninestInitialHref'.toJS) as JSString?)
          ?.toDart;
  if (initialHref == null) {
    return null;
  }
  final fragment = Uri.parse(initialHref).fragment;
  return fragment.startsWith('/') ? fragment : null;
}
