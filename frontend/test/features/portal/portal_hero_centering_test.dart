// 首页（Spatial Home）时间块与天气条的水平对齐与极性回归。
//
// 手机档里只有时钟会被 LayoutBuilder 拿到拉满宽的盒子（眉标与天气条自己收缩宽度），
// 所以光靠 Column 的 `crossAxisAlignment` 不足以让它居中：量的是墨迹而不是盒子矩形，
// 否则被拉满的盒子中心看着正好在视口中央，墨迹却贴着左边的缺陷会被漏掉。
// 天气条同理但更容易漏：胶囊本身就铺满舞台，盒子中心恒等于舞台中心，
// 必须看条内图标组的左右留痕是否对称。
// ≥980 双栏档反过来必须贴左（时间块占 1.1fr，右侧是同排的焦点卡）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/pages/portal_page.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_mobile_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/golden_fonts.dart';

/// 一段文本的墨迹水平区间（全局坐标）。
class InkRange {
  const InkRange(this.left, this.right);

  final double left;
  final double right;

  double get center => (left + right) / 2;
}

WeatherData _weather() {
  return const WeatherData(
    temp: 23,
    feelsLike: 22,
    text: '晴',
    icon: '100',
    humidity: '40',
    windSpeed: '3',
    windDir: '东风',
    pressure: '1008',
    visibility: '10',
    uvIndex: 5,
    sunrise: '06:00',
    sunset: '18:00',
    aqi: 50,
    pm2p5: 10,
    aqiCategory: '优',
    updateTime: '2026-10-08T09:00+08:00',
    locationName: '杭州',
  );
}

InkRange _inkOf(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final text = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  final left = boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
  final right = boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b);
  final origin = paragraph.localToGlobal(Offset.zero).dx;
  return InkRange(origin + left, origin + right);
}

