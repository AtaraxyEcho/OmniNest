import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/desktop/pages/desktop_now_playing_page.dart';
import 'package:omninest/app/desktop/widgets/desktop_np_style_panel.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpNowPlaying(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(const DesktopNowPlayingPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('主视觉给出曲名、艺人与时长', (tester) async {
    await pumpNowPlaying(tester);

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Evening Drift'), findsWidgets);
    expect(find.textContaining('Aoi Trio'), findsWidgets);
    // v10 底栏：左侧当前时间、右侧剩余时间，总时长并进专辑副标题。
    expect(find.text('1:36'), findsOneWidget);
    expect(find.text('-2:38'), findsOneWidget);
    expect(find.textContaining('4:14'), findsOneWidget);
  });

  testWidgets('About 页有 64 柱动态频谱', (tester) async {
    await pumpNowPlaying(tester);

    expect(find.byType(DesktopVisualizer), findsNothing);
    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    final visualizer = tester.widget<DesktopVisualizer>(
      find.byType(DesktopVisualizer),
    );
    expect(visualizer.bars, 64);
    expect(visualizer.seed, 5);
    expect(visualizer.playing, isTrue);
  });

  testWidgets('外观面板可开合，Background / Lyrics 双 Tab 可切换', (tester) async {
    await pumpNowPlaying(tester);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('Appearance'), findsWidgets);
    expect(find.text('Gradient'), findsOneWidget);

    await tester.tap(find.text('Gradient'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('desktop-np-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Small'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Appearance'), findsWidgets);
  });

  testWidgets('外观面板的风格预设是 6 个等宽渐变块并带名称', (tester) async {
    await pumpNowPlaying(tester);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    // 六个方形色块：宽高相等、圆角 10 且带渐变。
    final swatches = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(DesktopNpStylePanel),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where(
          (box) =>
              box.decoration is BoxDecoration &&
              ((box.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(10)) &&
              (box.decoration as BoxDecoration).gradient != null,
        );
    expect(swatches, hasLength(6));

    // 每块下方都有名称（不再是只有 Tooltip 的圆点）。
    final labels =
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(DesktopNpStylePanel),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data)
            .whereType<String>()
            .toList();
    expect(labels, contains('Auto'));
    expect(labels.where((label) => label.isNotEmpty).length, greaterThan(8));
  });

  test('16 字段外观偏好可持久化往返', () {
    const style = DesktopNpStyle(
      background: DesktopNpBackground.gradient,
      wallId: 'b-2',
      mask: 24,
      blur: 12,
      gradAuto: false,
      gradStart: Color(0xFF112233),
      gradEnd: Color(0xFF445566),
      gradAngle: 45,
      wordFill: false,
      fillAuto: false,
      fillPaint: DesktopNpPaint.halves(
        top: DesktopNpZone.solid(Color(0xFFFFFFFF)),
        bottom: DesktopNpZone.solid(Color(0xFFFFCC00)),
        splitPos: 68,
      ),
      baseOpacity: 40,
      lyricScale: 1.25,
      glow: false,
      lyricFade: 30,
    );
    final restored = DesktopNpStyle.fromJson(style.toJson());
    expect(restored.background, DesktopNpBackground.gradient);
    expect(restored.wallId, 'b-2');
    expect(restored.mask, 24);
    expect(restored.blur, 12);
    expect(restored.gradAuto, isFalse);
    expect(restored.gradStart, const Color(0xFF112233));
    expect(restored.gradEnd, const Color(0xFF445566));
    expect(restored.gradAngle, 45);
    expect(restored.wordFill, isFalse);
    expect(restored.fillAuto, isFalse);
    expect(restored.fillPaint.split, isTrue);
    expect(restored.fillPaint.splitPos, 68);
    expect(restored.baseOpacity, 40);
    expect(restored.lyricScale, 1.25);
    expect(restored.glow, isFalse);
    expect(restored.lyricFade, 30);

    const defaults = DesktopNpStyle();
    expect(defaults.background, DesktopNpBackground.aurora);
    expect(defaults.wallId, 'b-env');
    expect(defaults.baseOpacity, 32);
    expect(defaults.lyricFade, 22);
    expect(defaults.gradAngle, 180);
  });

  test('旧版上下半区 JSON 平滑迁移到双区颜料', () {
    final restored = DesktopNpStyle.fromJson(<String, Object>{
      'splitPaint': true,
      'splitPos': 68,
      'lowerBrush': 3,
      'preset': 1,
      'brush': 2,
    });
    expect(restored.fillPaint.split, isTrue);
    expect(restored.fillPaint.splitPos, 68);
  });

  testWidgets('歌词 Tab 可切到上下半区填充', (tester) async {
    await pumpNowPlaying(tester);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    await tester.tap(find.byKey(const ValueKey('desktop-np-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 「其他行」目标始终展开颜料编辑器（当前行默认跟随封面色调，编辑器收起）。
    final otherLines = find.text('Other lines');
    expect(otherLines, findsOneWidget);
    await tester.ensureVisible(otherLines);
    await tester.pump();
    await tester.tap(otherLines);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final halves = find.text('Upper / lower halves');
    expect(halves, findsOneWidget);
    await tester.ensureVisible(halves);
    await tester.pump();
    await tester.tap(halves);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Lower half'), findsWidgets);
    expect(find.text('Split position'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('歌词与队列两页可切换', (tester) async {
    await pumpNowPlaying(tester);

    expect(find.text('No lyrics'), findsOneWidget);

    await tester.tap(find.text('Play Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Evening Drift'), findsWidgets);
  });
}
