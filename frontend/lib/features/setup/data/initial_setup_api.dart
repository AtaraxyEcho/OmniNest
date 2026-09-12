import 'package:dio/dio.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/setup/domain/initial_setup_status.dart';

class InitialSetupApi {
  const InitialSetupApi(this._client);

  final ApiClient _client;

  Future<InitialSetupStatus> status() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/setup/status',
      options: _publicOptions,
    );
    final data = _parseEnvelope(response.data)['data'];
    if (data is! Map) {
      throw const AppException(
        code: 'SETUP_STATUS_INVALID',
        message: '安装状态响应格式不正确',
      );
    }
    return InitialSetupStatus.fromJson(Map<String, dynamic>.from(data));
  }

  /// 安装向导生成两步验证秘钥，返回秘钥与扫码 URI。
  Future<TwoFactorSetupData> newTwoFactorSecret({String? username}) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/setup/2fa/secret',
      data: username == null ? null : {'username': username},
      options: _publicOptions,
    );
    final data = _parseEnvelope(response.data)['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(
        code: 'SETUP_SECRET_INVALID',
        message: '两步验证秘钥响应格式不正确',
      );
    }
    return TwoFactorSetupData.fromJson(data);
  }

  /// 创建超管；安装向导要求两步验证时传秘钥与确认码，返回一次性备份码。
  Future<List<String>?> createSuperAdmin({
    required String setupToken,
    required String username,
    required String displayName,
    required String email,
    required String password,
    String instanceName = 'OmniNest',
    String defaultLocale = 'zh-CN',
    String defaultTimezone = 'Asia/Shanghai',
    String? totpSecret,
    String? totpCode,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/setup/super-admin',
      data: {
        'username': username,
        'displayName': displayName,
        'email': email.isEmpty ? null : email,
        'password': password,
        'instanceName': instanceName,
        'defaultLocale': defaultLocale,
        'defaultTimezone': defaultTimezone,
        if (totpSecret != null) 'totpSecret': totpSecret,
        if (totpCode != null) 'totpCode': totpCode,
      },
      options: _publicOptions.copyWith(headers: {'X-Setup-Token': setupToken}),
    );
    final data = _parseEnvelope(response.data)['data'];
    if (data is Map && data['backupCodes'] is List) {
      return (data['backupCodes'] as List)
          .map((item) => item.toString())
          .toList();
    }
    return null;
  }

  Map<String, dynamic> _parseEnvelope(Map<String, dynamic>? body) {
    final envelope = body ?? const <String, dynamic>{};
    final code = envelope['code'];
    if (code is num && code.toInt() >= 400) {
      throw AppException(
        code: code.toInt().toString(),
        message: envelope['message']?.toString() ?? '安装请求失败',
      );
    }
    return envelope;
  }

  static final _publicOptions = Options(
    extra: {ApiClient.skipAuthorizationKey: true},
  );
}
