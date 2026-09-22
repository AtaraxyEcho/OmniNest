import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';

class AuthClient {
  AuthClient(Object client, {String? clientPlatform})
    : _dio = client is ApiClient ? client.dio : client as Dio,
      _clientPlatform = clientPlatform ?? _defaultPlatform();

  final Dio _dio;
  final String _clientPlatform;

  /// 检测当前平台标识，用于后端同平台会话互斥。
  /// Web 使用 "web"，原生端使用具体平台名（android/ios/windows/macos/linux）。
  static String _defaultPlatform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      _ => 'native',
    };
  }

  Future<AuthLoginResult> login({
    required String username,
    required String password,
  }) async {
    final data = await _postUnwrapped('/auth/login', {
      'username': username,
      'password': password,
    });
    return AuthLoginResult.fromJson(data);
  }

  /// 两步验证登录第二步：验证码或备份码换取令牌。
  Future<AuthTokenResponse> verifyTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    final data = await _postUnwrapped('/auth/login/2fa', {
      'challengeToken': challengeToken,
      'code': code,
    });
    return AuthTokenResponse.fromJson(data);
  }

  /// 注册引导：用 enroll 挑战令牌生成 TOTP 秘钥。
  Future<TwoFactorSetupData> bootstrapTwoFactorSetup({
    required String challengeToken,
    required String password,
  }) async {
    final data = await _postUnwrapped('/auth/login/2fa/setup', {
      'challengeToken': challengeToken,
      'password': password,
    });
    return TwoFactorSetupData.fromJson(data);
  }

  /// 注册引导：确认验证码启用，返回备份码与完成令牌。
  Future<TwoFactorBootstrapEnableData> bootstrapTwoFactorEnable({
    required String challengeToken,
    required String code,
  }) async {
    final data = await _postUnwrapped('/auth/login/2fa/enable', {
      'challengeToken': challengeToken,
      'code': code,
    });
    return TwoFactorBootstrapEnableData.fromJson(data);
  }

  /// 注册引导：确认保存备份码后完成登录。
  Future<AuthTokenResponse> completeTwoFactorEnrollment({
    required String finalizeToken,
  }) async {
    final data = await _postUnwrapped('/auth/login/2fa/complete', {
      'finalizeToken': finalizeToken,
    });
    return AuthTokenResponse.fromJson(data);
  }

  Future<AuthTokenResponse> refresh({String? refreshToken}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data:
          refreshToken == null || refreshToken.isEmpty
              ? null
              : {'refreshToken': refreshToken},
      options: _credentialOptions(),
    );

    return parseAuthResponse(response.data);
  }

  /// 退出登录：吊销服务端刷新会话；Web 端由后端清除 HttpOnly Cookie。
  /// 原生端传入本地保存的刷新令牌，Web 端留空走 Cookie 通道。
  Future<void> logout({String? refreshToken}) async {
    await _dio.post<Map<String, dynamic>>(
      '/auth/logout',
      data:
          refreshToken == null || refreshToken.isEmpty
              ? null
              : {'refreshToken': refreshToken},
      options: _credentialOptions(),
    );
  }

  AuthTokenResponse parseAuthResponse(Map<String, dynamic>? body) {
    return AuthTokenResponse.fromJson(_unwrap(body));
  }

  /// 拉取当前用户资料；头像/显示名在其他设备变更后的实时重拉入口。
  Future<UserProfile> currentUser() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return UserProfile.fromJson(_unwrap(response.data));
  }

  /// 修改当前用户密码。
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '/me/password',
      data: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
  }

  Future<Map<String, dynamic>> _postUnwrapped(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: _credentialOptions(),
    );
    return _unwrap(response.data);
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回认证结果');
    }
    final code = body['code'];
    final message = body['message']?.toString() ?? '认证失败';
    if (code != 200) {
      throw AppException(
        code: code?.toString() ?? 'AUTH_ERROR',
        message: message,
      );
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '认证结果格式不正确');
    }
    return data;
  }

  /// 认证请求公共选项。携带凭据 Cookie（Web 端 HttpOnly 刷新令牌通道）。
  /// 自定义请求头必须与后端 CORS allowedHeaders 白名单保持一致：
  /// 新增头若不在白名单内，跨源预检会被浏览器拦截，表现为刷新必失败。
  Options _credentialOptions() {
    return Options(
      headers: {'X-Client-Platform': _clientPlatform},
      extra: {'withCredentials': true},
    );
  }
}
