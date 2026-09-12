import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/router.dart';

/// OmniNest 自定义协议深链白名单前缀。
///
/// 仅允许直达分享、书籍详情与影片播放页；受保护路由由路由器认证守卫兜底。
const List<String> deepLinkAllowedPrefixes = <String>[
  '/s/',
  '/shared/photos/',
  '/reader/items/',
  '/video/',
];

/// 将 omninest:// 链接解析为应用内路由路径。
///
/// 返回 null 表示链接不在白名单内或格式不合法。
String? resolveDeepLinkPath(Uri uri) {
  if (uri.scheme.toLowerCase() != 'omninest') {
    return null;
  }
  final host = uri.host.trim();
  final path = uri.path;
  if (host.isEmpty || path.isEmpty || path == '/') {
    return null;
  }
  final route = '/$host$path';
  if (route.contains('..') || route.contains('//')) {
    return null;
  }
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
          debugPrint('[DeepLink] 链接流错误: $error');
        }
      },
    );
  }

  void _handle(Uri uri) {
    final route = resolveDeepLinkPath(uri);
    if (route == null) {
      if (kDebugMode) {
        debugPrint('[DeepLink] 拒绝非白名单深链: $uri');
      }
      return;
    }
    _router.go(route);
  }

  void dispose() {
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
