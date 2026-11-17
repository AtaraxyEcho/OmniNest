import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';

/// 空气质量与紫外线的"缺数据"语义。
///
/// 0 在 AQI / PM2.5 / UV 里都是有意义的最好或最弱档位，缺数据必须保持 null，
/// 否则界面会把"没取到"显示成"空气优"。
void main() {
  test('缺少空气质量字段时保持 null，不落成 0', () {
    final data = WeatherData.fromJson(<String, dynamic>{
      'temp': 20,
      'aqiCategory': '--',
    });

    expect(data.aqi, isNull);
    expect(data.pm2p5, isNull);
    expect(data.uvIndex, isNull);
    expect(data.aqiDisplay, '--');
    expect(data.pm25Display, '--');
    expect(data.uvDisplay, '--');
    expect(data.aqiColorValue, const Color(0xFF8A8A8A));
  });

  test('有空气质量的响应保留数值与分档配色', () {
    final data = WeatherData.fromJson(<String, dynamic>{
      'temp': 26,
      'aqi': 46,
      'pm2p5': 11,
      'uvIndex': 7,
      'aqiCategory': 'Good',
    });

    expect(data.aqiDisplay, '46');
    expect(data.pm25Display, '11');
    expect(data.uvDisplay, '7');
    expect(data.aqiColorValue, const Color(0xFF00897B));
  });

  test('降级空数据不带任何空气质量数值', () {
    final data = WeatherData.empty();

    expect(data.aqi, isNull);
    expect(data.pm2p5, isNull);
    expect(data.uvIndex, isNull);
  });
}
