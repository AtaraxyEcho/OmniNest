import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/platform/desktop/desktop_deep_link_bridge.dart';
import 'package:omninest/core/log/dev_log.dart';

/// OmniNest 自定义协议深链白名单前缀。
///
/// 仅允许直达分享、书籍详情与影片播放页；受保护路由由路由器认证守卫兜底。
const List<String> deepLinkAllowedPrefixes = <String>[
  '/s/',
  '/shared/photos/',
  '/reader/items/',
  '/video/',
];

/// 路径段里不允许出现的控制字符。
final RegExp _deepLinkControlChars = RegExp(r'[\x00-\x1f\x7f]');

/// 将 omninest:// 链接解析为应用内路由路径。
///
/// 返回 null 表示链接不在白名单内或格式不合法。
///
/// 判定必须基于已解码的 [Uri.pathSegments]：`Uri.path` 保留百分号编码，
/// `omninest://video/%2e%2e/admin` 用字面量 `..` 检查拦不住，而交给
/// [GoRouter.go] 时会被解码并归一化，等于越过白名单直达受保护路由。
/// 重新按段编码后再比对前缀，保证「校验的形状」就是「交给路由的形状」。
String? resolveDeepLinkPath(Uri uri) {
  if (uri.scheme.toLowerCase() != 'omninest') {
    return null;
  }
  final host = uri.host.trim();
  if (host.isEmpty || uri.pathSegments.isEmpty) {
    return null;
  }
  final segments = <String>[host, ...uri.pathSegments];
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(r'\') ||
        _deepLinkControlChars.hasMatch(segment)) {
      return null;
    }
  }
  final route = '/${segments.map(Uri.encodeComponent).join('/')}';
  for (final prefix in deepLinkAllowedPrefixes) {
    if (route.startsWith(prefix) ||
        route == prefix.substring(0, prefix.length - 1)) {
      return route;
    }
  }
  return null;
}

/// 深链服务：接住冷启动初始链接与运行期链接流，落位到 GoRouter。
class DeepLinkService {
  DeepLinkService({required GoRouter router, AppLinks? links})
    : _router = router,
      _links = links ?? AppLinks();

  final GoRouter _router;
  final AppLinks _links;
  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    desktopDeepLinkHandler = _handle;
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } on Object {
      // 平台不支持（桌面未注册协议等）时静默跳过冷启动链接。
    }
    _subscription = _links.uriLinkStream.listen(
      _handle,
      onError: (Object error) {
        if (kDebugMode) {
          devLog('[DeepLink] 链接流错误: $error');
        }
      },
    );
  }

  /// 处理外部深链（含桌面第二实例转发）。
  void handleExternal(Uri uri) {
    _handle(uri);
  }

  void _handle(Uri uri) {
    if (uri.scheme.toLowerCase() != 'omninest') {
      // Web 端 app_links 会把当前页面 URL 作为初始链接与流事件重复上报，
      // 非 omninest 协议一律静默忽略，避免每次启动重复输出拒绝日志。
      return;
    }
    final route = resolveDeepLinkPath(uri);
    if (route == null) {
      if (kDebugMode) {
        devLog('[DeepLink] 拒绝非白名单深链: $uri');
      }
      return;
    }
    _router.go(route);
  }

  void dispose() {
    desktopDeepLinkHandler = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _started = false;
  }
}

/// 挂接深链服务的 Riverpod 入口：在应用根 watch 一次持续生效。
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(router: ref.read(appRouterProvider));
  ref.onDispose(service.dispose);
  unawaited(service.start());
  return service;
});
