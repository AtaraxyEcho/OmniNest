import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_weather_profile.dart';

void main() {
  WeatherData weather(String windDir) {
    return WeatherData(
      temp: 20,
      feelsLike: 20,
      text: '晴',
      icon: '100',
      humidity: '50',
      windSpeed: '1',
      windDir: windDir,
      pressure: '1000',
      visibility: '10',
      uvIndex: 1,
      sunrise: '06:00',
      sunset: '18:00',
      aqi: 10,
      pm2p5: 5,
      aqiCategory: '优',
      updateTime: '2026-10-25 12:00',
    );
  }

  test('wind direction accepts Chinese, English and compass abbreviations', () {
    expect(PortalWeatherProfile.from(weather('静风')).wind, 0);
    expect(PortalWeatherProfile.from(weather('东北风')).wind, -0.41);
    expect(PortalWeatherProfile.from(weather('SSW')).wind, 0.32);
    expect(PortalWeatherProfile.from(weather('northeast')).wind, -0.41);
    expect(PortalWeatherProfile.from(weather('E')).wind, -0.58);
  });

  test('wind direction accepts numeric degrees and falls back safely', () {
    expect(PortalWeatherProfile.from(weather('45°')).wind, -0.41);
    expect(PortalWeatherProfile.from(weather('270')).wind, 0.58);
    expect(PortalWeatherProfile.from(weather('unknown')).wind, 0.08);
  });
}