/// `viaShell` 用于 ≥980 双栏档：`PortalPage` 在那个宽度已交给桌面宿主，
/// 只有移动壳层自己的入口才会渲染 `.home-stage` 双栏。
Future<void> _pumpHome(
  WidgetTester tester, {
  required double width,
  required Widget home,
  Brightness brightness = Brightness.dark,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        presetAppEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
        realtimeWeatherProvider.overrideWith((ref) async => _weather()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme:
            brightness == Brightness.light
                ? OmniNestTheme.from(AppThemePalette.light)
                : OmniNestTheme.from(AppThemePalette.dark),
        home: MobileShellScope(hosted: true, child: Scaffold(body: home)),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

/// 首页大时钟：页内唯一带 -4 字距的文本（衬线 hero 口径）。
final Finder _clock = find.byWidgetPredicate(
  (widget) => widget is Text && widget.style?.letterSpacing == -4,
);

void main() {
  // 不装字体时占位字形是等宽实心矩形，"12:00" 的墨迹几乎铺满整盒，
  // 起始对齐与居中对量出来的墨迹中心差别很小——这条守卫必须用真字形。
  setUpAll(loadGoldenFonts);

  testWidgets('手机档首页眉标、大时钟与天气条都水平居中', (tester) async {
    await _pumpHome(tester, width: 390, home: const PortalPage());

    final temp = find.text('23°');
    expect(_clock, findsOneWidget, reason: '应能定位首页大时钟');
    expect(temp, findsOneWidget, reason: '天气条应已渲染');

    // 视口 390、`.home-stage` 页边距左右各 16 → 内容区中心 195。
    const center = 195.0;
    expect(
      _inkOf(tester, _clock).center,
      closeTo(center, 1.0),
      reason: '首页时间应水平居中',
    );
    // 眉标与时钟同一个头部 Column；页内还有「RECENTLY TOUCHED」等同款
    // 1.65 字距眉标，必须把搜索范围收到时钟所在的那个 Column 里。
    final header =
        find.ancestor(of: _clock, matching: find.byType(Column)).first;
    final eyebrow = find.descendant(
      of: header,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.letterSpacing == 1.65,
      ),
    );
    expect(eyebrow, findsOneWidget, reason: '头部里应只有一条眉标');
    expect(
      _inkOf(tester, eyebrow).center,
      closeTo(center, 1.0),
      reason: '眉标应与时钟同轴',
    );

    // 天气条要看内容组而不是胶囊：`.weather-line` 铺满舞台宽度，但
    // `justify-content:center` 让图标·温度·天况·箭头聚在中间。胶囊盒子
    // 中心恒等于 195，量盒子永远发现不了"图标贴着内容左缘"这一缺陷。
    final pill = find.ancestor(
      of: temp,
      matching: find.byType(GestureDetector),
    );
    final glyphs = find.descendant(
      of: pill,
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'OmniIcon',
      ),
    );
    expect(glyphs, findsAtLeastNWidgets(2), reason: '天气图标与右箭头都应在条内');
    final firstGlyphLeft = tester.getTopLeft(glyphs.first).dx;
    final lastGlyphRight = tester.getTopRight(glyphs.last).dx;
    expect(
      (firstGlyphLeft + lastGlyphRight) / 2,
      closeTo(center, 2.0),
      reason: '内容组中心应与舞台中心重合',
    );
    expect(
      firstGlyphLeft,
      greaterThan(16.0 + 24.0),
      reason: '内容组必须按自身宽度收缩；贴着内容左缘说明行被撑满成两端分布',
    );
  });

  testWidgets('≥980 双栏档时间块仍贴左栏，不跟着居中', (tester) async {
    await _pumpHome(tester, width: 1000, home: const PortalMobileShell());

    // 双栏档 `.home-stage` 页边距 40：时间块左缘就该落在内容左边界。
    // 容差放到 2.5：-4 字距会给墨迹留 2px 的尾距误差，那是字体度量不是对齐问题。
    final ink = _inkOf(tester, _clock);
    expect(ink.left, closeTo(40.0, 2.5), reason: '双栏档时间块应贴内容左缘');
    expect(ink.center, lessThan(500.0), reason: '双栏档时间块不该跑到视口中央，右侧是焦点卡');
  });

  testWidgets('首页随外观设置翻极性：两态照片上都用浅色字', (tester) async {
    Color clockInk() =>
        tester.renderObject<RenderParagraph>(_clock).text.style!.color!;
    Color clockGlow() =>
        tester
            .renderObject<RenderParagraph>(_clock)
            .text
            .style!
            .shadows!
            .first
            .color;

    await _pumpHome(tester, width: 390, home: const PortalPage());
    expect(clockInk(), MobileEnvPalette.dark.ink, reason: '深色外观下照片上仍是浅字');
    expect(clockGlow(), MobileEnvPalette.dark.heroGlow);

    await _pumpHome(
      tester,
      width: 390,
      home: const PortalPage(),
      brightness: Brightness.light,
    );
    expect(
      clockInk(),
      MobileEnvPalette.lightPhotographic.ink,
      reason: '样例第 4 层把首页留在摄影面：浅态首页仍是照片上的浅色字',
    );
    expect(
      clockInk(),
      isNot(MobileEnvPalette.light.ink),
      reason: '首页必须区别于媒体库/阅读/文件的纸面画布墨色',
    );
    expect(
      clockGlow(),
      MobileEnvPalette.lightPhotographic.heroGlow,
      reason: '摄影面的光晕是墨色投影，不是画布面的白色提亮',
    );
  });

  testWidgets('浅态摄影面：首页卡片是样例那块深玻璃，不落画布近白', (tester) async {
    await _pumpHome(
      tester,
      width: 390,
      home: const PortalPage(),
      brightness: Brightness.light,
    );

    final photographic = MobileEnvPalette.lightPhotographic;
    final canvas = MobileEnvPalette.light;
    final painted = _paintedCardColors(tester);

    // 焦点卡（音乐卡）在浅态取样例第 4 层的深玻璃，而不是画布档近白。
    expect(
      painted,
      contains(photographic.focusGradientStart),
      reason: '量不到摄影档卡片底，说明焦点卡没常驻渲染，这条守卫就空了',
    );
    // 这次报的缺陷就是卡片族从画布档取值：整个首页子树都不该出现画布档的
    // 卡片底与描边（瓦片、焦点卡、快捷行都在覆盖范围内）。
    for (final canvasColor in [
      canvas.surfaceRaised,
      canvas.focusGradientStart,
      canvas.focusGradientEnd,
      canvas.line09,
      canvas.line10,
    ]) {
      expect(
        painted,
        isNot(contains(canvasColor)),
        reason: '首页画出了画布档的卡片色：摄影档漏了这条覆盖',
      );
    }
  });
}

/// 首页子树里所有 `DecoratedBox` 真正画出来的卡片色（填充、渐变两端、描边）。
Set<Color> _paintedCardColors(WidgetTester tester) {
  final colors = <Color>{};
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) {
      continue;
    }
    final fill = decoration.color;
    if (fill != null) {
      colors.add(fill);
    }
    final gradient = decoration.gradient;
    if (gradient is LinearGradient) {
      colors.addAll(gradient.colors);
    }
    final border = decoration.border;
    if (border is Border) {
      colors.add(border.top.color);
    }
  }
  return colors;
}
