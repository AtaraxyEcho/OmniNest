import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  testWidgets('renders heading and paragraph with indent', (tester) async {
    final settings = ReaderViewSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ReaderContentBlockItem(
                block: HeadingBlock(text: '章标题', level: 1),
                settings: settings,
                itemId: 'b',
                chapterId: 'c0',
              ),
              ReaderContentBlockItem(
                block: ParagraphBlock(
                  lines: [
                    LineData(spans: [ReaderInlineSpan(text: '正文内容')]),
                  ],
                ),
                settings: settings,
                itemId: 'b',
                chapterId: 'c0',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('章标题'), findsOneWidget);
    expect(find.textContaining('正文内容'), findsOneWidget);
    // 首行缩进
    expect(find.textContaining('　　正文内容'), findsOneWidget);
  });

  testWidgets('continuation paragraph skips indent', (tester) async {
    final settings = ReaderViewSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContentBlockItem(
            block: ParagraphBlock(
              lines: [
                LineData(spans: [ReaderInlineSpan(text: '续接段落')]),
              ],
            ),
            settings: settings,
            itemId: 'b',
            chapterId: 'c0',
            isFirstBlockContinuation: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('续接段落'), findsOneWidget);
    expect(find.textContaining('　　续接段落'), findsNothing);
  });
}
