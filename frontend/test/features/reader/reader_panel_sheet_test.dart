import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_adaptive_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 三面板（目录 / 显示与排版 / 批注）共用抽屉外壳的规格锁。
///
/// 数值来自稿子 `完善移动端阅读器UI UX/src/index.css` 的 `.sheet-layer`、
/// `.bottom-sheet`、`.sheet-handle`、`.sheet-header`、`.chapter-*`、
/// `.setting-*` 与 `@media (min-width:720px)`；本文件只锁"稿子定了什么"，
/// 不在这里重复控件的行为用例。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    Size viewport = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder:
              (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(body: child),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReaderControlLayout layoutAt(Size viewport) =>
      ReaderControlLayout.resolve(viewport: viewport, fontSize: 19);

  group('稿子 .bottom-sheet 外壳', () {
    test('几何常量锁住稿子取值', () {
      expect(ReaderSheetSpec.radius, 28);
      expect(ReaderSheetSpec.maxWidth, 680);
      expect(ReaderSheetSpec.wideBreakpointWidth, 720);
      expect(ReaderSheetSpec.wideBottomMargin, 18);
      expect(ReaderSheetSpec.handleWidth, 38);
      expect(ReaderSheetSpec.handleHeight, 4);
      expect(ReaderSheetSpec.shadowBlurRadius, 60);
      expect(ReaderSheetSpec.shadowOffset, const Offset(0, -20));
      expect(
        ReaderSheetSpec.headerPadding,
        const EdgeInsets.fromLTRB(24, 12, 20, 12),
      );
      // sheet-up 240ms cubic-bezier(.22,.8,.25,1)；本项目动效上限 320ms。
      expect(
        ReaderSheetSpec.entranceDuration,
        const Duration(milliseconds: 240),
      );
    });

    test('遮罩是稿子的 42% 绿黑，不是纯黑', () {
      const scrim = ReaderSheetSpec.scrimColor;
      // Color 的通道在这版 Flutter 上是 0..1 的 double。
      expect((scrim.r * 255).round(), 15);
      expect((scrim.g * 255).round(), 18);
      expect((scrim.b * 255).round(), 16);
      expect(scrim.a, closeTo(0.42, 0.005));
    });

    test('窄屏只圆顶角不画底边，≥720 四角全圆补底边', () {
      final narrow = ReaderSheetSpec.borderRadiusFor(390);
      expect(narrow.topLeft.x, 28);
      expect(narrow.bottomLeft.x, 0);
      final wide = ReaderSheetSpec.borderRadiusFor(720);
      expect(wide.bottomLeft.x, 28);

      const line = Color(0xFF112233);
      expect(
        ReaderSheetSpec.borderFor(390, line).bottom.style,
        BorderStyle.none,
      );
      expect(ReaderSheetSpec.borderFor(720, line).bottom.color, line);
    });

    testWidgets('手机宽度：抽屉贴底、占满视口宽', (tester) async {
      await pumpAt(
        tester,
        ReaderAdaptivePanelOverlay(
          title: '目录',
          eyebrow: '书名',
          settings: ReaderViewSettings(),
          layout: layoutAt(const Size(390, 844)),
          onClose: () {},
          child: const SizedBox.shrink(),
        ),
      );

      final sheet = tester.getRect(find.byType(ReaderAdaptivePanelFrame));
      expect(sheet.width, 390);
      expect(sheet.bottom, 844);
      expect(sheet.top, closeTo(844 - 691.7, 0.5));
    });

    testWidgets('≥720 视口：宽 680 居中、离底边 18', (tester) async {
      const viewport = Size(900, 800);
      await pumpAt(
        tester,
        ReaderAdaptivePanelOverlay(
          title: '目录',
          settings: ReaderViewSettings(),
          layout: layoutAt(viewport),
          onClose: () {},
          child: const SizedBox.shrink(),
        ),
        viewport: viewport,
      );

      final sheet = tester.getRect(find.byType(ReaderAdaptivePanelFrame));
      expect(sheet.width, 680);
      expect(sheet.left, (900 - 680) / 2);
      expect(sheet.bottom, 800 - 18);
    });

    testWidgets('点遮罩空白处关闭面板', (tester) async {
      var closed = 0;
      await pumpAt(
        tester,
        ReaderAdaptivePanelOverlay(
          title: '目录',
          settings: ReaderViewSettings(),
          layout: layoutAt(const Size(390, 844)),
          onClose: () => closed++,
          child: const SizedBox.shrink(),
        ),
      );

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('关闭钮按稿子画成圆形描边钮，触控边长不低于 48', (tester) async {
      await pumpAt(
        tester,
        ReaderAdaptivePanelOverlay(
          title: '目录',
          eyebrow: '书名',
          settings: ReaderViewSettings(),
          layout: layoutAt(const Size(390, 844)),
          onClose: () {},
          child: const SizedBox.shrink(),
        ),
      );

      // 稿子 .icon-button 是 44×44；本项目把返回/关闭这类逃生控件下限定在 48。
      final chip = find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(IconButton),
      );
      final size = tester.getSize(chip);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      final shape = tester
          .widget<IconButton>(chip)
          .style!
          .shape!
          .resolve(<WidgetState>{});
      expect(shape, isA<CircleBorder>());
    });

    testWidgets('头部是 9pt 强调色眉标 + 25pt 衬线面板名', (tester) async {
      await pumpAt(
        tester,
        ReaderAdaptivePanelOverlay(
          title: '目录',
          eyebrow: '寂静的艺术',
          settings: ReaderViewSettings(),
          layout: layoutAt(const Size(390, 844)),
          onClose: () {},
          child: const SizedBox.shrink(),
        ),
      );

      final eyebrow = tester.widget<Text>(find.text('寂静的艺术'));
      expect(eyebrow.style?.fontSize, AppTypography.labelNano);
      expect(eyebrow.style?.fontWeight, FontWeight.w700);
      final title = tester.widget<Text>(find.text('目录'));
      expect(title.style?.fontSize, 25);
      expect(title.style?.fontFamily, AppTypography.serifFamily);
    });
  });

  group('稿子 .chapter-list', () {
    const chapters = [
      ReaderChapter(id: 'c1', title: '第一章', level: 0),
      ReaderChapter(id: 'c2', title: '第二章', level: 0),
      ReaderChapter(id: 'c3', title: '第三节', level: 1, chapterNumber: 2),
    ];

    Future<void> pumpToc(WidgetTester tester) => pumpAt(
      tester,
      ChapterPanel(
        chapters: chapters,
        currentChapterId: 'c2',
        settings: ReaderViewSettings(),
        onChapterTap: (_) {},
      ),
    );

    testWidgets('序号补零、摘要行给全书章数与当前章位', (tester) async {
      await pumpToc(tester);

      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('共 3 章'), findsOneWidget);
      expect(find.text('第 2/3 章'), findsOneWidget);
      // 「正在阅读」只出现在当前行。
      expect(find.text('正在阅读'), findsOneWidget);
    });

    testWidgets('列表左右留 20，发丝线随行的 8/4 内边距', (tester) async {
      await pumpToc(tester);

      final list = tester.widget<ListView>(find.byType(ListView).first);
      final padding = list.padding! as EdgeInsets;
      expect(padding.left, 20);
      expect(padding.right, 20);

      final row = tester.widget<Container>(
        find
            .ancestor(of: find.text('第一章'), matching: find.byType(Container))
            .first,
      );
      expect(
        row.padding,
        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      );
      expect(row.constraints!.minHeight, 65);
      expect(
        (row.decoration! as BoxDecoration).border!.bottom.color,
        isNotNull,
      );
    });

    testWidgets('标题 12/600，副标签 9，点行回调带章节 id', (tester) async {
      String? tapped;
      await pumpAt(
        tester,
        ChapterPanel(
          chapters: chapters,
          currentChapterId: 'c1',
          settings: ReaderViewSettings(),
          onChapterTap: (id) => tapped = id,
        ),
      );

      expect(tester.widget<Text>(find.text('第一章')).style?.fontSize, 12);
      expect(
        tester.widget<Text>(find.text('第一章')).style?.fontWeight,
        FontWeight.w600,
      );
      // `.chapter-label small`：9px 副标签是章节序号，不是标题本身。
      expect(tester.widget<Text>(find.text('第 2 章')).style?.fontSize, 9);

      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      expect(tapped, 'c1');
    });
  });

  group('稿子 .setting-section', () {
    Future<void> pumpSettings(WidgetTester tester) => pumpAt(
      tester,
      ReaderViewSettingsPanel(
        settings: ReaderViewSettings(),
        onSettingsChanged: (_) {},
        pageModeEnabled: true,
        mobile: true,
      ),
      viewport: const Size(390, 844),
    );

    testWidgets('段名 11、选项 10、格内选项 9', (tester) async {
      await pumpSettings(tester);

      expect(find.text('阅读模式'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('阅读模式')).style?.fontSize,
        AppTypography.labelSmall,
      );
      // `.setting-label small`（当前值）与 `.segmented button` 同为 10px。
      final scrollLabels = find.text('滑动');
      expect(scrollLabels, findsNWidgets(2));
      for (final label in tester.widgetList<Text>(scrollLabels)) {
        expect(label.style?.fontSize, AppTypography.labelMicro);
      }
      // `.setting-grid .segmented button` 再收一档。
      expect(
        tester.widget<Text>(find.text('宋体')).style?.fontSize,
        AppTypography.labelNano,
      );
    });

    testWidgets('选中面用 --page-elevated，首段不画上沿线', (tester) async {
      await pumpSettings(tester);
      final settings = ReaderViewSettings();

      final selectedBox = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('宋体'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (selectedBox.decoration! as BoxDecoration).color,
        settings.elevatedColor,
      );

      final firstSection = tester.widget<Container>(
        find
            .ancestor(of: find.text('阅读模式'), matching: find.byType(Container))
            .first,
      );
      expect(firstSection.decoration, isNull);

      final sizeSection = tester.widget<Container>(
        find
            .ancestor(of: find.text('字号'), matching: find.byType(Container))
            .first,
      );
      final border = (sizeSection.decoration! as BoxDecoration).border!;
      expect(border.top.style, BorderStyle.solid);
    });

    testWidgets('色板四格按内容排布，不在放大缩放下溢出', (tester) async {
      await pumpAt(
        tester,
        ReaderViewSettingsPanel(
          settings: ReaderViewSettings(),
          onSettingsChanged: (_) {},
          pageModeEnabled: true,
          mobile: true,
        ),
        viewport: const Size(320, 640),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
