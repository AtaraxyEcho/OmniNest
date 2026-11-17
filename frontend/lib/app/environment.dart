import 'package:omninest/app/platform_origin_stub.dart'
    if (dart.library.js_interop) 'package:omninest/app/platform_origin_web.dart'
    as platform;

class AppEnvironment {
  const AppEnvironment({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    this.webBaseUrl,
    this.basePrefix = '/',
  });

  /// 解析构建期预置（--dart-define）与浏览器同源来源。
  ///
  /// 返回 null 表示既无预置也无法同源推导：服务器未配置，由路由层
  /// 引导进入首启配置页（此前 release 缺预置启动即抛错的行为废弃）。
  static AppEnvironment? fromDefinesOrNull() {
    const configuredApiBaseUrl = String.fromEnvironment(
      'OMNINEST_API_BASE_URL',
    );
    const configuredWsBaseUrl = String.fromEnvironment('OMNINEST_WS_BASE_URL');
    const configuredWebBaseUrl = String.fromEnvironment(
      'OMNINEST_WEB_BASE_URL',
    );
    final browserOrigin = platform.getBrowserOrigin();
    if (configuredApiBaseUrl.isEmpty &&
        _normalizeHttpOrigin(browserOrigin) == null) {
      return null;
    }
    return AppEnvironment.resolve(
      configuredApiBaseUrl: configuredApiBaseUrl,
      configuredWsBaseUrl: configuredWsBaseUrl,
      configuredWebBaseUrl: configuredWebBaseUrl,
      browserOrigin: browserOrigin,
    );
  }

  factory AppEnvironment.resolve({
    String configuredApiBaseUrl = '',
    String configuredWsBaseUrl = '',
    String configuredWebBaseUrl = '',
    String? browserOrigin,
    String? pagePath,
  }) {
    final normalizedOrigin = _normalizeHttpOrigin(browserOrigin);
    // 子路径部署（--base-href=/omninest/）下同源接口同样带前缀，否则只有
    // 资源走前缀、API 仍打站点根。
    final pagePrefix = _normalizePrefix(pagePath ?? platform.getPageBasePath());
    final apiBaseUrl =
        configuredApiBaseUrl.isNotEmpty
            ? configuredApiBaseUrl
            : normalizedOrigin == null
            ? 'http://localhost:8080/api/v1'
            : _replaceOriginPath(normalizedOrigin, '${pagePrefix}api/v1');
    // 显式配置 API 时（桌面端与运行时配置）没有页面路径可读，前缀只能从
    // API 地址自身剥出。
    final prefix =
        configuredApiBaseUrl.isNotEmpty
            ? _prefixFromApiPath(Uri.tryParse(configuredApiBaseUrl)?.path ?? '')
            : pagePrefix;
    // WS 回退链：显式配置 > 浏览器同源 > 从 API 基地址同域推导
    // （release 脚本只传 API 时 WS 自动跟随；调试无配置时 localhost 行为不变）。
    final wsSource = normalizedOrigin ?? Uri.parse(apiBaseUrl);
    final wsBaseUrl =
        configuredWsBaseUrl.isNotEmpty
            ? configuredWsBaseUrl
            : _replaceOriginPath(
              wsSource,
              '${prefix}ws',
              scheme: wsSource.scheme == 'https' ? 'wss' : 'ws',
            );
    final webBaseUrl =
        configuredWebBaseUrl.isNotEmpty ? configuredWebBaseUrl : null;
    return AppEnvironment(
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
      webBaseUrl: webBaseUrl,
      basePrefix: prefix,
    );
  }

  final String apiBaseUrl;
  final String wsBaseUrl;

  /// 分享链接基地址。
  /// 未配置时使用浏览器当前站点（Web 平台）或 apiBaseUrl（其他平台）。
  final String? webBaseUrl;

  /// 站点内路径前缀，形如 `/omninest/`；根部署为 `/`。
  final String basePrefix;

  String get effectiveWebBaseUrl {
    if (webBaseUrl != null) {
      return webBaseUrl!;
    }
    final browserOrigin = platform.getBrowserOrigin();
    if (browserOrigin != null) {
      return _trimTrailingSlash('$browserOrigin$basePrefix');
    }
    // 桌面端退化：分享页挂在前端站点而非 API，须剥离「前缀 + api/v1」，
    // 否则链接形如 host/omninest/api/v1/#/s/xxx，浏览器仅请求该路径会命中
    // 受保护接口返回 401。
    return _webBaseFromApiBaseUrl(apiBaseUrl);
  }

  static String _normalizePrefix(String raw) {
    if (raw.isEmpty) {
      return '/';
    }
    final withLeading = raw.startsWith('/') ? raw : '/$raw';
    return withLeading.endsWith('/') ? withLeading : '$withLeading/';
  }

  /// 从 API 路径反推站点前缀：`/omninest/api/v1` 得 `/omninest/`，非该形态按根处理。
  static String _prefixFromApiPath(String path) {
    const apiSuffix = '/api/v1';
    if (!path.endsWith(apiSuffix)) {
      return '/';
    }
    return _normalizePrefix(path.substring(0, path.length - apiSuffix.length));
  }

  static String _webBaseFromApiBaseUrl(String apiBaseUrl) {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.hasAuthority) {
      return apiBaseUrl;
    }
    final prefix = _prefixFromApiPath(uri.path);
    if (prefix == '/') {
      return uri.origin;
    }
    return _trimTrailingSlash('${uri.origin}$prefix');
  }

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/') && value.length > 1) {
      return value.substring(0, value.length - 1);
    }
    return value;
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
