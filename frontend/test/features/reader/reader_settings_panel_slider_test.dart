import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/app_slider.dart';
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
    // 稿子把行距换成了三档分段，面板里只剩字号一条滑杆。
    final sliders = find.byType(AppSlider);
    expect(sliders, findsOneWidget);
    await tester.drag(sliders.first, const Offset(80, 0));
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
