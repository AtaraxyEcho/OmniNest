import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_dialog.dart';

WeatherData _sampleWeather() {
  final hourly = <WeatherHourly>[
    const WeatherHourly(time: '现在', temp: 21, icon: '104', text: '阴'),
    const WeatherHourly(
      time: '2026-09-11T18:00+08:00',
      temp: 20,
      icon: '101',
      text: '多云',
    ),
    const WeatherHourly(
      time: '2026-09-11T19:00+08:00',
      temp: 19,
      icon: '150',
      text: '晴',
    ),
  ];
  for (var i = 0; i < 8; i++) {
    hourly.add(
      WeatherHourly(
        time: '2026-09-11T2$i:00+08:00',
        temp: 18 + i,
        icon: '150',
        text: '晴',
      ),
    );
  }
  return WeatherData(
    temp: 21,
    feelsLike: 20,
    text: '阴',
    icon: '104',
    humidity: '64%',
    windSpeed: '3',
    windDir: '北风',
    pressure: '938',
    visibility: '30',
    uvIndex: 4,
    sunrise: '06:33',
    sunset: '18:59',
    aqi: 42,
    pm2p5: 18,
    aqiCategory: '优',
    updateTime: '2026-09-11 17:45',
    healthAdvice: '',
    tempMax: 24,
    tempMin: 16,
    precip: '0.0',
    windScale: '3',
    textDay: '多云',
    textNight: '晴',
    locationName: '福州',
    hourly: hourly,
    daily: const [
      WeatherDaily(
        date: '2026-09-11',
        tempMax: 24,
        tempMin: 16,
        iconDay: '104',
        textDay: '多云',
        iconNight: '150',
        textNight: '晴',
      ),
      WeatherDaily(
        date: '2026-09-12',
        tempMax: 26,
        tempMin: 17,
        iconDay: '100',
        textDay: '晴',
        iconNight: '150',
        textNight: '晴',
      ),
    ],
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
  testWidgets('天气详情首帧延迟启动背景动效', (tester) async {
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

  testWidgets('手机尺寸展示温度、提示、AQI 与地区', (tester) async {
    await _openWeatherDetail(tester, size: const Size(390, 844));

    expect(find.text('21°'), findsWidgets);
    expect(find.textContaining('适合户外'), findsOneWidget);
    expect(find.textContaining('AQI 42'), findsOneWidget);
    expect(find.textContaining('福州'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await _closeWeatherDetail(tester);
    expect(find.text('21°'), findsNothing);
  });

  testWidgets('桌面尺寸英雄双列与指标网格', (tester) async {
    await _openWeatherDetail(tester, size: const Size(1600, 1000));

    expect(find.text('21°'), findsWidgets);
    expect(find.textContaining('多云'), findsWidgets);
    expect(find.textContaining('06:33'), findsOneWidget);
    expect(find.textContaining('18:59'), findsOneWidget);
    expect(find.textContaining('UV 4'), findsOneWidget);
  });

  testWidgets('预报选项卡可切换逐小时与一周', (tester) async {
    await _openWeatherDetail(tester, size: const Size(1600, 1000));

    expect(find.text('逐小时'), findsOneWidget);
    expect(find.text('一周预报'), findsOneWidget);
    // 默认逐小时：首项「现在」，只渲染 8 张卡片
    expect(find.text('现在'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('26:00'), findsNothing);

    await tester.tap(find.text('一周预报'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('09-12'), findsOneWidget);
    expect(find.text('26°'), findsOneWidget);
  });

  testWidgets('弹窗矩形不超过窗口视口', (tester) async {
    const viewport = Size(1000, 700);
    await _openWeatherDetail(tester, size: viewport);

    final dialogRect = tester.getRect(find.byType(Dialog).first);
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(viewport.width));
    expect(dialogRect.bottom, lessThanOrEqualTo(viewport.height));
  });

  testWidgets('小窗口不溢出', (tester) async {
    await _openWeatherDetail(tester, size: const Size(320, 480));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
}
