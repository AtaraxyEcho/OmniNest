import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_sheet.dart';

WeatherData _sampleWeather() {
  return WeatherData(
    temp: 18,
    feelsLike: 17,
    text: 'Clear',
    icon: '100',
    humidity: '62',
    windSpeed: '8',
    windDir: 'NE',
    pressure: '1013',
    visibility: '24',
    uvIndex: 2,
    sunrise: '06:12',
    sunset: '17:46',
    aqi: 28,
    pm2p5: 8,
    aqiCategory: 'Excellent',
    updateTime: '2026-10-03T17:00',
    hourly: const [
      WeatherHourly(
        time: '2026-10-03T17:00',
        temp: 18,
        icon: '100',
        text: 'Clear',
      ),
      WeatherHourly(
        time: '2026-10-03T20:00',
        temp: 16,
        icon: '100',
        text: 'Clear',
      ),
    ],
    daily: const [
      WeatherDaily(
        date: '2026-10-04',
        tempMax: 24,
        tempMin: 14,
        iconDay: '100',
        textDay: 'Clear',
        iconNight: '150',
        textNight: 'Clear',
      ),
    ],
    locationName: 'Hangzhou',
  );
}

void main() {
  testWidgets('天气面板点击遮罩关闭且内容完整', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () => showWeatherDetailSheet(
                            context,
                            weather: _sampleWeather(),
                          ),
                      child: const Text('open'),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('HANGZHOU · LOCAL WEATHER'), findsOneWidget);
    // 大字温度（74px 衬线）与逐时 16° 均在场：内容未残缺。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == '18°' &&
            (widget.style?.fontSize ?? 0) > 40,
      ),
      findsOneWidget,
    );
    expect(find.text('16°'), findsOneWidget);

    // 点击顶部遮罩区关闭，遮罩下方按钮不再被命中。
    await tester.tapAt(const Offset(195, 80));
    await tester.pumpAndSettle();
    expect(find.text('HANGZHOU · LOCAL WEATHER'), findsNothing);
  });

  testWidgets('嵌套导航器中面板仍落在根导航（遮罩覆盖全屏）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Navigator(
            onGenerateRoute:
                (settings) => MaterialPageRoute(
                  builder:
                      (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed:
                                () => showWeatherDetailSheet(
                                  context,
                                  weather: _sampleWeather(),
                                ),
                            child: const Text('open-nested'),
                          ),
                        ),
                      ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-nested'));
    await tester.pumpAndSettle();

    // 遮罩铺满整屏：视口左上角的点击命中遮罩并关闭面板。
    expect(find.text('HANGZHOU · LOCAL WEATHER'), findsOneWidget);
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.text('HANGZHOU · LOCAL WEATHER'), findsNothing);
    expect(find.text('open-nested'), findsOneWidget);
  });
}
