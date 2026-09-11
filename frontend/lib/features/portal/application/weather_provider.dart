import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/portal/application/weather_preferences_controller.dart';

/// 天气图标映射（和风图标代码 → emoji）
String weatherIconFromCode(String icon) {
  final iconCode = int.tryParse(icon) ?? 999;
  if (iconCode == 100) return '☀️';
  if (iconCode == 101 || iconCode == 102) return '⛅';
  if (iconCode == 103 || iconCode == 104) return '☁️';
  if (iconCode >= 150 && iconCode <= 153) return '🌙';
  if (iconCode >= 300 && iconCode < 400) return '🌧️';
  if (iconCode >= 400 && iconCode < 500) return '🌨️';
  if (iconCode >= 500) return '🌫️';
  return '🌤️';
}

/// 逐小时预报条目。
class WeatherHourly {
  const WeatherHourly({
    required this.time,
    required this.temp,
    required this.icon,
    required this.text,
  });

  final String time;
  final int temp;
  final String icon;
  final String text;

  String get weatherIcon => weatherIconFromCode(icon);

  /// 显示用时间：ISO 时间取 HH:mm，否则原样展示。
  String get displayTime {
    final tIndex = time.indexOf('T');
    if (tIndex >= 0 && tIndex + 6 <= time.length) {
      return time.substring(tIndex + 1, tIndex + 6);
    }
    return time;
  }

  factory WeatherHourly.fromJson(Map<String, dynamic> json) {
    return WeatherHourly(
      time: json['time'] as String? ?? '--',
      temp: (json['temp'] as num?)?.toInt() ?? 0,
      icon: json['icon'] as String? ?? '999',
      text: json['text'] as String? ?? '--',
    );
  }
}

/// 逐日预报条目。
class WeatherDaily {
  const WeatherDaily({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.iconDay,
    required this.textDay,
    required this.iconNight,
    required this.textNight,
  });

  final String date;
  final int tempMax;
  final int tempMin;
  final String iconDay;
  final String textDay;
  final String iconNight;
  final String textNight;

  String get weatherIcon => weatherIconFromCode(iconDay);

  factory WeatherDaily.fromJson(Map<String, dynamic> json) {
    return WeatherDaily(
      date: json['date'] as String? ?? '--',
      tempMax: (json['tempMax'] as num?)?.toInt() ?? 0,
      tempMin: (json['tempMin'] as num?)?.toInt() ?? 0,
      iconDay: json['iconDay'] as String? ?? '999',
      textDay: json['textDay'] as String? ?? '--',
      iconNight: json['iconNight'] as String? ?? '999',
      textNight: json['textNight'] as String? ?? '--',
    );
  }
}

/// 天气数据模型
class WeatherData {
  const WeatherData({
    required this.temp,
    required this.feelsLike,
    required this.text,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
    required this.windDir,
    required this.pressure,
    required this.visibility,
    required this.uvIndex,
    required this.sunrise,
    required this.sunset,
    required this.aqi,
    required this.pm2p5,
    required this.aqiCategory,
    required this.updateTime,
    this.healthAdvice = '',
    this.tempMax = 0,
    this.tempMin = 0,
    this.precip = '--',
    this.windScale = '--',
    this.textDay = '--',
    this.textNight = '--',
    this.hourly = const [],
    this.daily = const [],
    this.locationName = '',
  });

  final int temp;
  final int feelsLike;
  final String text;
  final String icon;
  final String humidity;
  final String windSpeed;
  final String windDir;
  final String pressure;
  final String visibility;
  final int uvIndex;
  final String sunrise;
  final String sunset;
  final int aqi;
  final int pm2p5;
  final String aqiCategory;
  final String updateTime;
  final String healthAdvice;
  final int tempMax;
  final int tempMin;
  final String precip;
  final String windScale;
  final String textDay;
  final String textNight;
  final List<WeatherHourly> hourly;
  final List<WeatherDaily> daily;

