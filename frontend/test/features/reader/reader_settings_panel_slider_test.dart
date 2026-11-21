import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required ValueChanged<ReaderViewSettings> onSettingsChanged,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildApp(
        SingleChildScrollView(
          child: ReaderViewSettingsPanel(
            settings: ReaderViewSettings(paletteId: 'dark'),
            onSettingsChanged: onSettingsChanged,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dragFontSizeSlider(WidgetTester tester) async {
    // 面板还有亮度与护眼暖色两条滑杆，按 Key 精确命中字号那条。
    final slider = find.byKey(const Key('readerFontSizeSlider'));
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('字号滑条拖动触发 onSettingsChanged 且值增大', (tester) async {
    ReaderViewSettings? received;
    await pumpPanel(
      tester,
      onSettingsChanged: (settings) => received = settings,
    );

    await dragFontSizeSlider(tester);

    expect(received, isNotNull);
    expect(received!.fontSize, greaterThan(18.0));
  });

  testWidgets('Windows 滑条路径字号拖动同样生效', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    ReaderViewSettings? received;
    await pumpPanel(
      tester,
      onSettingsChanged: (settings) => received = settings,
    );

    await dragFontSizeSlider(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(received, isNotNull);
    expect(received!.fontSize, greaterThan(18.0));
  });
}
