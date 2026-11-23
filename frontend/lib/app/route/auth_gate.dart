import 'package:omninest/core/auth/redirect_target.dart';

/// 服务器配置、安装与登录三重门控的纯函数决策层。
/// 从 `router.dart` 拆出以控制单文件行数；路由只负责读 provider 后调用。
/// 服务器配置门控决策；返回 null 表示放行进入后续安装/登录门控链。
///
/// 非 Web 端在服务器配置加载期间停泊在引导页（避免空环境下业务页面
/// 瞬时构建，也避免安装向导在已配置实例上闪现数秒）；加载完成且未
/// 配置才进入 /server-setup 并保留 redirect 目标（配置完成后经登录页
/// 续跳）；已配置后访问引导页则按认证状态回到登录或目标页；携带
/// switch=1 的显式切换请求放行（设置页更换服务器入口使用，覆盖预置
/// 存在时 clear 后回落预置导致引导页不可达的死角）。
/// Web 恒有同源推导，不经过服务器门控。
String? serverGateRedirectPath({
  required bool isWeb,
  required bool isConfigLoading,
  required bool isConfigured,
  required bool isAuthenticated,
  required String location,
}) {
  final uri = Uri.parse(location);
  final path = uri.path;
  if (!isWeb) {
    // 配置在途：停泊引导页（带 redirect 目标），已配置实例不再闪现
    // 安装向导；判定完成且未配置才落 /server-setup。
    if (isConfigLoading) {
      // /login 必须一并放行：否则 server gate 把它送进 /boot，auth gate
      // 又从 /boot 送回 /login，形成永不落地的重定向环（仅原生端）。
      if (const ['/boot', '/login', '/server-setup'].contains(path)) {
        return null;
      }
      final target = location == '/' ? '/portal' : location;
      return Uri(
        path: '/boot',
        queryParameters: {'redirect': target},
      ).toString();
    }
    if (!isConfigured) {
      return path == '/server-setup' ? null : _serverSetupLocation(uri);
    }
  }
  if (path == '/server-setup') {
    if (uri.queryParameters['switch'] == '1') {
      return null;
    }
    final target = _safeRedirectTarget(uri.queryParameters['redirect']);
    if (isAuthenticated) {
      return target ?? '/portal';
    }
    return target == null
        ? '/login'
        : Uri(path: '/login', queryParameters: {'redirect': target}).toString();
  }
  return null;
}

String _serverSetupLocation(Uri uri) {
  // 配置加载期间深链先停在 /boot?redirect=...；配置完成后必须解包内层目标，
  // 否则会把 /boot 自身再次编码进 redirect，最终被 _safeRedirectTarget 拒绝。
  if (uri.path == '/boot') {
    final inner = _safeRedirectTarget(uri.queryParameters['redirect']);
    if (inner == null || inner == '/' || inner == '/portal') {
      return '/server-setup';
    }
    return Uri(
      path: '/server-setup',
      queryParameters: {'redirect': inner},
    ).toString();
  }
  final target = uri.toString();
  if (target == '/' || uri.path == '/server-setup' || uri.path == '/login') {
    return '/server-setup';
  }
  return Uri(
    path: '/server-setup',
    queryParameters: {'redirect': target},
  ).toString();
}

/// 认证与安装门控决策；返回 null 表示放行。
///
/// [canAccessAdminConsole] 由调用方经 `canAccessAdminConsoleProvider` 求得
/// （权限与手机形态的统一事实源），本函数只做路由侧决策。
String? authRedirectPath({
  required bool isChecking,
  required bool isAuthenticated,
  required String location,
  required bool canAccessAdminConsole,
  bool isSetupChecking = false,
  bool setupRequired = false,
}) {
  if (isChecking || isSetupChecking) {
    // 认证/安装检查在途：仅放行公开路径，受保护路径停泊到引导页。
    // 避免页面在无凭据状态下构建并发起必然 401 的首批请求——这是
    // Web 刷新后被强制登出的直接诱因。
    final uri = Uri.parse(location);
    final path = uri.path;
    if (path == '/boot' || _isPublicPath(path) || path == '/server-setup') {
      return null;
    }
    final target = location == '/' ? '/portal' : location;
    return Uri(path: '/boot', queryParameters: {'redirect': target}).toString();
  }

  final uri = Uri.parse(location);
  final path = uri.path;
  final isLogin = path == '/login';

  if (setupRequired) {
    return path == '/setup' ? null : '/setup';
  }
  if (path == '/boot') {
    // 检查已结束：按认证结果落位到原目标或登录页。
    final target = _safeRedirectTarget(uri.queryParameters['redirect']);
    if (!isAuthenticated) {
      return Uri(
        path: '/login',
        queryParameters: {'redirect': target ?? '/portal'},
      ).toString();
    }
    return target ?? '/portal';
  }
  if (path == '/setup') {
    return isAuthenticated ? '/portal' : '/login';
  }

  if (isAuthenticated && isLogin) {
    return _safeRedirectTarget(uri.queryParameters['redirect']) ?? '/portal';
  }

  // 公开路径不做任何重定向
  if (_isPublicPath(path)) {
    return null;
  }

  if (!isAuthenticated && !_isPublicPath(path)) {
    final target = location == '/' ? '/portal' : location;
    return Uri(
      path: '/login',
      queryParameters: {'redirect': target},
    ).toString();
  }

  // 管理页面：入口判定统一走 canAccessAdminConsoleProvider（权限 +
  // 手机形态）；分区细粒度由页面权限校验
  if (isAuthenticated && path.startsWith('/admin')) {
    if (!canAccessAdminConsole) {
      return '/portal';
    }
  }

  return null;
}

bool _isPublicPath(String path) {
  return path == '/login' ||
      path == '/setup' ||
      path.startsWith('/shared/photos/') ||
      path.startsWith('/s/');
}

String? _safeRedirectTarget(String? redirect) => safeRedirectTarget(redirect);
