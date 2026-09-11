import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_dialog.dart';

WeatherData _sampleWeather() {
  return const WeatherData(
    temp: 26,
    feelsLike: 28,
    text: '晴',
    icon: '100',
    humidity: '45%',
    windSpeed: '12',
    windDir: '东南',
    pressure: '1012',
    visibility: '18',
    uvIndex: 7,
    sunrise: '05:42',
    sunset: '18:31',
    aqi: 62,
    pm2p5: 28,
    aqiCategory: '良',
    updateTime: '2026-03-01 14:00',
    healthAdvice: '多补水，午间减少暴晒。',
    tempMax: 30,
    tempMin: 18,
    precip: '0',
    windScale: '3',
    textDay: '晴',
    textNight: '多云',
  );
}

Future<void> _openWeatherDetail(WidgetTester tester, {Size? size}) async {
  final viewSize = size ?? const Size(390, 844);
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder:
            (context) => TextButton(
              onPressed:
                  () => showWeatherDetailDialog(
                    context,
                    weather: _sampleWeather(),
                  ),
              child: const Text('打开天气'),
            ),
      ),
    ),
  );

  await tester.tap(find.text('打开天气'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
}

Future<void> _closeWeatherDetail(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('天气详情首帧延迟启动重量级背景动效', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showWeatherDetailDialog(
                      context,
                      weather: WeatherData.empty(),
                    ),
                child: const Text('打开天气'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('打开天气'));
    await tester.pump();

    expect(find.byKey(const ValueKey('weather-scene-effects')), findsNothing);

    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const ValueKey('weather-scene-effects')), findsOneWidget);
  });

  testWidgets('手机尺寸展示核心天气信息并可关闭', (tester) async {
    await _openWeatherDetail(tester, size: const Size(390, 844));

    expect(find.text('26°'), findsOneWidget);
    expect(find.textContaining('AQI 62'), findsOneWidget);
    expect(find.textContaining('晴'), findsWidgets);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await _closeWeatherDetail(tester);

    expect(find.text('26°'), findsNothing);
  });

  testWidgets('桌面宽屏展示关闭按钮与关键指标', (tester) async {
    await _openWeatherDetail(tester, size: const Size(1600, 1000));

    expect(find.text('26°'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.textContaining('湿度'), findsOneWidget);
    expect(find.textContaining('能见度'), findsOneWidget);
  });

  testWidgets('平板尺寸可正常渲染完整详情', (tester) async {
    await _openWeatherDetail(tester, size: const Size(820, 1180));

    expect(find.text('26°'), findsOneWidget);
    expect(find.textContaining('PM2.5'), findsOneWidget);
    expect(find.textContaining('05:42'), findsOneWidget);
  });
}
