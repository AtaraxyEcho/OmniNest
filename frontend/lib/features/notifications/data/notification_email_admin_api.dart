import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';

/// 通知邮件通道管理 API：按当前 SMTP 配置发送测试邮件。
class NotificationEmailAdminApi {
  const NotificationEmailAdminApi(this._client);

  final ApiClient _client;

  /// 收件人为空时由服务端发送给当前管理员绑定的邮箱。
  Future<void> sendTest({String? to}) async {
    final recipient = to?.trim() ?? '';
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/admin/notifications/email-test',
      data: {if (recipient.isNotEmpty) 'to': recipient},
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '测试邮件发送失败');
  }
}
