import 'package:omninest/features/portal/application/weather_provider.dart';

enum PortalWeatherType {
  sunny,
  cloudy,
  rain,
  storm,
  snow,
  fog,
  haze,
  dust,
  heat,
  cold,
  none,
}

enum PortalWeatherTime { dawn, day, dusk, night }

bool hasSamePortalWeatherVisuals(WeatherData? left, WeatherData? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return left == right;
  }
  return left.icon == right.icon &&
      left.windDir == right.windDir &&
      left.sunrise == right.sunrise &&
      left.sunset == right.sunset &&
      left.precip == right.precip &&
      left.windScale == right.windScale &&
      left.text == right.text &&
      left.updateTime == right.updateTime;
}

class PortalWeatherProfile {
  const PortalWeatherProfile({
    required this.type,
    required this.wind,
    required this.intensity,
    this.time = PortalWeatherTime.day,
    this.heavy = false,
  });

  final PortalWeatherType type;
  final double wind;
  final double intensity;
  final PortalWeatherTime time;
  final bool heavy;

  bool get isNight => time == PortalWeatherTime.night;

  bool get isDawn => time == PortalWeatherTime.dawn;

  bool get isDusk => time == PortalWeatherTime.dusk;

  bool get isTransition =>
      time == PortalWeatherTime.dawn || time == PortalWeatherTime.dusk;

  double get shaderDayPhase {
    return switch (time) {
      PortalWeatherTime.dawn => 0.25,
      PortalWeatherTime.day => 0,
      PortalWeatherTime.dusk => 0.5,
      PortalWeatherTime.night => 1,
    };
  }

  double get shaderType {
    return switch (type) {
      PortalWeatherType.none => 0,
      PortalWeatherType.sunny => 1,
      PortalWeatherType.cloudy => 2,
      PortalWeatherType.rain => 3,
      PortalWeatherType.storm => 4,
      PortalWeatherType.snow => 5,
      PortalWeatherType.fog => 6,
      PortalWeatherType.haze => 7,
      PortalWeatherType.dust => 8,
      PortalWeatherType.heat => 9,
      PortalWeatherType.cold => 10,
    };
  }

  static PortalWeatherProfile from(WeatherData? weather) {
    if (weather == null || weather.updateTime.isEmpty) {
      return const PortalWeatherProfile(
        type: PortalWeatherType.none,
        wind: 0.16,
        intensity: 0.32,
      );
    }
    final code = int.tryParse(weather.icon) ?? 999;
    final wind = _resolveWind(weather.windDir);
    final time = _resolveWeatherTime(
      weather.sunrise,
      weather.sunset,
      iconCode: code,
    );
    if (_isClearCode(code)) {
      return PortalWeatherProfile(
        type: PortalWeatherType.sunny,
        wind: wind,
        intensity: 0.30,
        time: time,
      );
    }
    if (_isCloudCode(code)) {
      final heavy = code == 104 || code == 154;
      return PortalWeatherProfile(
        type: PortalWeatherType.cloudy,
        wind: wind,
        intensity: heavy ? 0.64 : 0.44,
        time: time,
        heavy: heavy,
      );
    }
    if (code >= 300 && code < 400) {
      final storm = _isStormRainCode(code);
      final intensity = _rainIntensityForCode(code);
      return PortalWeatherProfile(
        type: storm ? PortalWeatherType.storm : PortalWeatherType.rain,
        wind: wind,
        intensity: intensity,
        time: time,
        heavy: intensity >= 0.70,
      );
    }
    if (code >= 400 && code < 500) {
      final intensity = _snowIntensityForCode(code);
      return PortalWeatherProfile(
        type: PortalWeatherType.snow,
        wind: wind * (intensity >= 0.72 ? 0.72 : 0.50),
        intensity: intensity,
        time: time,
        heavy: intensity >= 0.72,
      );
    }
    if (_isHazeCode(code)) {
      return PortalWeatherProfile(
        type: PortalWeatherType.haze,
        wind: wind * 0.36,
        intensity: 0.82,
        time: time,
        heavy: true,
      );
    }
    if (_isDustCode(code)) {
      return PortalWeatherProfile(
        type: PortalWeatherType.dust,
        wind: wind == 0 ? 0.42 : wind,
        intensity: 0.78,
        time: time,
        heavy: true,
      );
    }
    if (_isFogCode(code)) {
      final intensity = _fogIntensityForCode(code);
      return PortalWeatherProfile(
        type: PortalWeatherType.fog,
        wind: wind * 0.36,
        intensity: intensity,
        time: time,
        heavy: intensity >= 0.72,
      );
    }
    if (_isExtremeTemperatureCode(code)) {
      return PortalWeatherProfile(
        type: code == 900 ? PortalWeatherType.heat : PortalWeatherType.cold,
        wind: wind,
        intensity: code == 900 ? 0.58 : 0.26,
        time: time,
        heavy: code == 900,
      );
    }
    return PortalWeatherProfile(
      type: PortalWeatherType.cloudy,
      wind: wind,
      intensity: 0.42,
      time: time,
    );
  }
}

