import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';

/// 通知类型配置 API 客户端。
class NotificationTypeApi {
  const NotificationTypeApi(this._client);

  final ApiClient _client;

  /// 查询所有启用的通知类型。
  Future<List<NotificationTypeConfig>> list() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/notification-types',
    );
    final data = response.data;
    ensureEnvelopeSuccess(data, fallbackMessage: '通知类型加载失败');
    final items = data!['data'] as List<dynamic>?;
    if (items == null || items.isEmpty) {
      return NotificationTypeConfig.fallbackTypes;
    }
    return items
        .map((e) => NotificationTypeConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 查询所有通知类型（包括已禁用的）。
  Future<List<NotificationTypeConfig>> listAll() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/notification-types/all',
    );
    final data = response.data;
    ensureEnvelopeSuccess(data, fallbackMessage: '通知类型加载失败');
    final items = data!['data'] as List<dynamic>?;
    if (items == null || items.isEmpty) {
      return NotificationTypeConfig.fallbackTypes;
    }
    return items
        .map((e) => NotificationTypeConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
