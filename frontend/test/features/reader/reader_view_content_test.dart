import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// stripHtml 是 reader_html_parser.dart 中的顶层公共函数。
/// _parseBlocks 是私有的，通过 widget 渲染间接测试。
void main() {
  group('stripHtml', () {
    test('removes HTML tags and returns plain text', () {
      expect(stripHtml('<p>Hello</p>'), 'Hello');
    });

    test('collapses multiple whitespace into single space', () {
      expect(stripHtml('<p>Hello</p>  <p>World</p>'), 'Hello World');
    });

    test('handles empty string', () {
      expect(stripHtml(''), '');
    });

    test('handles string with only tags', () {
      expect(stripHtml('<br/><hr/>'), '');
    });

    test('preserves text content across multiple tags', () {
      expect(
        stripHtml('<h1>Title</h1><p>Body <b>text</b></p>'),
        'Title Body text',
      );
    });
  });

  group('ReaderViewContent widget', () {
    Widget buildTestWidget({
      required String html,
      List<ReaderAnnotation> annotations = const [],
      void Function(String, int, int)? onHighlight,
      void Function(String, int, int)? onAnnotate,
      void Function(VoidCallback)? onRegisterClearSelection,
      VoidCallback? onTap,
    }) {
      final settings = ReaderViewSettings();
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: OmniNestTheme.from(AppThemePalette.dark),
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 400,
            child: ReaderViewContent(
              htmlContent: html,
              settings: settings,
              annotations: annotations,
              onHighlight: onHighlight,
              onAnnotate: onAnnotate,
              onRegisterClearSelection: onRegisterClearSelection,
              onTap: onTap,
            ),
          ),
        ),
      );
    }

    /// 等待 compute isolate 完成解析。
    /// compute() 在独立 isolate 中运行，在 fake async 下不会自动完成。
    /// 使用 runAsync 让真实异步执行，然后 pump 触发重建。
    Future<void> waitForParse(WidgetTester tester) async {
      // runAsync 使用真实事件循环，允许 isolate 消息传递
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      // pump 触发 setState 导致的重建
      await tester.pump();
    }

    testWidgets('renders simple paragraph content', (tester) async {
      await tester.pumpWidget(buildTestWidget(html: '<p>Hello world</p>'));
      await waitForParse(tester);

      expect(find.textContaining('Hello world'), findsOneWidget);
    });

    testWidgets('renders heading content', (tester) async {
      await tester.pumpWidget(buildTestWidget(html: '<h1>Title</h1>'));
      await waitForParse(tester);

      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('renders mixed heading and paragraph', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(html: '<h1>Title</h1><p>Body text</p>'),
      );
      await waitForParse(tester);

      expect(find.text('Title'), findsOneWidget);
      expect(find.textContaining('Body text'), findsOneWidget);
    });

    testWidgets('shows loading indicator for large content', (tester) async {
      // 小内容（< 500 字符）同步解析，不显示加载指示器
      // 大内容使用 isolate 异步解析，会显示加载指示器
      final largeHtml = '<p>${'word ' * 200}</p>';
      await tester.pumpWidget(buildTestWidget(html: largeHtml));

      // 第一次 pump 时应显示加载指示器（大内容走异步路径）
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders empty state for empty HTML', (tester) async {
      await tester.pumpWidget(buildTestWidget(html: ''));
      await waitForParse(tester);

      // 空内容应显示无内容提示，不应抛出异常
      expect(find.byType(ReaderViewContent), findsOneWidget);
    });

    testWidgets('contains SelectionArea for text selection', (tester) async {
      await tester.pumpWidget(buildTestWidget(html: '<p>Selectable text</p>'));
      await waitForParse(tester);

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('点击正文文本会触发阅读工具栏切换', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        buildTestWidget(
          html: '<p>Tap reader content</p>',
          onTap: () => tapCount++,
        ),
      );
      await waitForParse(tester);

      await tester.tap(find.textContaining('Tap reader content'));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('selected text menu exposes highlight and annotation actions', (
      tester,
    ) async {
      String? highlightedText;
      int? highlightedStart;
      int? highlightedEnd;
      await tester.pumpWidget(
        buildTestWidget(
          html: '<p>Annotatable reader text</p>',
          onHighlight: (text, start, end) {
            highlightedText = text;
            highlightedStart = start;
            highlightedEnd = end;
          },
          onAnnotate: (_, _, _) {},
        ),
      );
      await waitForParse(tester);

      await tester.longPress(find.textContaining('Annotatable reader text'));
      await tester.pumpAndSettle();

      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Add Annotation'), findsOneWidget);
      await tester.tap(find.text('Highlight'));
      await tester.pump();

      expect(highlightedText != null && highlightedText!.isNotEmpty, true);
      expect(highlightedStart != null, true);
      expect(highlightedEnd! > highlightedStart!, true);
    });

    testWidgets('残留选区下的单击不再被吞：清选中的同时切换工具栏', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        buildTestWidget(
          html: '<p>Selection then tap text</p>',
          onTap: () => tapCount++,
        ),
      );
      await waitForParse(tester);

      await tester.longPress(find.textContaining('Selection then tap text'));
      await tester.pumpAndSettle();

      // 连点两次正文：其中一次可能被选区上下文菜单吃掉，但修复后至少有一次必须完成切换。
      // 旧实现"仅清除选中即 return"会把选区存在期间的单击全部吞掉，得到 0。
      final content = find.textContaining('Selection then tap text');
      await tester.tapAt(tester.getCenter(content));
      await tester.pump();
      await tester.tapAt(tester.getCenter(content));
      await tester.pump();

      expect(tapCount, greaterThanOrEqualTo(1), reason: '选区存在期间的单击不得被静默吞掉');
    });

    testWidgets('拖拽滚动不切换工具栏', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        buildTestWidget(html: '<p>拖拽滚动测试内容</p>', onTap: () => tapCount++),
      );
      await waitForParse(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.textContaining('拖拽滚动测试内容')),
      );
      await gesture.moveBy(const Offset(0, 60));
      await gesture.up();
      await tester.pump();

      expect(tapCount, 0);
    });

    testWidgets('清除选择焦点后替换章节不会访问失活元素', (tester) async {
      VoidCallback? clearSelection;
      await tester.pumpWidget(
        buildTestWidget(
          html: '<p>Selectable chapter content for replacement</p>',
          onRegisterClearSelection: (callback) => clearSelection = callback,
        ),
      );
      await waitForParse(tester);
      await tester.longPress(find.textContaining('Selectable chapter'));
      await tester.pump();

      clearSelection?.call();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(tester.takeException() == null, true);
    });

    testWidgets('renders bold text within paragraph', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(html: '<p>Hello <b>world</b></p>'),
      );
      await waitForParse(tester);

      // 验证包含 "Hello" 和 "world" 的文本已渲染
      expect(find.textContaining('Hello'), findsWidgets);
      expect(find.textContaining('world'), findsWidgets);
    });

    testWidgets('renders content with annotations', (tester) async {
      final annotations = [
        const ReaderAnnotation(
          id: 'ann-1',
          readerItemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 5,
          note: 'test',
          createdAt: null,
          color: '#FFEB3B',
        ),
      ];

      await tester.pumpWidget(
        buildTestWidget(html: '<p>Hello world</p>', annotations: annotations),
      );
      await waitForParse(tester);

      // 批注应用后内容应正常渲染
      expect(find.textContaining('Hello'), findsWidgets);
    });

    testWidgets('renders divider block', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(html: '<p>Before</p><hr/><p>After</p>'),
      );
      await waitForParse(tester);

      expect(find.textContaining('Before'), findsOneWidget);
      expect(find.textContaining('After'), findsOneWidget);
    });
  });
}