  /// 可读地区名（城市），GPS 直连时可能为空。
  final String locationName;

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final hourlyRaw = json['hourly'] as List<dynamic>? ?? const [];
    final dailyRaw = json['daily'] as List<dynamic>? ?? const [];
    return WeatherData(
      temp: (json['temp'] as num?)?.toInt() ?? 0,
      feelsLike: (json['feelsLike'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '未知',
      icon: json['icon'] as String? ?? '999',
      humidity: json['humidity'] as String? ?? '--',
      windSpeed: json['windSpeed'] as String? ?? '--',
      windDir: json['windDir'] as String? ?? '',
      pressure: json['pressure'] as String? ?? '--',
      visibility: json['visibility'] as String? ?? '--',
      uvIndex: json['uvIndex'] as int? ?? 0,
      sunrise: json['sunrise'] as String? ?? '--',
      sunset: json['sunset'] as String? ?? '--',
      aqi: json['aqi'] as int? ?? 0,
      pm2p5: json['pm2p5'] as int? ?? 0,
      aqiCategory: json['aqiCategory'] as String? ?? '--',
      updateTime: json['updateTime'] as String? ?? '',
      healthAdvice: json['healthAdvice'] as String? ?? '',
      tempMax: (json['tempMax'] as num?)?.toInt() ?? 0,
      tempMin: (json['tempMin'] as num?)?.toInt() ?? 0,
      precip: json['precip'] as String? ?? '--',
      windScale: json['windScale'] as String? ?? '--',
      textDay: json['textDay'] as String? ?? '--',
      textNight: json['textNight'] as String? ?? '--',
      hourly: [
        for (final item in hourlyRaw)
          if (item is Map<String, dynamic>) WeatherHourly.fromJson(item),
      ],
      daily: [
        for (final item in dailyRaw)
          if (item is Map<String, dynamic>) WeatherDaily.fromJson(item),
      ],
      locationName: json['locationName'] as String? ?? '',
    );
  }

  static WeatherData empty() {
    return const WeatherData(
      temp: 0,
      feelsLike: 0,
      text: '加载中',
      icon: '999',
      humidity: '--',
      windSpeed: '--',
      windDir: '--',
      pressure: '--',
      visibility: '--',
      uvIndex: 0,
      sunrise: '--',
      sunset: '--',
      aqi: 0,
      pm2p5: 0,
      aqiCategory: '--',
      updateTime: '',
      healthAdvice: '',
      tempMax: 0,
      tempMin: 0,
      precip: '--',
      windScale: '--',
      textDay: '--',
      textNight: '--',
    );
  }

  /// AQI 等级颜色（int 值）
  int get aqiColor {
    if (aqi <= 50) return 0xFF00897B;
    if (aqi <= 100) return 0xFFF9A825;
    if (aqi <= 150) return 0xFFEF6C00;
    if (aqi <= 200) return 0xFFD32F2F;
    if (aqi <= 300) return 0xFF7B1FA2;
    return 0xFF4E342E;
  }

  /// AQI 等级颜色（Color 对象，安全转换）
  Color get aqiColorValue => Color(aqiColor);

  /// 天气图标映射
  String get weatherIcon => weatherIconFromCode(icon);
}

/// 天气配置
class WeatherConfig {
  const WeatherConfig({required this.enabled, required this.defaultLocation});

  final bool enabled;
  final String defaultLocation;
}

/// 从配置中心读取天气配置
final weatherConfigProvider = FutureProvider<WeatherConfig>((ref) async {
  final adminApi = ref.watch(adminOperationsApiProvider);
  final configView = await adminApi.configs();

  String getConfig(String key, String defaultValue) {
    try {
      final entry = configView.items.firstWhere((c) => c.key == key);
      return entry.value.isNotEmpty ? entry.value : defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  bool getBoolConfig(String key, bool defaultValue) {
    final value = getConfig(key, defaultValue.toString());
    return value.toLowerCase() == 'true';
  }

  return WeatherConfig(
    enabled: getBoolConfig('weather.enabled', false),
    defaultLocation: getConfig('weather.location', '北京'),
  );
});

/// 用户 GPS 位置 Provider（请求权限并获取经纬度）
/// 返回 null 表示无 GPS 数据，由后端走 fallback 链（用户偏好 > 配置中心）
final userLocationProvider = FutureProvider<String?>((ref) async {
  try {
    if (kIsWeb) {
      // Web 端无 GPS，返回 null 让后端使用用户偏好或配置默认值
      return null;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );

    final location =
        '${position.longitude.toStringAsFixed(2)},${position.latitude.toStringAsFixed(2)}';

    // 上报位置到后端（供桌面端等其他设备共享）
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.post(
        '/weather/location',
        data: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'source':
              defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS
                  ? 'mobile'
                  : 'desktop',
        },
      );
    } catch (e) {
      debugPrint('上报位置失败: $e');
    }

    return location;
  } catch (e) {
    debugPrint('获取位置失败: $e');
    return null;
  }
});

/// 实时天气 Provider（调用后端代理）
/// 仅在有 GPS 数据时传 location 参数，否则由后端走 fallback 链
final realtimeWeatherProvider = FutureProvider<WeatherData>((ref) async {
  final configAsync = ref.watch(weatherConfigProvider);
  final enabled = configAsync.whenOrNull(data: (c) => c.enabled) ?? false;

  if (!enabled) {
    return WeatherData.empty();
  }

  final location = await ref.watch(userLocationProvider.future);
  // 后端可能因 GPS 优先而未回填地区名，这里用用户偏好城市兜底。
  final preferredCity =
      ref.watch(weatherLocationProvider).asData?.value ?? '';

  try {
    final apiClient = ref.watch(apiClientProvider);
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/weather/realtime',
      queryParameters: {if (location != null) 'location': location},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data!;
      if (data['code'] == 200 && data['data'] != null) {
        final weather = WeatherData.fromJson(
          data['data'] as Map<String, dynamic>,
        );
        if (weather.locationName.isNotEmpty || preferredCity.isEmpty) {
          return weather;
        }
        return WeatherData(
          temp: weather.temp,
          feelsLike: weather.feelsLike,
          text: weather.text,
          icon: weather.icon,
          humidity: weather.humidity,
          windSpeed: weather.windSpeed,
          windDir: weather.windDir,
          pressure: weather.pressure,
          visibility: weather.visibility,
          uvIndex: weather.uvIndex,
          sunrise: weather.sunrise,
          sunset: weather.sunset,
          aqi: weather.aqi,
          pm2p5: weather.pm2p5,
          aqiCategory: weather.aqiCategory,
          updateTime: weather.updateTime,
          healthAdvice: weather.healthAdvice,
          tempMax: weather.tempMax,
          tempMin: weather.tempMin,
          precip: weather.precip,
          windScale: weather.windScale,
          textDay: weather.textDay,
          textNight: weather.textNight,
          hourly: weather.hourly,
          daily: weather.daily,
          locationName: preferredCity,
        );
      }
    }
    return WeatherData.empty();
  } catch (e) {
    debugPrint('获取天气失败: $e');
    return WeatherData.empty();
  }
});
