import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/pages/desktop_home_page.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';

import 'desktop_test_harness.dart';
import 'tolerant_golden.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final GoldenFileComparator defaultComparator = goldenFileComparator;
  setUpAll(() {
    goldenFileComparator = TolerantGoldenComparator(
      Uri.parse('test/app/desktop/desktop_home_view_test.dart'),
    );
  });
  tearDownAll(() {
    goldenFileComparator = defaultComparator;
  });

  setUp(() {
    // 固定时刻：问候语、天象渐变与 hero 时钟都随之确定，基线不随跑测时间漂移。
    DesktopHomePage.clock = () => DateTime(2026, 11, 14, 18, 30);
    _mockPathProvider();
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
          'assets/backdrops/default_wallpaper.jpg',
        )).buffer.asUint8List();
    // 用全局 HttpOverrides 而不是 runZoned：图片请求可能在 zone 结束后才由
    // 绘制/解码链发起，落在 zone 外就会走真实网络并回退成兜底色，导致基线
    // 在并行跑套件时稳定差 0.3%。每个测试文件独立 isolate，全局覆盖是安全的。
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = DesktopImageOverrides(bytes);
    addTearDown(() => HttpOverrides.global = previousOverrides);
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
    // 样例 `.stat` 的说明行是“今天新增”；数值位是 1100ms 递增动画，
    // 固定 600ms 帧上断言会落在中间值，所以核标签与说明。
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('+42 today'), findsOneWidget);
  });

  testWidgets('hero 用当前时段问候与天气实况，不是写死文案', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining('Hangzhou · Partly cloudy'), findsOneWidget);
    expect(find.text('18°'), findsOneWidget);
    expect(find.text('H 21° · L 12°'), findsOneWidget);
    expect(find.textContaining('Mira Han'), findsOneWidget);
    // 样例 `.hero-tile`：小字给进度/艺人，粗体给片名/专辑名。
    expect(find.text('Aperture'), findsWidgets);
    expect(find.text('Resume · 64% left'), findsOneWidget);
    expect(find.text('Play · Aoi Trio'), findsOneWidget);
    expect(find.text('Evening Drift'), findsWidgets);
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
    // 卡片封面解码是真实异步：并行跑整个桌面套件时 1.2s 假时间不足以让位图落地，
    // 基线会随机差 0.3%（半透明首帧）。让出真实事件循环再补两帧，动画相位不变。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    // 解码落地后封面还有 300ms 淡入：再推一段假时间让两枚 hero 徽标的玻璃
    // 采样稳定下来，否则并行跑套件时会差 0.3%。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
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

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// 首页卡片封面走 `flutter_cache_manager`，测试进程没有 path_provider 插件，
/// 这里给出临时目录桩，避免平台通道异常打断 golden 采样。
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        final prefix = call.method.replaceAll(RegExp(r'[^A-Za-z]'), '');
        final dir = await Directory.systemTemp.createTemp(
          'omninest-home-$prefix',
        );
        return dir.path;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });
}
