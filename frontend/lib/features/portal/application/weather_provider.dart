import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/portal/application/weather_preferences_controller.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 天气图标映射（和风图标代码 → Material 矢量图标）。
///
/// 使用矢量图标而非 emoji：Web 端 emoji 字体在首次绘制时才从外部
/// CDN 下载（详情页首开约 1 秒空白），离线/内网部署则永久空白。
IconData weatherIconFromCode(String icon) {
  final iconCode = int.tryParse(icon) ?? 999;
  if (iconCode == 100) return Icons.wb_sunny_outlined;
  if (iconCode == 101 || iconCode == 102) {
    return Icons.cloud_queue_outlined;
  }
  if (iconCode == 103 || iconCode == 104 || iconCode == 154) {
    return Icons.cloud_outlined;
  }
  if (iconCode >= 150 && iconCode <= 153) return Icons.nightlight_round;
  if (iconCode >= 300 && iconCode < 400) return Icons.water_drop_outlined;
  if (iconCode >= 400 && iconCode < 500) return Icons.ac_unit_outlined;
  if (iconCode >= 500) return Icons.blur_on_outlined;
  return Icons.wb_cloudy_outlined;
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

  IconData get weatherIcon => weatherIconFromCode(icon);

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

  IconData get weatherIcon => weatherIconFromCode(iconDay);

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
  IconData get weatherIcon => weatherIconFromCode(icon);
}

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
      devLog('上报位置失败: $e');
    }

    return location;
  } catch (e) {
    devLog('获取位置失败: $e');
    return null;
  }
});

/// 实时天气 Provider（调用后端代理）
///
/// 不在前端读取管理端配置：和风凭据与 weather.enabled 均由后端配置中心处理。
/// 仅在有 GPS 数据时传 location 参数，否则由后端走 fallback 链。
final realtimeWeatherProvider = FutureProvider<WeatherData>((ref) async {
  final location = await ref.watch(userLocationProvider.future);
  // 后端可能因 GPS 优先而未回填地区名，这里用用户偏好城市兜底。
  final preferredCity = ref.watch(weatherLocationProvider).asData?.value ?? '';

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
    devLog('获取天气失败: $e');
    return WeatherData.empty();
  }
});
