import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/player/music_visual_color_picker.dart';

void main() {
  const defaultColor = Color(0xFF72D6C9);

  Color? captured;

  Future<void> pumpField(
    WidgetTester tester, {
    Color initial = const Color(0xFFE87878),
  }) async {
    captured = null;
    tester.view.physicalSize = const Size(800, 900);
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
            child: MusicVisualColorField(
              palette: MusicImmersivePalette.digital,
              label: '激活颜色',
              value: initial,
              defaultValue: defaultColor,
              onChanged: (color) => captured = color,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MusicVisualColorField));
    await tester.pumpAndSettle();
  }

  Future<void> confirmDialog(WidgetTester tester) async {
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  testWidgets('点选预设色并确认后回调对应颜色', (tester) async {
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

    expect(captured, const Color(0xFF31C27C));
  });

  testWidgets('HEX 输入实时生效并随确认回调', (tester) async {
    await pumpField(tester);

    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#31C27C',
    );
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured, const Color(0xFF31C27C));
  });

  testWidgets('HEX 输入非法内容时不改变当前颜色', (tester) async {
    await pumpField(tester, initial: const Color(0xFF31C27C));

    await tester.enterText(
      find.byKey(const ValueKey('music-visual-color-hex')),
      '#12',
    );
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured, const Color(0xFF31C27C));
  });

  testWidgets('拖动色相条后确认回调色相变化后的颜色', (tester) async {
    await pumpField(tester, initial: const Color(0xFFE87878));

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
    expect(captured, isNot(const Color(0xFFE87878)));
  });

  testWidgets('恢复默认色按钮回调字段默认值', (tester) async {
    await pumpField(tester, initial: const Color(0xFFE87878));

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(captured, defaultColor);
  });
}