enum WeatherScene {
  sunny,
  partlyCloudy,
  cloudy,
  rain,
  storm,
  snow,
  fog,
  haze,
  dust,
  heat,
  cold,
}

/// Portal 天气视觉统一规格。
class WeatherSceneSpec {
  const WeatherSceneSpec({
    required this.profile,
    required this.scene,
    required this.shaderType,
    required this.shaderDayPhase,
    required this.intensity,
    required this.wind,
    required this.heavy,
    required this.cloudCount,
    required this.rainFarCount,
    required this.rainNearCount,
    required this.snowCount,
    required this.dockRippleCount,
    required this.dockSplashCount,
    required this.snowCapGrowthSeconds,
    required this.interactionParticleColor,
  });

  final PortalWeatherProfile profile;
  final WeatherScene scene;
  final double shaderType;
  final double shaderDayPhase;
  final double intensity;
  final double wind;
  final bool heavy;
  final int cloudCount;
  final int rainFarCount;
  final int rainNearCount;
  final int snowCount;
  final int dockRippleCount;
  final int dockSplashCount;
  final double snowCapGrowthSeconds;
  final int interactionParticleColor;

  bool get isRain => scene == WeatherScene.rain || scene == WeatherScene.storm;

  bool get isSnow => scene == WeatherScene.snow;

  static WeatherSceneSpec from(WeatherData? weather) {
    return fromProfile(PortalWeatherProfile.from(weather));
  }

  static WeatherSceneSpec fromProfile(PortalWeatherProfile profile) {
    final scene = _resolveScene(profile);
    final intensity = profile.intensity.clamp(0.0, 1.0);
    final heavy = profile.heavy || scene == WeatherScene.storm;
    return WeatherSceneSpec(
      profile: profile,
      scene: scene,
      shaderType: profile.shaderType,
      shaderDayPhase: profile.shaderDayPhase,
      intensity: intensity,
      wind: profile.wind.clamp(-1.0, 1.0),
      heavy: heavy,
      cloudCount: _cloudCount(scene, heavy),
      rainFarCount: (18 + intensity * 14 + (heavy ? 6 : 0)).round(),
      rainNearCount: (5 + intensity * 6 + (heavy ? 3 : 0)).round(),
      snowCount: (12 + intensity * 26 + (heavy ? 8 : 0)).round(),
      dockRippleCount: heavy ? 28 : (12 + intensity * 14).round(),
      dockSplashCount: heavy ? 16 : (8 + intensity * 10).round(),
      snowCapGrowthSeconds: heavy ? 8 : 14,
      interactionParticleColor: _interactionParticleColor(scene, profile),
    );
  }
}

