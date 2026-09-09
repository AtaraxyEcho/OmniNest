import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

ContinuousChapterEntry _chapter({
  required String id,
  required String title,
  required String body,
}) {
  final block = ParagraphBlock(
    lines: [
      LineData(spans: [ReaderInlineSpan(text: body)]),
    ],
  );
  return ContinuousChapterEntry(
    chapterId: id,
    title: title,
    blockCount: 1,
    cumulativeHeights: [80],
    totalHeight: 80,
    totalChars: body.length,
    isReady: true,
    blocks: [block],
    blockCharPrefixes: [0, body.length],
  );
}

void main() {
  testWidgets('renders sticky chapter headers and both chapters', (
    tester,
  ) async {
    final controller = ReaderContinuousScrollController();
    controller.rebuild(
      anchorChapterId: 'c0',
      allChapterIds: const ['c0', 'c1'],
      resolve: (id) {
        if (id == 'c0') {
          return _chapter(id: 'c0', title: '第一章标题', body: '甲章正文内容甲章正文内容');
        }
        return _chapter(id: 'c1', title: '第二章标题', body: '乙章正文内容乙章正文内容');
      },
    );
    final scrollController = ScrollController();
    addTearDown(() {
      scrollController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContinuousScrollView(
            controller: controller,
            settings: ReaderViewSettings(),
            scrollController: scrollController,
            itemId: 'book',
            annotationsByChapter: const {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一章标题'), findsOneWidget);
    expect(find.textContaining('甲章正文'), findsOneWidget);

    // 滚动到下一章可见。
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('第二章标题'), findsOneWidget);
    expect(find.textContaining('乙章正文'), findsOneWidget);
  });

  testWidgets('shows loading spinner when window empty', (tester) async {
    final controller = ReaderContinuousScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContinuousScrollView(
            controller: controller,
            settings: ReaderViewSettings(),
            scrollController: ScrollController(),
            itemId: 'book',
            annotationsByChapter: const {},
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
