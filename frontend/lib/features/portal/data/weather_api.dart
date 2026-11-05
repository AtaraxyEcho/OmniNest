import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';

/// 天气与定位上报 API。
class WeatherApi {
  const WeatherApi(this._client);

  final ApiClient _client;

  /// 查询实时天气；网关或业务信封不完整时返回 null，由调用方回退空天气。
  Future<Map<String, dynamic>?> fetchRealtime({String? location}) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/weather/realtime',
      queryParameters: {if (location != null) 'location': location},
    );
    if (response.statusCode != 200 || response.data == null) {
      return null;
    }
    final envelope = response.data!;
    if (envelope['code'] != 200 || envelope['data'] is! Map) {
      return null;
    }
    return (envelope['data'] as Map).cast<String, dynamic>();
  }

  /// 上报当前设备位置，供其他设备复用天气位置。
  Future<void> reportLocation({
    required double latitude,
    required double longitude,
    required String source,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/weather/location',
      data: {'latitude': latitude, 'longitude': longitude, 'source': source},
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '位置上报失败');
  }
}
