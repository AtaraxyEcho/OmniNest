// 首页（Spatial Home）时间块与天气条的水平对齐回归。
//
// 手机档里只有时钟会被 LayoutBuilder 拿到拉满宽的盒子（眉标与天气条自己收缩宽度），
// 所以光靠 Column 的 `crossAxisAlignment` 不足以让它居中：量的是墨迹而不是盒子矩形，
// 否则被拉满的盒子中心看着正好在视口中央，墨迹却贴着左边的缺陷会被漏掉。
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
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/pages/portal_page.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_mobile_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        theme: OmniNestTheme.from(AppThemePalette.dark),
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
    expect(
      tester
          .getCenter(
            find.ancestor(of: temp, matching: find.byType(GestureDetector)),
          )
          .dx,
      closeTo(center, 1.0),
      reason: '首页天气条应水平居中',
    );
  });

  testWidgets('≥980 双栏档时间块仍贴左栏，不跟着居中', (tester) async {
    await _pumpHome(
      tester,
      width: 1000,
      home: const PortalMobileShell(),
    );

    // 双栏档 `.home-stage` 页边距 40：时间块左缘就该落在内容左边界。
    // 容差放到 2.5：-4 字距会给墨迹留 2px 的尾距误差，那是字体度量不是对齐问题。
    final ink = _inkOf(tester, _clock);
    expect(ink.left, closeTo(40.0, 2.5), reason: '双栏档时间块应贴内容左缘');
    expect(
      ink.center,
      lessThan(500.0),
      reason: '双栏档时间块不该跑到视口中央，右侧是焦点卡',
    );
  });
}
