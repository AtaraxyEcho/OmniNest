import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/player/music_visual_color_picker.dart';

void main() {
  const defaultPaint = LyricPaint.solid(0xFF72D6C9);
  const initialPaint = LyricPaint.solid(0xFFE87878);

  LyricPaint? captured;

  Future<void> pumpField(
    WidgetTester tester, {
    LyricPaint initial = initialPaint,
  }) async {
    captured = null;
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: MusicVisualPaintField(
              palette: MusicImmersivePalette.digital,
              label: '已读歌词颜色',
              value: initial,
              defaultValue: defaultPaint,
              onChanged: (paint) => captured = paint,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MusicVisualPaintField));
    await tester.pumpAndSettle();
  }

  Future<void> confirmDialog(WidgetTester tester) async {
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  Future<void> selectGradient(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('music-visual-color-mode-gradient')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('点选预设色并确认后回调对应纯色', (tester) async {
    await pumpField(tester);

    final swatch = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color ==
              const Color(0xFF31C27C),
    );
    expect(swatch, findsOneWidget);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured?.mode, LyricPaintMode.solid);
    expect(captured?.primary, 0xFF31C27C);
  });

  testWidgets('HEX 输入实时生效并随确认回调', (tester) async {
    await pumpField(tester);

    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#31C27C',
    );
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured?.primary, 0xFF31C27C);
  });

  testWidgets('HEX 输入非法内容时不改变当前颜色', (tester) async {
    await pumpField(tester, initial: const LyricPaint.solid(0xFF31C27C));

    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#12',
    );
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured?.primary, 0xFF31C27C);
  });

  testWidgets('拖动色相条后确认回调色相变化后的颜色', (tester) async {
    await pumpField(tester, initial: initialPaint);

    final hueBarCenter = tester.getCenter(
      find.byKey(const ValueKey('music-visual-color-hue-bar')),
    );
    // 取色面手势依赖竞技场逐步判定，需在事件间插入 pump 才能可靠触发。
    final gesture = await tester.startGesture(hueBarCenter);
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured, isNotNull);
    expect(captured?.primary, isNot(0xFFE87878));
  });

  testWidgets('恢复默认值按钮回调字段默认画法', (tester) async {
    await pumpField(tester, initial: initialPaint);

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured?.mode, defaultPaint.mode);
    expect(captured?.colors, defaultPaint.colors);
  });

  testWidgets('切换上下渐变后可分别编辑两端颜色', (tester) async {
    await pumpField(tester, initial: initialPaint);

    await selectGradient(tester);
    expect(
      find.byKey(const ValueKey('music-visual-color-gradient-preview')),
      findsOneWidget,
    );

    // 下色改为绿色，上色保持初始红色。
    await tester.tap(
      find.byKey(const ValueKey('music-visual-color-stop-bottom')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#31C27C',
    );
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured?.mode, LyricPaintMode.verticalGradient);
    expect(captured?.colors, const <int>[0xFFE87878, 0xFF31C27C]);
  });

  testWidgets('渐变预览随上色/下色的调整实时刷新', (tester) async {
    await pumpField(tester, initial: initialPaint);
    await selectGradient(tester);

    final topBefore = _previewGradient(tester).colors;
    expect(topBefore, const <Color>[Color(0xFFE87878), Color(0xFFE87878)]);

    // 上色：预览首端立即变化，末端保持不变。
    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#4A90D9',
    );
    await tester.pumpAndSettle();
    final topAfter = _previewGradient(tester);
    expect(topAfter.colors, const <Color>[
      Color(0xFF4A90D9),
      Color(0xFFE87878),
    ]);
    // 必须是新的颜色列表实例：LinearGradient/BoxDecoration 按值比较颜色，
    // 原地改写同一列表会让新旧装饰判定相等，预览不重绘。
    expect(topAfter.colors, isNot(same(topBefore)));

    // 下色：预览末端立即变化，上色保持。
    await tester.tap(
      find.byKey(const ValueKey('music-visual-color-stop-bottom')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#31C27C',
    );
    await tester.pumpAndSettle();
    expect(_previewGradient(tester).colors, const <Color>[
      Color(0xFF4A90D9),
      Color(0xFF31C27C),
    ]);

    await confirmDialog(tester);
    expect(captured?.colors, const <int>[0xFF4A90D9, 0xFF31C27C]);
  });

  testWidgets('渐变两端色块分别显示各自颜色', (tester) async {
    await pumpField(tester, initial: initialPaint);
    await selectGradient(tester);

    await tester.tap(
      find.byKey(const ValueKey('music-visual-color-stop-bottom')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#31C27C',
    );
    await tester.pumpAndSettle();

    expect(
      _stopSwatchColor(
        tester,
        find.byKey(const ValueKey('music-visual-color-stop-top')),
      ),
      const Color(0xFFE87878),
    );
    expect(
      _stopSwatchColor(
        tester,
        find.byKey(const ValueKey('music-visual-color-stop-bottom')),
      ),
      const Color(0xFF31C27C),
    );
  });

  testWidgets('渐变画法再次打开时回显两端颜色与当前端点', (tester) async {
    await pumpField(
      tester,
      initial: const LyricPaint.vertical(0xFF123456, 0xFF654321),
    );

    // 渐变端点的色块直接回显保存值，取色区默认编辑上色。
    final topStop = find.byKey(const ValueKey('music-visual-color-stop-top'));
    expect(topStop, findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('music-visual-color-hex')),
          )
          .controller!
          .text,
      '#123456',
    );

    await confirmDialog(tester);
    expect(captured?.colors, const <int>[0xFF123456, 0xFF654321]);
  });

  testWidgets('浅色宿主主题下弹窗仍复用深色主题样式', (tester) async {
    await pumpField(tester);

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, const Color(0xFF111A20));
    final dialogContext = tester.element(find.byType(AlertDialog));
    expect(Theme.of(dialogContext).brightness, Brightness.dark);
  });
}

/// 读取渐变预览条的渐变（键 `music-visual-color-gradient-preview`）。
LinearGradient _previewGradient(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const ValueKey('music-visual-color-gradient-preview')),
  );
  return (container.decoration! as BoxDecoration).gradient! as LinearGradient;
}

/// 读取某个渐变端点色块的当前颜色。
Color? _stopSwatchColor(WidgetTester tester, Finder stop) {
  final swatch = find.descendant(of: stop, matching: find.byType(Container));
  return (tester.widget<Container>(swatch.first).decoration! as BoxDecoration)
      .color;
}
