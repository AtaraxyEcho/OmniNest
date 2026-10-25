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

  group('正文生僻字回落', () {
    test('无衬线正文回落到全量衬线字体', () {
      final settings = ReaderViewSettings(fontFamily: 'sans');

      expect(settings.resolvedFontFamily, isNull);
      expect(settings.bodyStyle.fontFamilyFallback, <String>[
        'NotoSansSC',
        'NotoSerifSC',
      ]);
    });

    test('衬线正文使用保留全量的衬线字体', () {
      final settings = ReaderViewSettings(fontFamily: 'serif');

      expect(settings.bodyStyle.fontFamily, 'NotoSerifSC');
      expect(settings.bodyStyle.fontFamilyFallback, contains('NotoSerifSC'));
    });
  });

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
      // 面板上只有音量键翻页与跟随原书两个开关：沉浸模式已撤下，
      // 再数出第三个就是重复入口。
      expect(find.byType(WorkstationSwitch), findsNWidgets(2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('桌面端隐藏音量键翻页设置项', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpPanel(tester);
      // 音量键不可用的平台只剩跟随原书这一个开关。
      expect(find.byType(WorkstationSwitch), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('跟随原书排版开关', () {
    test('默认不跟随，序列化往返保留用户选择', () {
      expect(ReaderViewSettings().followBookTypesetting, isFalse);
      final enabled = ReaderViewSettings.fromJson(
        ReaderViewSettings(followBookTypesetting: true).toJson(),
      );
      expect(enabled.followBookTypesetting, isTrue);
    });

    test('旧版本偏好没有这个字段时按不跟随补齐', () {
      const legacy = {
        'fontFamily': 'serif',
        'fontSize': 18,
        'lineHeight': 1.6,
        'themeIndex': 2,
        'readingMode': 'scroll',
        'immersiveMode': false,
        'pageTurnMode': 'slide',
        'version': 5,
      };
      expect(
        ReaderViewSettings.fromJson(legacy).followBookTypesetting,
        isFalse,
      );
    });

    testWidgets('整行点按即开启，回调收到新值', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      ReaderViewSettings? emitted;
      await pumpPanel(
        tester,
        mobile: true,
        onSettingsChanged: (value) => emitted = value,
      );

      await tester.ensureVisible(find.byIcon(Icons.format_size_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.format_size_rounded));
      await tester.pumpAndSettle();

      expect(emitted?.followBookTypesetting, isTrue, reason: '默认关闭，点行即开启');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('作用域说明取自 ARB，随开关一起渲染', (tester) async {
      // 「跟随原书排版」这个名字比它的实际作用域宽：它只管缩进·段距·对齐，
      // 字号/字体/行距恒归读者。说明必须进 ARB 并真的出现在面板上，
      // 否则读者会以为打开就与这本书一模一样。
      await pumpPanel(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ReaderViewSettingsPanel)),
      );
      // 段名与开关行各写了一次标签（既有形态），说明只在段名之下出现一次。
      expect(
        find.text(l10n.readerFollowBookTypesetting),
        findsNWidgets(2),
        reason: '段名与开关行都写着同一个标签，少一处就是面板结构变了',
      );
      expect(
        find.text(l10n.readerFollowBookTypesettingHint),
        findsOneWidget,
        reason: '开关少了作用域说明',
      );
    });

    testWidgets('移动壳层同样渲染说明，且读屏真的念得到', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final handle = tester.ensureSemantics();
      await pumpPanel(tester, mobile: true);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ReaderViewSettingsPanel)),
      );
      expect(
        find.text(l10n.readerFollowBookTypesettingHint),
        findsOneWidget,
        reason: '移动态面板少了作用域说明',
      );
      // 说明挂在段名之下而不是开关行内：整行是 excludeSemantics 的点按目标，
      // 塞进行里就会被语义屏蔽，读屏只念得到开关名。
      expect(
        find.bySemanticsLabel(l10n.readerFollowBookTypesettingHint),
        findsOneWidget,
        reason: '说明在语义树里不可达，等于没写',
      );
      handle.dispose();
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
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpPanel(tester);

      expect(find.byType(WorkstationSwitch), findsNWidgets(2));
      expect(find.byType(MobilePillSwitch), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('整行可点按，不必命中 34×20 胶囊', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      ReaderViewSettings? emitted;
      await pumpPanel(
        tester,
        mobile: true,
        onSettingsChanged: (value) => emitted = value,
      );

      // 面板按稿子限高 82dvh 并纵向滚动，尾部开关要先滚进视口。
      await tester.ensureVisible(find.byIcon(Icons.volume_up_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pumpAndSettle();

      expect(emitted?.volumeKeyPaging, isFalse, reason: '默认开，点整行即关');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('开关行只暴露一个带名称的 toggled 节点', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final handle = tester.ensureSemantics();
      await pumpPanel(tester, mobile: true);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ReaderViewSettingsPanel)),
      );
      final label = l10n.readerVolumeKeyPaging;
      final node =
          tester.getSemantics(find.byIcon(Icons.volume_up_rounded)).toString();
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
        hasSavedTypography: false,
      );

      expect(mobile.paletteId, ReaderReadingPalette.dark.id);
      expect(mobile.fontSize, 19);
      expect(mobile.lineHeight, 1.85);
    });

    test('桌面宽窗保持深色与默认字号，不换档', () {
      final desktop = applyReaderShellDefaults(
        loaded: ReaderViewSettings(),
        mobileShell: false,
        hasSavedTypography: false,
      );

      expect(desktop.paletteId, ReaderReadingPalette.dark.id);
      expect(desktop.fontSize, ReaderViewSettings().fontSize);
    });

    test('用户存过字号或行距后，移动壳层不再盖回样例档位', () {
      final saved = ReaderViewSettings.fromJson(const {
        'fontSize': 24.0,
        'lineHeight': 2.1,
        'paletteId': 'dark',
        'version': 7,
      });

      final resolved = applyReaderShellDefaults(
        loaded: saved,
        mobileShell: true,
        hasSavedTypography: true,
      );

      expect(resolved.fontSize, 24.0);
      expect(resolved.lineHeight, 2.1);
    });

    test('套用过的移动默认会落盘，重进同一本书不会二次覆盖', () {
      final mobile = ReaderViewSettings().withMobileDefaults();

      expect(mobile.mobileDefaults, isTrue);
      expect(mobile.toJson()['mobileDefaults'], isTrue);

      final reloaded = ReaderViewSettings.fromJson(mobile.toJson());
      expect(reloaded.mobileDefaults, isTrue);
      expect(reloaded.withMobileDefaults().fontSize, 19);
    });
  });
}
