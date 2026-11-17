import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/pages/desktop_home_page.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 固定时刻：问候语、天象渐变与 hero 时钟都随之确定，基线不随跑测时间漂移。
    DesktopHomePage.clock = () => DateTime(2026, 11, 14, 18, 30);
  });

  tearDown(() {
    DesktopHomePage.clock = DateTime.now;
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    bool dark = true,
    DesktopAccent accent = DesktopAccent.sage,
    Size viewport = kDesktopViewport,
  }) async {
    final bytes =
        (await rootBundle.load(
          'assets/backdrops/default_wallpaper_poster.jpg',
        )).buffer.asUint8List();
    await HttpOverrides.runZoned(
      () async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: desktopSeedOverrides(),
            child: wrapDesktop(
              const DesktopHomePage(),
              dark: dark,
              accent: accent,
              viewport: viewport,
            ),
          ),
        );
        // 天象是循环动画，pumpAndSettle 永远等不到静止；按固定帧推进，
        // golden 的相位因此也是确定的。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      },
      createHttpClient:
          (context) => DesktopImageOverrides(bytes).createHttpClient(context),
    );
  }

  testWidgets('首页按样例铺开六个分区，数据全部来自模块门面', (tester) async {
    await pumpHome(tester);

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Made for this moment'), findsOneWidget);
    expect(find.text('Currently reading'), findsOneWidget);
    expect(find.text('Recent photos'), findsOneWidget);
    expect(find.text('Recent files'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);

    // 真实种子而不是演示占位。
    expect(find.text('Aperture'), findsWidgets);
    expect(find.text('The Quiet Arrival'), findsWidgets);
    expect(find.text('Evening Drift'), findsWidgets);
    expect(find.text('Field notes.pdf'), findsOneWidget);
    expect(find.text('Import finished'), findsOneWidget);
    expect(find.text('4382 photos · 128 titles'), findsOneWidget);
  });

  testWidgets('hero 用当前时段问候与天气实况，不是写死文案', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining('Hangzhou · Partly cloudy'), findsOneWidget);
    expect(find.text('18°'), findsOneWidget);
    expect(find.text('H 21° · L 12°'), findsOneWidget);
    expect(find.textContaining('Mira Han'), findsOneWidget);
    expect(find.text('Resume Aperture'), findsOneWidget);
    // 次按钮跟样例一样直呼当前曲名，而不是泛化的「开始聆听」。
    expect(find.widgetWithText(DesktopButton, 'Evening Drift'), findsOneWidget);
  });

  testWidgets('浅色主题与强调色档位都真的换色', (tester) async {
    await pumpHome(tester, dark: false, accent: DesktopAccent.copper);

    final context = tester.element(find.byType(DesktopHomePage));
    final scheme = Theme.of(context).colorScheme;
    expect(scheme.brightness, Brightness.light);
    expect(scheme.primary, DesktopAccent.copper.light);
  });

  testWidgets('1280 宽下两栏叠成单列，卡片不溢出', (tester) async {
    await pumpHome(tester, viewport: const Size(1280, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Currently reading'), findsOneWidget);
  });

  testWidgets('首页视觉基线', (tester) async {
    await pumpHome(tester);
    // 首页区块带 55ms 交错入场，固定帧推进到入场结束后再取基线，
    // 否则 golden 会固化半透明的中间帧。
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/desktop_home_dark.png'),
    );
  });

  testWidgets('空库时每个分区落到自己的空态与前往入口', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(empty: true),
        child: wrapDesktop(const DesktopHomePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Nothing in progress. Open Movies to start something.'),
      findsOneWidget,
    );
    expect(find.text('No photos yet.'), findsOneWidget);
    expect(find.text('Nothing on the shelf yet.'), findsOneWidget);
    expect(find.text('No recent files.'), findsOneWidget);
    expect(find.byIcon(DesktopIcons.film), findsWidgets);
  });
}
