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
    final wsBaseUrl =
        configuredWsBaseUrl.isNotEmpty
            ? configuredWsBaseUrl
            : normalizedOrigin == null
            ? 'ws://localhost:8080/ws'
            : _replaceOriginPath(
              normalizedOrigin,
              '/ws',
              scheme: normalizedOrigin.scheme == 'https' ? 'wss' : 'ws',
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
