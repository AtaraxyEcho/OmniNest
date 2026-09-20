import 'package:omninest/app/environment.dart';

/// 用户配置的目标服务器连接信息。
///
/// [apiBaseUrl] 为规范化后的 API 基地址（以 /api/v1 结尾）；
/// [wsBaseUrl] 与 [webBaseUrl] 为可选显式覆盖，缺省时由 AppEnvironment 推导。
class ServerConfig {
  const ServerConfig({
    required this.apiBaseUrl,
    this.wsBaseUrl,
    this.webBaseUrl,
  });

  /// 持久化结构版本；字段语义变化时递增并在 fromJson 做迁移。
  static const int schemaVersion = 1;

  /// 构建期 HTTPS-only 开关（--dart-define=OMNINEST_REQUIRE_HTTPS）。
  /// 为 true 时规范化层拒绝 http 地址，公网定制构建以此杜绝明文出口。
  static const bool requireHttpsByBuild = bool.fromEnvironment(
    'OMNINEST_REQUIRE_HTTPS',
  );

  final String apiBaseUrl;
  final String? wsBaseUrl;
  final String? webBaseUrl;

  /// 由该配置派生运行环境；WS 与分享基址未显式覆盖时按同域规则推导。
  AppEnvironment toAppEnvironment() {
    return AppEnvironment.resolve(
      configuredApiBaseUrl: apiBaseUrl,
      configuredWsBaseUrl: wsBaseUrl ?? '',
      configuredWebBaseUrl: webBaseUrl ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'apiBaseUrl': apiBaseUrl,
      if (wsBaseUrl != null) 'wsBaseUrl': wsBaseUrl,
      if (webBaseUrl != null) 'webBaseUrl': webBaseUrl,
    };
  }

  /// 解析持久化 JSON；结构版本不符或地址未通过当前构建校验时返回 null，
  /// 调用方按未配置处理（严格构建读到历史 http 配置即视为未配置）。
  static ServerConfig? fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] is! int ||
        json['schemaVersion'] != schemaVersion) {
      return null;
    }
    final api = json['apiBaseUrl'];
    if (api is! String) {
      return null;
    }
    final ws = json['wsBaseUrl'];
    final web = json['webBaseUrl'];
    return tryParse(
      api,
      wsBaseUrl: ws is String ? ws : null,
      webBaseUrl: web is String ? web : null,
    );
  }

  /// 规范化用户输入的服务器地址；无法解析或违反当前构建约束时返回 null。
  ///
  /// 接受三种形态：host、host:port、完整 URL。无 scheme 时端口 443 默认
  /// https、其余默认 http（内网自托管为主场景）；路径包含 /api/v1 段时
  /// 截断至该段（容忍粘贴完整端点 URL），否则自动补齐；IPv6 字面量需
  /// 方括号。requireHttps 缺省取构建期开关。
  static ServerConfig? tryParse(
    String raw, {
    String? wsBaseUrl,
    String? webBaseUrl,
    bool? requireHttps,
  }) {
    final api = _normalizeApiBaseUrl(raw, requireHttps ?? requireHttpsByBuild);
    if (api == null) {
      return null;
    }
    final ws = _normalizeOptionalUrl(
      wsBaseUrl,
      allowedSchemes: const {'ws', 'wss'},
    );
    if (ws == _invalidUrl) {
      return null;
    }
    final web = _normalizeOptionalUrl(
      webBaseUrl,
      allowedSchemes: const {'http', 'https'},
    );
    if (web == _invalidUrl) {
      return null;
    }
    return ServerConfig(apiBaseUrl: api, wsBaseUrl: ws, webBaseUrl: web);
  }

  static const String _invalidUrl = '\u0000invalid';

  static String? _normalizeApiBaseUrl(String raw, bool requireHttps) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) {
      return null;
    }
    var candidate = trimmed;
    if (!candidate.contains('://')) {
      final scheme = trimmed.endsWith(':443') ? 'https' : 'http';
      candidate = '$scheme://$trimmed';
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    if (scheme == 'http' && requireHttps) {
      return null;
    }
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final apiSegmentIndex = path.indexOf('/api/v1');
    if (apiSegmentIndex >= 0) {
      path = path.substring(0, apiSegmentIndex + '/api/v1'.length);
    } else if (path.isEmpty) {
      path = '/api/v1';
    } else {
      path = '$path/api/v1';
    }
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  /// 规范化可选覆盖地址：空白视为未覆盖（null），格式非法返回哨兵 [_invalidUrl]。
  static String? _normalizeOptionalUrl(
    String? raw, {
    required Set<String> allowedSchemes,
  }) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return _invalidUrl;
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path, query: null, fragment: null).toString();
  }
}