WeatherScene _resolveScene(PortalWeatherProfile profile) {
  return switch (profile.type) {
    PortalWeatherType.sunny => WeatherScene.sunny,
    PortalWeatherType.cloudy =>
      profile.heavy ? WeatherScene.cloudy : WeatherScene.partlyCloudy,
    PortalWeatherType.rain => WeatherScene.rain,
    PortalWeatherType.storm => WeatherScene.storm,
    PortalWeatherType.snow => WeatherScene.snow,
    PortalWeatherType.fog => WeatherScene.fog,
    PortalWeatherType.haze => WeatherScene.haze,
    PortalWeatherType.dust => WeatherScene.dust,
    PortalWeatherType.heat => WeatherScene.heat,
    PortalWeatherType.cold => WeatherScene.cold,
    PortalWeatherType.none => WeatherScene.partlyCloudy,
  };
}

int _cloudCount(WeatherScene scene, bool heavy) {
  return switch (scene) {
    WeatherScene.cloudy => heavy ? 9 : 6,
    WeatherScene.rain => heavy ? 8 : 6,
    WeatherScene.storm => 10,
    WeatherScene.snow => 6,
    WeatherScene.cold => 5,
    WeatherScene.partlyCloudy => 4,
    WeatherScene.sunny ||
    WeatherScene.fog ||
    WeatherScene.haze ||
    WeatherScene.dust ||
    WeatherScene.heat => 3,
  };
}

int _interactionParticleColor(
  WeatherScene scene,
  PortalWeatherProfile profile,
) {
  if (scene == WeatherScene.snow) {
    return 0xFFFFFFFF;
  }
  if (scene == WeatherScene.rain || scene == WeatherScene.storm) {
    return profile.isNight ? 0xFFCFEFFF : 0xFF80CBC4;
  }
  return 0xFFFFFFFF;
}

PortalWeatherTime _resolveWeatherTime(
  String sunrise,
  String sunset, {
  required int iconCode,
}) {
  if (_isNightWeatherCode(iconCode)) {
    return PortalWeatherTime.night;
  }
  final now = DateTime.now();
  final currentMinutes = now.hour * 60 + now.minute;
  final sunriseMinutes = _parseClockMinutes(sunrise);
  final sunsetMinutes = _parseClockMinutes(sunset);
  if (sunriseMinutes != null && sunsetMinutes != null) {
    if (sunriseMinutes == 0 && sunsetMinutes >= 23 * 60 + 50) {
      return PortalWeatherTime.day;
    }
    final dawnStart = sunriseMinutes - 50;
    final dawnEnd = sunriseMinutes + 60;
    final duskStart = sunsetMinutes - 60;
    final duskEnd = sunsetMinutes + 50;
    if (currentMinutes < dawnStart || currentMinutes > duskEnd) {
      return PortalWeatherTime.night;
    }
    if (currentMinutes >= dawnStart && currentMinutes <= dawnEnd) {
      return PortalWeatherTime.dawn;
    }
    if (currentMinutes >= duskStart && currentMinutes <= duskEnd) {
      return PortalWeatherTime.dusk;
    }
    return PortalWeatherTime.day;
  }
  if (now.hour < 5 || now.hour >= 19) {
    return PortalWeatherTime.night;
  }
  if (now.hour < 7) {
    return PortalWeatherTime.dawn;
  }
  if (now.hour >= 17) {
    return PortalWeatherTime.dusk;
  }
  return PortalWeatherTime.day;
}

bool _isClearCode(int code) {
  return code == 100 || code == 150;
}

bool _isCloudCode(int code) {
  return code == 101 ||
      code == 102 ||
      code == 103 ||
      code == 104 ||
      code == 151 ||
      code == 152 ||
      code == 153 ||
      code == 154;
}

bool _isNightWeatherCode(int code) {
  return code >= 150 && code <= 154;
}

int? _parseClockMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

bool _isStormRainCode(int code) {
  return code == 302 ||
      code == 303 ||
      code == 304 ||
      code == 310 ||
      code == 311 ||
      code == 312 ||
      code == 317 ||
      code == 318;
}

double _rainIntensityForCode(int code) {
  switch (code) {
    case 305:
    case 309:
      return 0.38;
    case 306:
    case 313:
    case 314:
      return 0.54;
    case 300:
      return 0.62;
    case 301:
    case 307:
    case 315:
      return 0.72;
    case 308:
    case 310:
    case 316:
      return 0.86;
    case 302:
    case 303:
    case 304:
      return 0.94;
    case 311:
    case 312:
    case 317:
    case 318:
      return 0.98;
    default:
      return 0.56;
  }
}

