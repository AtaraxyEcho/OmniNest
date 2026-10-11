import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_settings_mixin.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPanel(
    WidgetTester tester, {
    bool mobile = false,
    ValueChanged<ReaderViewSettings>? onSettingsChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderViewSettingsPanel(
              settings: ReaderViewSettings(),
              onSettingsChanged: onSettingsChanged ?? (_) {},
              mobile: mobile,
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
      expect(find.byType(WorkstationSwitch), findsNWidgets(2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('桌面端隐藏音量键翻页设置项', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpPanel(tester);
      expect(find.byType(WorkstationSwitch), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('移动壳层开关形态', () {
    testWidgets('移动壳层用样例胶囊，不沿用工位直角开关', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpPanel(tester, mobile: true);

      expect(find.byType(MobilePillSwitch), findsNWidgets(2));
      expect(find.byType(WorkstationSwitch), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('工位形态保持直角开关', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpPanel(tester);

      expect(find.byType(WorkstationSwitch), findsOneWidget);
      expect(find.byType(MobilePillSwitch), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('整行可点按，不必命中 34×20 胶囊', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      ReaderViewSettings? emitted;
      await pumpPanel(
        tester,
        mobile: true,
        onSettingsChanged: (value) => emitted = value,
      );

      // 面板按稿子限高 82dvh 并纵向滚动，尾部开关要先滚进视口。
      await tester.ensureVisible(find.byIcon(Icons.fullscreen_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pumpAndSettle();

      expect(emitted?.immersiveMode, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('开关行只暴露一个带名称的 toggled 节点', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final handle = tester.ensureSemantics();
      await pumpPanel(tester, mobile: true);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ReaderViewSettingsPanel)),
      );
      final label = l10n.readerImmersiveMode;
      final node =
          tester.getSemantics(find.byIcon(Icons.fullscreen_rounded)).toString();
      expect(node, contains('hasToggled'));
      expect(node, contains('isButton'));
      expect(node, contains('label: "$label"'));
      expect(
        node,
        isNot(contains('$label\\n$label')),
        reason: '行与胶囊各写一次名称会让读屏播两遍',
      );
      handle.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('移动壳层只换正文档位', () {
    test('移动壳层保留深色档，只把正文换成样例的 19/1.85', () {
      final mobile = applyReaderShellDefaults(
        loaded: ReaderViewSettings(),
        mobileShell: true,
      );

      expect(mobile.paletteId, ReaderReadingPalette.dark.id);
      expect(mobile.fontSize, 19);
      expect(mobile.lineHeight, 1.85);
    });

    test('桌面宽窗保持深色与默认字号，不换档', () {
      final desktop = applyReaderShellDefaults(
        loaded: ReaderViewSettings(),
        mobileShell: false,
      );

      expect(desktop.paletteId, ReaderReadingPalette.dark.id);
      expect(desktop.fontSize, ReaderViewSettings().fontSize);
    });
  });
}
