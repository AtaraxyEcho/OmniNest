/// 从浏览器原始地址中取出应用内路由。
///
/// 本构建走 hash 路由（未启用 `usePathUrlStrategy`），深链形如
/// `https://host/[base]/#/reader/items/<id>`，因此只看 fragment。
///
/// 解析必须是容错的：地址可能来自手工粘贴、被中间代理截断或被扩展改写，
/// `Uri.parse` 直接抛 `FormatException` 会让启动阶段白屏，回落到门户即可。
String? parseWebInitialLocation(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null) {
    return null;
  }
  final fragment = uri.fragment;
  if (fragment.isEmpty || !fragment.startsWith('/')) {
    return null;
  }
  return fragment;
}
