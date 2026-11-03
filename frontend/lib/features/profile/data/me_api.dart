import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/profile/domain/user_session.dart';

/// 当前用户 API 客户端。
class MeApi {
  const MeApi(this._client);

  final ApiClient _client;

  /// 上传头像，返回 presigned 下载 URL。
  Future<String> uploadAvatar(Uint8List bytes, String fileName) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await _client.dio.put<Map<String, dynamic>>(
      '/me/avatar',
      data: formData,
    );
    final data = response.data;
    ensureEnvelopeSuccess(data, fallbackMessage: '头像上传失败');
    return data!['data']?.toString() ?? '';
  }

  /// 修改当前用户密码。
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final response = await _client.dio.put<Map<String, dynamic>>(
      '/me/password',
      data: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '修改密码失败');
  }

  /// 更新当前用户基础资料（显示昵称 / 邮箱）；未提供的字段不变。
  Future<void> updateMe({String? displayName, String? email}) async {
    final response = await _client.dio.patch<Map<String, dynamic>>(
      '/me',
      data: {
        if (displayName != null) 'displayName': displayName,
        if (email != null) 'email': email,
      },
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '更新资料失败');
  }

  /// 查询两步验证状态（是否已开启、策略是否强制当前角色）。
  Future<TwoFactorStatusData> twoFactorStatus() async {
    return TwoFactorStatusData.fromJson(await _getData('/me/2fa/status'));
  }

  /// 自助生成两步验证秘钥（密码复核）。
  Future<TwoFactorSetupData> twoFactorSetup({required String password}) async {
    return TwoFactorSetupData.fromJson(
      await _postData('/me/2fa/setup', {'password': password}),
    );
  }

  /// 自助确认开启两步验证，返回一次性备份码。
  Future<List<String>> twoFactorEnable({required String code}) async {
    final data = await _postData('/me/2fa/enable', {'code': code});
    final codes = data['backupCodes'];
    return codes is List
        ? codes.map((item) => item.toString()).toList()
        : const <String>[];
  }

  /// 关闭两步验证（密码与验证码双重复核）。后端为 Void 响应（data 为空），
  /// 不得走要求 data 为对象的 _postData 解包。
  Future<void> twoFactorDisable({
    required String password,
    required String code,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/me/2fa/disable',
      data: {'password': password, 'code': code},
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '关闭两步验证失败');
  }

  Future<Map<String, dynamic>> _getData(String path) async {
    final response = await _client.dio.get<Map<String, dynamic>>(path);
    return _unwrap(response.data);
  }

  Future<Map<String, dynamic>> _postData(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: body,
    );
    return _unwrap(response.data);
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? body) {
    return requireEnvelopeData(
      body,
      fallbackMessage: '认证操作失败',
      invalidMessage: '响应格式不正确',
    );
  }

  /// 获取当前用户的活跃会话列表。
  Future<List<UserSession>> getSessions() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/me/sessions',
    );
    final data = response.data;
    ensureEnvelopeSuccess(data, fallbackMessage: '会话列表加载失败');
    final list = data!['data'];
    if (list is! List) {
      throw const FormatException('会话列表格式不正确');
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map(UserSession.fromJson)
        .toList();
  }

  /// 撤销指定会话（主动登出其他设备）。
  Future<void> revokeSession(String sessionId) async {
    final response = await _client.dio.delete<Map<String, dynamic>>(
      '/me/sessions/$sessionId',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '撤销会话失败');
  }

  /// 获取服务器配置的对外 Web 基址（分享链接用）；未配置时返回 null。
  Future<String?> webShareBaseUrl() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/me/web-share-base-url',
    );
    // 本类其余方法都做信封校验：漏掉这一步会把 401/403 当成“未配置分享基址”，
    // 用户看到的分享链接静默退化为本机地址。
    ensureEnvelopeSuccess(response.data, fallbackMessage: '获取分享链接基址失败');
    final data = response.data?['data'];
    if (data is String && data.isNotEmpty) {
      return data;
    }
    return null;
  }
}
