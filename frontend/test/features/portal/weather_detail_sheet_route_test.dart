import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_sheet.dart';

WeatherData _sampleWeather({
  int hourlyCount = 2,
  int dailyCount = 1,
  String humidity = '62%',
}) {
  return WeatherData(
    temp: 18,
    feelsLike: 17,
    text: 'Clear',
    icon: '100',
    humidity: humidity,
    windSpeed: '8 km/h',
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
    hourly: [
      for (var index = 0; index < hourlyCount; index++)
        WeatherHourly(
          time: '2026-10-03T${(17 + index).toString().padLeft(2, '0')}:00',
          temp: 18 - 2 * index,
          icon: '100',
          text: 'Clear',
        ),
    ],
    daily: [
      for (var index = 0; index < dailyCount; index++)
        WeatherDaily(
          date: '2026-10-0${5 + index}',
          tempMax: 24 + index,
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

Future<void> _pumpSheet(
  WidgetTester tester,
  WeatherData weather, {
  Locale locale = const Locale('en'),
}) async {
  // 一个用例里连续开两次面板时，必须先拆掉上一棵树：旧路由还留在同一个
  // Overlay 里，第二次的 tap('open') 只会打在上一层面板上。
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => Center(
                  child: TextButton(
                    onPressed:
                        () => showWeatherDetailSheet(context, weather: weather),
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
}

/// 面板根容器：样例 `.weather-sheet` 的 30 顶圆角是唯一标识。
Finder _weatherSheetFinder() {
  return find.byWidgetPredicate((widget) {
    if (widget is! Container || widget.decoration is! BoxDecoration) {
      return false;
    }
    final radius = (widget.decoration as BoxDecoration).borderRadius;
    return radius is BorderRadius && radius.topLeft.x == 30;
  });
}

Finder _omniIcon(OmniIconsData icon) {
  return find.byWidgetPredicate(
    (widget) => widget is OmniIcon && widget.icon == icon,
  );
}

/// 逐时轨底必须是不透明面板底：从横向滚动条往上找到带发丝边框那一层 Container。
bool _hourlyRailSurfaceIsOpaque(WidgetTester tester) {
  for (final element
      in find
          .ancestor(of: _horizontalScroller(), matching: find.byType(Container))
          .evaluate()) {
    final decoration = (element.widget as Container).decoration;
    if (decoration is BoxDecoration && decoration.border != null) {
      final color = decoration.color;
      return color != null && color.a == 1.0;
    }
  }
  return false;
}

Finder _horizontalScroller() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is SingleChildScrollView &&
        widget.scrollDirection == Axis.horizontal,
  );
}

void main() {
  testWidgets('天气面板点击遮罩关闭且内容完整', (tester) async {
    await _pumpSheet(tester, _sampleWeather());

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

  testWidgets('天气面板逐值对齐样例：头部内缩 19、无重复关闭钮、整幅逐时轨、三行预报', (tester) async {
    await _pumpSheet(tester, _sampleWeather(hourlyCount: 5, dailyCount: 5));

    // 样例 .weather-sheet>header：padding 24px 19px 8px，左沿距面板 19。
    // 眉标是头部第一行文字，它的左沿就是那 19 内缩。
    expect(
      tester.getTopLeft(find.text('HANGZHOU · LOCAL WEATHER')).dx,
      moreOrLessEquals(19, epsilon: 0.6),
    );
    // 头部不再放关闭钮：点遮罩、系统返回/侧滑、下拉甩动已覆盖退出，
    // 第四颗属重复控制（2026-10-15 定）。
    expect(find.byTooltip('Close'), findsNothing);

    // 样例 .hourly-weather：margin 0 -20px 抵消主区 20 内边距，
    // 轨道内沿只留面板自身的 20，发丝线整幅通铺。
    final railFinder = _horizontalScroller();
    expect(railFinder, findsOneWidget);
    final railRect = tester.getRect(railFinder);
    expect(railRect.left, moreOrLessEquals(20, epsilon: 0.6));
    expect(railRect.width, moreOrLessEquals(350, epsilon: 0.6));

    // 逐时轨必须坐在不透明的面板底上：壁纸带是钉在面板顶部的定高 Positioned，
    // 行随内容滚动，任何时刻滑进带内都不能透出图片。
    expect(_hourlyRailSurfaceIsOpaque(tester), isTrue);

    // 样例 days 固定 3 条：第四、五天不得出现在树里。
    // 夹具日期从 2026-10-05（周一）起，首行按样例换成 Tomorrow，
    // 因此渲染出的是 Tomorrow / Tuesday / Wednesday。
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Monday'), findsNothing);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('Wednesday'), findsOneWidget);
    expect(find.text('Thursday'), findsNothing);
    expect(find.text('Friday'), findsNothing);

    // 样例预报头按钮是「标签 + chevron」，没有 settings 图标。
    expect(_omniIcon(OmniIcons.chevron), findsWidgets);
    expect(_omniIcon(OmniIcons.settings), findsNothing);
  });

  testWidgets('天气面板不再把后端已带的单位拼第二遍', (tester) async {
    await _pumpSheet(tester, _sampleWeather());

    // /weather/realtime 的 humidity 与 windSpeed 字面量已含 % 和 km/h
    // （WeatherService.java:481），面板原样显示；实机截图上的
    // 「5 km/h km/h」「81%%」就是这里多拼了一遍。
    expect(find.text('8 km/h'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.contains('km/h km/h') ?? false),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data?.endsWith('%%') ?? false),
      ),
      findsNothing,
    );
  });

  testWidgets('中文界面下预报行不出现英文星期', (tester) async {
    await _pumpSheet(
      tester,
      _sampleWeather(hourlyCount: 5, dailyCount: 5),
      locale: const Locale('zh'),
    );

    // 夹具日 2026-10-05（周一）起，首行按样例是「明天」，其后两天
    // 必须跟界面语言走，不能是 en_US 的 Tuesday。
    expect(find.text('星期二'), findsOneWidget);
    expect(find.text('星期三'), findsOneWidget);
    expect(find.text('Tuesday'), findsNothing);
  });

  testWidgets('天气面板文字不带上 MaterialApp 兜底装饰', (tester) async {
    await _pumpSheet(tester, _sampleWeather(hourlyCount: 5, dailyCount: 5));

    // 裸 PopupRoute 页面没有 Material 祖先时，文字会继承 MaterialApp 的兜底
    // 样式（underline + double + 黄色 decorationColor），肉眼看到的就是每条
    // 文字下的双横线。这里按渲染结果判定，不看 widget 上写了什么。
    var checked = 0;
    for (final element in find.byType(RichText).evaluate()) {
      final render = element.renderObject;
      if (render is! RenderParagraph || !render.hasSize) {
        continue;
      }
      checked++;
      expect(
        render.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '文字「${render.text.toPlainText()}」带上了装饰',
      );
    }
    expect(checked, greaterThan(10));
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

  testWidgets('面板展开高度压在 78% 屏高内，上方仍留出页面', (tester) async {
    await _pumpSheet(tester, _sampleWeather(hourlyCount: 5, dailyCount: 3));

    final sheet = tester.getRect(_weatherSheetFinder());
    // 内容自然高度 821 远超上限，所以这里判的是"被约束住"而不是"内容变短"。
    expect(sheet.height, lessThan(844 * 0.8));
    expect(
      844 - sheet.height,
      greaterThan(150),
      reason: '抽屉上方必须留出可见的壁纸/页面，不能整屏盖住',
    );
  });

  testWidgets('摘要行由逐时数据生成，不足两小时就整行消失', (tester) async {
    await _pumpSheet(tester, _sampleWeather(hourlyCount: 5));
    //  fixtures 温度是 18-2*i ⇒ 18,16,14,12,10。
    expect(
      find.text('Between 10° and 18° over the next 5 hours.'),
      findsOneWidget,
    );

    await _pumpSheet(tester, _sampleWeather(hourlyCount: 1));
    expect(
      find.textContaining('over the next'),
      findsNothing,
      reason: '只有一个小时没有区间可说，整行不该编造',
    );
  });

  testWidgets('抽屉微型标签档取 microLabelInk，不落回 --muted', (tester) async {
    await _pumpSheet(tester, _sampleWeather(hourlyCount: 5, dailyCount: 3));

    Color inkOf(String text) =>
        tester
            .renderObject<RenderParagraph>(find.text(text))
            .text
            .style!
            .color!;

    for (final slot in ['HUMIDITY', 'Comfortable', 'Now', 'NEXT THREE DAYS']) {
      expect(
        inkOf(slot),
        MobileEnvPalette.light.microLabelInk,
        reason: '$slot 属于 7-10px 微型标签档',
      );
      expect(
        inkOf(slot),
        isNot(MobileEnvPalette.light.inkMuted),
        reason: '落回 --muted 就等于把整层小字重新调灰',
      );
    }
  });

  testWidgets('湿度格第三行按百分比分档', (tester) async {
    for (final (value, note) in [
      ('62%', 'Comfortable'),
      ('80%', 'Humid'),
      ('18%', 'Dry'),
    ]) {
      await _pumpSheet(tester, _sampleWeather(humidity: value));
      expect(
        find.text(note),
        findsOneWidget,
        reason: '湿度 $value 应说明为 $note（样例该格有第三行）',
      );
    }
  });
}
