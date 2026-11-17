/// 登录回跳目标的安全校验。
///
/// 路由守卫与登录页必须共用同一判据：任何一处更宽松都会让
/// `/?redirect=...` 变成外部跳转或内部状态页的入口。
library;

/// 返回可安全回跳的站内路径；不合法时返回 null。
String? safeRedirectTarget(String? redirect) {
  if (redirect == null || redirect.isEmpty) {
    return null;
  }
  // 反斜杠与协议相对地址都可能被浏览器解释成外部跳转；控制路由不能作为登录回跳目标。
  if (!redirect.startsWith('/') ||
      redirect.startsWith('//') ||
      redirect.contains('\\') ||
      redirect.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  final uri = Uri.tryParse(redirect);
  if (uri == null) {
    return null;
  }
  final path = uri.path;
  if (path == '/login' ||
      path.startsWith('/login/') ||
      path == '/boot' ||
      path == '/setup' ||
      path == '/server-setup') {
    return null;
  }
  return redirect;
}
