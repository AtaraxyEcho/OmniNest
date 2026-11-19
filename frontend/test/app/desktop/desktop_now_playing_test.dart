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
    expect(find.text('04:14'), findsOneWidget);
    expect(find.text('01:36'), findsOneWidget);
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

  testWidgets('外观面板可开合，背景与歌词档位可切换', (tester) async {
    await pumpNowPlaying(tester);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Appearance'), findsWidgets);
    expect(find.text('Gradient'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);

    await tester.tap(find.text('Gradient'));
    await tester.pump();
    await tester.tap(find.text('L'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Appearance'), findsWidgets);
  });

  testWidgets('外观面板的预设是 6 列方形色块并带名称', (tester) async {
    await pumpNowPlaying(tester);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 六个方形色块：宽高相等且为圆角 12。
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
                  BorderRadius.circular(12)) &&
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
    expect(labels, contains('PRESETS'));
    expect(labels.where((label) => label.isNotEmpty).length, greaterThan(8));
  });

  test('上下半区偏好可持久化往返', () {
    const style = DesktopNpStyle(splitPaint: true, splitPos: 68, lowerBrush: 3);
    final restored = DesktopNpStyle.fromJson(style.toJson());
    expect(restored.splitPaint, isTrue);
    expect(restored.splitPos, 68);
    expect(restored.lowerBrush, 3);
    expect(restored.copyWith(splitPaint: false).splitPaint, isFalse);
    expect(
      DesktopNpStyle.fromJson(const DesktopNpStyle().toJson()).splitPaint,
      isFalse,
    );
  });

  testWidgets('外观面板可切到上下半区填充', (tester) async {
    await pumpNowPlaying(tester);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

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
