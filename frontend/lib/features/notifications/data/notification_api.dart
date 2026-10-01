import 'package:dio/dio.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/capability_gate_interceptor.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';

class NotificationApi {
  NotificationApi(this._client);

  final ApiClient _client;

  Future<({List<NotificationDto> items, int total})> list({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {
        'page': page,
        'size': size,
        if (unreadOnly) 'unreadOnly': true,
      },
    );
    final data = response.data;
    if (data == null) return (items: <NotificationDto>[], total: 0);
    final envelope = data['data'] as Map<String, dynamic>?;
    if (envelope == null) return (items: <NotificationDto>[], total: 0);
    final list =
        (envelope['items'] as List<dynamic>? ?? [])
            .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
            .toList();
    final total = (envelope['totalElements'] as num?)?.toInt() ?? 0;
    return (items: list, total: total);
  }

  Future<int> unreadCount() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/notifications/unread-count',
    );
    final data = response.data;
    if (data == null) return 0;
    return (data['data'] as num?)?.toInt() ?? 0;
  }

  /// 标记通知已读（用户主动写）：无能力时抛 FORBIDDEN，禁止假成功。
  Future<void> markRead(List<String> ids) async {
    _client.requirePermission(activityWritePermission);
    final response = await _client.dio.put<Map<String, dynamic>>(
      '/notifications/read',
      data: {'ids': ids},
    );
    _requireSuccess(response.data);
  }

  /// 全部标为已读（用户主动写）：无能力时抛 FORBIDDEN。
  Future<void> markAllRead() async {
    _client.requirePermission(activityWritePermission);
    final response = await _client.dio.put<Map<String, dynamic>>(
      '/notifications/read-all',
    );
    _requireSuccess(response.data);
  }

  /// 删除通知（用户主动写）：无能力时抛 FORBIDDEN，禁止假成功。
  Future<void> deleteNotification(String notificationId) async {
    _client.requirePermission(activityWritePermission);
    final response = await _client.dio.delete<Map<String, dynamic>>(
      '/notifications/$notificationId',
    );
    _requireSuccess(response.data);
  }

  /// 清空通知（用户主动写）：无能力时抛 FORBIDDEN。
  Future<void> clearAll() async {
    _client.requirePermission(activityWritePermission);
    try {
      final response = await _client.dio.delete<Map<String, dynamic>>(
        '/notifications',
      );
      _requireSuccess(response.data);
    } on DioException catch (error) {
      throw _toAppException(error);
    }
  }

  AppException _toAppException(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final code = data['code'];
      final message = data['message']?.toString();
      return AppException(
        code:
            code?.toString() ??
            error.response?.statusCode?.toString() ??
            'NOTIFICATION_ERROR',
        message: message?.isNotEmpty == true ? message! : '通知操作失败',
      );
    }
    return AppException(
      code: error.response?.statusCode?.toString() ?? 'NOTIFICATION_ERROR',
      message: error.message?.isNotEmpty == true ? error.message! : '通知操作失败',
    );
  }

  void _requireSuccess(Map<String, dynamic>? body) {
    final envelope = body ?? const <String, dynamic>{};
    final code = envelope['code'];
    if (code is num && code.toInt() >= 400) {
      throw AppException(
        code: code.toInt().toString(),
        message: envelope['message']?.toString() ?? '通知操作失败',
      );
    }
  }
}
