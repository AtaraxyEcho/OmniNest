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
    final data = response.data?['data'];
    if (data is! Map) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '版本信息格式不正确');
    }
    return AppVersionInfo.fromJson(Map<String, dynamic>.from(data));
  }
}

final appVersionApiProvider = Provider<AppVersionApi>((ref) {
  return AppVersionApi(ref.watch(apiClientProvider));
});
