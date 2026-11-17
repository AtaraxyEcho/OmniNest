import 'package:dio/dio.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/realtime/realtime_models.dart';

/// 同步协调器依赖的远端数据接口。
abstract interface class RealtimeRemoteDataSource {
  Future<RealtimeBootstrap> bootstrap();

  Future<RealtimeEventPage> events({required int after, int limit = 200});

  Future<RealtimeHead> head();
}

/// 同步游标和补偿事件 REST 客户端。
class RealtimeApi implements RealtimeRemoteDataSource {
  RealtimeApi(this._apiClient);

  final ApiClient _apiClient;

  /// 获取首次同步高水位。
  @override
  Future<RealtimeBootstrap> bootstrap() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/sync/bootstrap',
    );
    return RealtimeBootstrap.fromJson(_payload(response));
  }

  /// 按游标获取当前用户可见的事件页。
  @override
  Future<RealtimeEventPage> events({
    required int after,
    int limit = 200,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/sync/events',
      queryParameters: {'after': after, 'limit': limit},
    );
    return RealtimeEventPage.fromJson(_payload(response));
  }

  /// 获取低频链路检查使用的同步高水位。
  @override
  Future<RealtimeHead> head() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/sync/head',
    );
    return RealtimeHead.fromJson(_payload(response));
  }

  Map<String, dynamic> _payload(Response<Map<String, dynamic>> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;
    final payload = data?['data'];
    if (status < 200 || status >= 300 || payload is! Map) {
      throw DioException.badResponse(
        statusCode: status,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    return Map<String, dynamic>.from(payload);
  }
}
