import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';

/// 天气与定位上报 API。
class WeatherApi {
  const WeatherApi(this._client);

  final ApiClient _client;

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
