import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderViewSettingsPanel(
              settings: ReaderViewSettings(),
              onSettingsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ReaderViewSettings volumeKeyPaging', () {
    test('默认开启', () {
      expect(ReaderViewSettings().volumeKeyPaging, isTrue);
    });

    test('toJson/fromJson 往返保留开关值', () {
      final disabled = ReaderViewSettings.fromJson(
        ReaderViewSettings(volumeKeyPaging: false).toJson(),
      );
      expect(disabled.volumeKeyPaging, isFalse);
      final enabled = ReaderViewSettings.fromJson(
        ReaderViewSettings().toJson(),
      );
      expect(enabled.volumeKeyPaging, isTrue);
    });

    test('v4 旧数据缺少字段时迁移为默认开启', () {
      final legacy = <String, dynamic>{
        'fontFamily': 'serif',
        'fontSize': 18.0,
        'lineHeight': 1.8,
        'paletteId': 'dark',
        'readingMode': 'scroll',
        'immersiveMode': false,
        'pageTurnMode': 'slide',
        'version': 4,
      };
      expect(ReaderViewSettings.fromJson(legacy).volumeKeyPaging, isTrue);
    });

    testWidgets('移动端显示音量键翻页设置项', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpPanel(tester);
      expect(find.byType(Switch), findsNWidgets(2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('桌面端隐藏音量键翻页设置项', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpPanel(tester);
      expect(find.byType(Switch), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
