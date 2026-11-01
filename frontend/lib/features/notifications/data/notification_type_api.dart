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

  /// 管理员更新通知类型；未传字段保持原值，这里只切换启用状态。
  Future<NotificationTypeConfig> updateType(
    String id, {
    required bool enabled,
  }) async {
    final response = await _client.dio.put<Map<String, dynamic>>(
      '/notification-types/$id',
      data: {'enabled': enabled},
    );
    final data = response.data;
    ensureEnvelopeSuccess(data, fallbackMessage: '通知类型更新失败');
    final raw = data!['data'];
    if (raw is! Map<String, dynamic>) {
      throw StateError('通知类型响应格式不正确');
    }
    return NotificationTypeConfig.fromJson(raw);
  }
}
