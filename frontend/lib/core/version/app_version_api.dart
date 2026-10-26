import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/version/app_version_compare.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/errors/app_exception.dart';

/// 应用版本检查响应。
class AppVersionInfo {
  const AppVersionInfo({
    this.latestVersion,
    this.releaseNotesUrl,
    this.downloadUrl,
  });

  final String? latestVersion;
  final String? releaseNotesUrl;
  final String? downloadUrl;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final raw = value?.toString();
      return raw == null || raw.trim().isEmpty ? null : raw.trim();
    }

    return AppVersionInfo(
      latestVersion: text(json['latestVersion']),
      releaseNotesUrl: text(json['releaseNotesUrl']),
      downloadUrl: text(json['downloadUrl']),
    );
  }
}

/// 应用版本检查 API（公开端点）。
class AppVersionApi {
  const AppVersionApi(this.apiClient);

  final ApiClient apiClient;

  /// 查询管理员配置的最新客户端版本信息。
  Future<AppVersionInfo> version() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/app/version',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '版本信息加载失败');
    final data = response.data!['data'];
    if (data is! Map) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '版本信息格式不正确');
    }
    final info = AppVersionInfo.fromJson(Map<String, dynamic>.from(data));
    final latestVersion = info.latestVersion;
    if (latestVersion == null) {
      return info;
    }
    final localVersion = await _localVersion();
    if (localVersion == null || isNewerVersion(latestVersion, localVersion)) {
      return info;
    }
    // 服务端配置的版本不高于当前安装版本时不算“发现新版本”，
    // 否则降级场景也会引导用户下载更旧的包。
    return AppVersionInfo(
      releaseNotesUrl: info.releaseNotesUrl,
      downloadUrl: info.downloadUrl,
    );
  }

  Future<String?> _localVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } on Object {
      // 测试或缺少平台通道时退回服务端结论，不因取不到本地版本而阻断检查更新。
      return null;
    }
  }
}

final appVersionApiProvider = Provider<AppVersionApi>((ref) {
  return AppVersionApi(ref.watch(apiClientProvider));
});