double _snowIntensityForCode(int code) {
  switch (code) {
    case 400:
      return 0.38;
    case 401:
    case 407:
    case 408:
      return 0.54;
    case 404:
    case 405:
    case 406:
      return 0.62;
    case 402:
    case 409:
      return 0.76;
    case 403:
    case 410:
      return 0.94;
    default:
      return 0.50;
  }
}

bool _isFogCode(int code) {
  return code == 500 ||
      code == 501 ||
      code == 509 ||
      code == 510 ||
      code == 514 ||
      code == 515;
}

bool _isHazeCode(int code) {
  return code == 502 || code == 511 || code == 512 || code == 513;
}

bool _isDustCode(int code) {
  return code == 503 ||
      code == 504 ||
      code == 507 ||
      code == 508 ||
      (code >= 700 && code < 800);
}

bool _isExtremeTemperatureCode(int code) {
  return code == 900 || code == 901;
}

double _fogIntensityForCode(int code) {
  switch (code) {
    case 500:
    case 501:
    case 509:
    case 514:
    case 515:
      return 0.62;
    case 502:
    case 511:
    case 512:
    case 513:
      return 0.84;
    case 503:
    case 504:
    case 507:
    case 508:
      return 0.78;
    default:
      return 0.70;
  }
}

const List<String> _compassPoints = [
  'N',
  'NNE',
  'NE',
  'ENE',
  'E',
  'ESE',
  'SE',
  'SSE',
  'S',
  'SSW',
  'SW',
  'WSW',
  'W',
  'WNW',
  'NW',
  'NNW',
];

/// 风向对粒子漂移的水平分量；保持既有四方位取值，斜向取中间档。
const Map<String, double> _windOffsets = {
  'N': -0.10,
  'NNE': -0.32,
  'NE': -0.41,
  'ENE': -0.54,
  'E': -0.58,
  'ESE': -0.54,
  'SE': -0.41,
  'SSE': -0.32,
  'S': 0.10,
  'SSW': 0.32,
  'SW': 0.41,
  'WSW': 0.54,
  'W': 0.58,
  'WNW': 0.54,
  'NW': 0.41,
  'NNW': 0.32,
};

double _resolveWind(String windDir) {
  final trimmed = windDir.trim();
  if (trimmed.isEmpty) {
    return 0.08;
  }
  final lower = trimmed.toLowerCase();
  if (trimmed.contains('静') || lower.contains('calm')) {
    return 0;
  }
  final numeric = RegExp(r'^[-+]?\d+(?:\.\d+)?').firstMatch(trimmed);
  if (numeric != null) {
    final angle = double.tryParse(numeric.group(0)!);
    if (angle != null) {
      final normalized = ((angle % 360) + 360) % 360;
      final index = ((normalized + 11.25) ~/ 22.5) % _compassPoints.length;
      return _windOffsets[_compassPoints[index]] ?? 0.08;
    }
  }
  final compact = lower.replaceAll(RegExp(r'[\s_-]'), '').replaceAll('风', '');
  final chinese = <String, String>{
    '东北': 'NE',
    '东南': 'SE',
    '西北': 'NW',
    '西南': 'SW',
    '东': 'E',
    '西': 'W',
    '南': 'S',
    '北': 'N',
  };
  for (final entry in chinese.entries) {
    if (compact.contains(entry.key)) {
      return _windOffsets[entry.value] ?? 0.08;
    }
  }
  final english = <String, String>{
    'northeast': 'NE',
    'southeast': 'SE',
    'northwest': 'NW',
    'southwest': 'SW',
    'north': 'N',
    'south': 'S',
    'east': 'E',
    'west': 'W',
  };
  for (final entry in english.entries) {
    if (lower.contains(entry.key)) {
      return _windOffsets[entry.value] ?? 0.08;
    }
  }
  final upper = compact.toUpperCase();
  if (_windOffsets.containsKey(upper)) {
    return _windOffsets[upper]!;
  }
  return 0.08;
}
