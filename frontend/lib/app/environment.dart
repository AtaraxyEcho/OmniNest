import 'package:flutter/foundation.dart';
import 'package:omninest/app/platform_origin_stub.dart'
    if (dart.library.js_interop) 'package:omninest/app/platform_origin_web.dart'
    as platform;

class AppEnvironment {
  const AppEnvironment({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    this.webBaseUrl,
  });

  factory AppEnvironment.fromDefines() {
    const configuredApiBaseUrl = String.fromEnvironment(
      'OMNINEST_API_BASE_URL',
    );
    const configuredWsBaseUrl = String.fromEnvironment('OMNINEST_WS_BASE_URL');
    const configuredWebBaseUrl = String.fromEnvironment(
      'OMNINEST_WEB_BASE_URL',
    );
    // 桌面/移动 release 构建必须显式指定服务地址：静默回落 localhost 只会
    // 表现为“连不上服务器”，fail-fast 让漏配在启动瞬间暴露。
    // Web 端有同源推导（browserOrigin 非空），不受此约束。
    if (kReleaseMode &&
        configuredApiBaseUrl.isEmpty &&
        _normalizeHttpOrigin(platform.getBrowserOrigin()) == null) {
      throw StateError(
        '缺少 OMNINEST_API_BASE_URL：桌面/移动 release 构建必须通过 '
        '--dart-define=OMNINEST_API_BASE_URL=<服务端地址> 指定 API 基地址',
      );
    }
    return AppEnvironment.resolve(
      configuredApiBaseUrl: configuredApiBaseUrl,
      configuredWsBaseUrl: configuredWsBaseUrl,
      configuredWebBaseUrl: configuredWebBaseUrl,
      browserOrigin: platform.getBrowserOrigin(),
    );
  }

  factory AppEnvironment.resolve({
    String configuredApiBaseUrl = '',
    String configuredWsBaseUrl = '',
    String configuredWebBaseUrl = '',
    String? browserOrigin,
  }) {
    final normalizedOrigin = _normalizeHttpOrigin(browserOrigin);
    final apiBaseUrl =
        configuredApiBaseUrl.isNotEmpty
            ? configuredApiBaseUrl
            : normalizedOrigin == null
            ? 'http://localhost:8080/api/v1'
            : _replaceOriginPath(normalizedOrigin, '/api/v1');
    // WS 回退链：显式配置 > 浏览器同源 > 从 API 基地址同域推导
    // （release 脚本只传 API 时 WS 自动跟随；调试无配置时 localhost 行为不变）。
    final wsBaseUrl =
        configuredWsBaseUrl.isNotEmpty
            ? configuredWsBaseUrl
            : normalizedOrigin != null
            ? _replaceOriginPath(
              normalizedOrigin,
              '/ws',
              scheme: normalizedOrigin.scheme == 'https' ? 'wss' : 'ws',
            )
            : _replaceOriginPath(
              Uri.parse(apiBaseUrl),
              '/ws',
              scheme: Uri.parse(apiBaseUrl).scheme == 'https' ? 'wss' : 'ws',
            );
    final webBaseUrl =
        configuredWebBaseUrl.isNotEmpty ? configuredWebBaseUrl : null;
    return AppEnvironment(
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
      webBaseUrl: webBaseUrl,
    );
  }

  final String apiBaseUrl;
  final String wsBaseUrl;

  /// 分享链接基地址。
  /// 未配置时使用浏览器当前 origin（Web 平台）或 apiBaseUrl（其他平台）。
  final String? webBaseUrl;

  String get effectiveWebBaseUrl {
    if (webBaseUrl != null) {
      return webBaseUrl!;
    }
    final browserOrigin = platform.getBrowserOrigin();
    if (browserOrigin != null) {
      return browserOrigin;
    }
    // 桌面端退化：分享页挂在前端站点而非 API，须剥离 apiBaseUrl 的路径段，
    // 否则链接形如 host/api/v1/#/s/xxx，浏览器仅请求 /api/v1/ 命中受保护接口返回 401。
    return Uri.parse(apiBaseUrl).origin;
  }

  static Uri? _normalizeHttpOrigin(String? origin) {
    if (origin == null || origin.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  static String _replaceOriginPath(Uri origin, String path, {String? scheme}) {
    return origin
        .replace(scheme: scheme ?? origin.scheme, path: path)
        .toString();
  }
}
