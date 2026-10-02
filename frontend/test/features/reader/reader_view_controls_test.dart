import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_find_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_bottom_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_top_bar.dart';

void main() {
  Widget buildApp(Widget child, {double textScale = 1, Locale? locale}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder:
          (context, appChild) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: appChild!,
          ),
      home: Scaffold(body: child),
    );
  }

  ReaderViewBottomBar buildBottomBar({bool immersiveMode = false}) {
    return ReaderViewBottomBar(
      settings: ReaderViewSettings(
        paletteId: 'dark',
        immersiveMode: immersiveMode,
      ),
      progress: 0.42,
      isPageMode: true,
      onPrevious: () {},
      onNext: () {},
      onShowContents: () {},
      onShowSettings: () {},
      onToggleImmersive: () {},
    );
  }

  testWidgets('文本阅读底栏按实际宽度选择三档布局', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cases = <(Size, Key)>[
      (const Size(320, 568), const Key('readerControlsCompact')),
      (const Size(800, 600), const Key('readerControlsMedium')),
      (const Size(1280, 800), const Key('readerControlsExpanded')),
    ];
    for (final entry in cases) {
      tester.view.physicalSize = entry.$1;
      await tester.pumpWidget(buildApp(buildBottomBar()));
      await tester.pump();

      expect(find.byKey(entry.$2), findsOneWidget);
      expect(find.byIcon(Icons.toc_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsNothing);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('文本阅读顶栏在窄屏长标题与放大字体下不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildApp(
        ReaderViewTopBar(
          settings: ReaderViewSettings(paletteId: 'dark'),
          bookTitle: '用于验证窄屏省略和控件布局的超长书籍标题',
          chapterTitle: '同样很长的章节标题需要稳定占据第二行',
          onBack: () {},
          onSearch: () {},
          onShowShortcuts: () {},
          onAddBookmark: () {},
        ),
        textScale: 1.5,
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_rounded), findsNothing);
    expect(find.byIcon(Icons.toc_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文本阅读顶栏紧凑档溢出菜单收纳低频操作且无目录入口', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var ttsToggled = false;
    var immersiveToggled = false;
    await tester.pumpWidget(
      buildApp(
        ReaderViewTopBar(
          settings: ReaderViewSettings(paletteId: 'dark'),
          bookTitle: '测试书籍',
          chapterTitle: '测试章节',
          onBack: () {},
          onSearch: () {},
          onShowShortcuts: () {},
          onAddBookmark: () {},
          onToggleTts: () => ttsToggled = true,
          onShowAnnotations: () {},
          onToggleImmersive: () => immersiveToggled = true,
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('朗读'), findsOneWidget);
    expect(find.text('批注'), findsOneWidget);
    expect(find.text('快捷键'), findsOneWidget);
    expect(find.text('沉浸模式'), findsOneWidget);
    expect(find.byIcon(Icons.toc_rounded), findsNothing);

    await tester.tap(find.text('沉浸模式'));
    await tester.pumpAndSettle();
    expect(immersiveToggled, isTrue);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('朗读'));
    await tester.pumpAndSettle();
    expect(ttsToggled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文本阅读顶栏宽屏保留快捷键按钮且不出现溢出菜单', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildApp(
        ReaderViewTopBar(
          settings: ReaderViewSettings(paletteId: 'dark'),
          bookTitle: '测试书籍',
          chapterTitle: '测试章节',
          onBack: () {},
          onSearch: () {},
          onShowShortcuts: () {},
          onAddBookmark: () {},
          onToggleTts: () {},
          onShowAnnotations: () {},
          onToggleImmersive: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沉浸模式在底栏使用明确的可见性状态', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(buildBottomBar()));
    expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);

    await tester.pumpWidget(buildApp(buildBottomBar(immersiveMode: true)));
    expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('样例 ReaderFocus 顶栏渲染玻璃钮与居中标题收纳溢出菜单', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var backTapped = false;
    await tester.pumpWidget(
      buildApp(
        ReaderViewTopBar(
          settings: ReaderViewSettings(paletteId: 'nightGlass'),
          bookTitle: 'The Art of Stillness',
          chapterTitle: 'Chapter 6',
          sampleChrome: true,
          onBack: () => backTapped = true,
          onSearch: () {},
          onShowShortcuts: () {},
          onAddBookmark: () {},
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.text('The Art of Stillness'), findsOneWidget);
    expect(find.text('Chapter 6'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is OmniIcon && widget.icon == OmniIcons.arrow,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is OmniIcon && widget.icon == OmniIcons.more,
      ),
      findsOneWidget,
    );
    // 样例皮肤不使用 Material 溢出钮与实底动作钮。
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is OmniIcon && widget.icon == OmniIcons.arrow,
      ),
    );
    await tester.pump();
    expect(backTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('样例 ReaderFocus 页脚渲染进度百分比与 Aa 设置钮', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildApp(
        ReaderViewBottomBar(
          settings: ReaderViewSettings(paletteId: 'nightGlass'),
          progress: 0.64,
          isPageMode: false,
          sampleChrome: true,
          onPrevious: () {},
          onNext: () {},
          onShowContents: () {},
          onShowSettings: () {},
          onToggleImmersive: () {},
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.text('64%'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is OmniIcon && widget.icon == OmniIcons.settings,
      ),
      findsOneWidget,
    );
    // 样例页脚不再出现工位实底按钮组。
    expect(find.byKey(const Key('readerControlsCompact')), findsNothing);
    expect(find.byIcon(Icons.toc_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文本阅读短横屏底栏保持稳定高度且不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(buildBottomBar(), textScale: 2));
    await tester.pump();

    expect(find.byKey(const Key('readerControlsMedium')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('嵌入式批注面板在窄屏大字体下可完整布局', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildApp(
        SizedBox(
          height: 360,
          child: ReaderAnnotationPanel(
            annotations: const [],
            allAnnotations: const [],
            chapters: const [],
            settings: ReaderViewSettings(paletteId: 'dark'),
            embedded: true,
          ),
        ),
        textScale: 1.5,
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节搜索结果突出显示匹配关键词', (tester) async {
    await tester.pumpWidget(
      buildApp(
        SizedBox(
          height: 420,
          child: ReaderFindPanel(
            plainText: '第一段内容 需要突出显示的关键词 第二段内容',
            settings: ReaderViewSettings(paletteId: 'light'),
            onSelect: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.pump();

    final richText = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan is TextSpan &&
            (widget.textSpan! as TextSpan).children?.any(
                  (span) => span is TextSpan && span.text == '关键词',
                ) ==
                true,
      ),
    );
    final spans = (richText.textSpan! as TextSpan).children!.cast<TextSpan>();
    final match = spans.firstWhere((span) => span.text == '关键词');
    expect(match.style?.fontWeight, FontWeight.w800);
    expect(match.style?.backgroundColor, isNotNull);
  });

  testWidgets('阅读提示条经全局反馈门面展示并去重合并', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildApp(
        Builder(
          builder:
              (context) => TextButton(
                onPressed: () => showReaderSnackBar(context, '书签已添加'),
                child: const Text('显示提示'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('显示提示'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('书签已添加'), findsOneWidget);

    // 同文案再次触发：合并为一条并重置计时，不产生第二条。
    await tester.tap(find.text('显示提示'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('书签已添加'), findsOneWidget);
    // 冲刷自动关闭计时器，避免用例结束残留 pending timer。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
