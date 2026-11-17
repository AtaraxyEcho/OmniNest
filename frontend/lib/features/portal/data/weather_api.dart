import 'package:dio/dio.dart';
import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';

class WeatherCitySuggestion {
  const WeatherCitySuggestion({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

/// 天气与定位上报 API。
class WeatherApi {
  WeatherApi(this._client)
    : _geocodingClient = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

  final ApiClient _client;
  final Dio _geocodingClient;

  /// 通过无凭据地理编码接口搜索城市，不向外部服务发送 OmniNest 会话令牌。
  Future<List<WeatherCitySuggestion>> searchCities(
    String query, {
    required String language,
    CancelToken? cancelToken,
  }) async {
    final response = await _geocodingClient.get<Map<String, dynamic>>(
      'https://geocoding-api.open-meteo.com/v1/search',
      queryParameters: {
        'name': query,
        'count': 6,
        'language': language,
        'format': 'json',
      },
      cancelToken: cancelToken,
    );
    final rows = response.data?['results'];
    if (rows is! List) return const <WeatherCitySuggestion>[];
    return rows
        .whereType<Map>()
        .map((row) {
          final name = row['name']?.toString() ?? '';
          final region = row['admin1']?.toString();
          final country = row['country']?.toString();
          final latitude = row['latitude'];
          final longitude = row['longitude'];
          if (name.isEmpty || latitude is! num || longitude is! num) {
            return null;
          }
          return WeatherCitySuggestion(
            name: [
              name,
              if (region != null && region.isNotEmpty && region != name) region,
              if (country != null && country.isNotEmpty) country,
            ].join(', '),
            latitude: latitude.toDouble(),
            longitude: longitude.toDouble(),
          );
        })
        .whereType<WeatherCitySuggestion>()
        .toList(growable: false);
  }

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
