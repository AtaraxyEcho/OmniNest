import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_find_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_window_search.dart';

void main() {
  group('ReaderWindowSearchIndex', () {
    test('resolves hits across chapter boundaries', () {
      final index = ReaderWindowSearchIndex([
        WindowSearchChapter(
          chapterId: 'c0',
          title: '第一章',
          plainText: '开头寻找目标甲。',
        ),
        WindowSearchChapter(
          chapterId: 'c1',
          title: '第二章',
          plainText: '这里也有目标乙。',
        ),
      ]);

      final combined = index.combinedText;
      expect(combined, contains('目标甲'));
      expect(combined, contains('目标乙'));

      final hitA = index.resolve(combined.indexOf('目标甲'));
      expect(hitA!.chapterId, 'c0');
      expect(hitA.localOffset, '开头寻找目标甲。'.indexOf('目标甲'));
      expect(hitA.chapterTitle, '第一章');

      final hitB = index.resolve(combined.indexOf('目标乙'));
      expect(hitB!.chapterId, 'c1');
      expect(hitB.localOffset, '这里也有目标乙。'.indexOf('目标乙'));
      expect(index.titleOf(combined.indexOf('目标乙')), '第二章');
    });

    test('fromBlocks 建出的命中落在块源字符域而不是检索串下标', () {
      final chapter = WindowSearchChapter.fromBlocks(
        chapterId: 'c0',
        title: 'T',
        blocks: [
          ParagraphBlock(
            lines: [
              LineData(
                spans: [ReaderInlineSpan(text: '关键内容', startOffset: 3)],
                collapsedChars: 3,
              ),
            ],
          ),
        ],
      );
      expect(chapter.plainText, '关键内容');
      final index = ReaderWindowSearchIndex([chapter]);
      expect(index.resolve(0)!.chapterId, 'c0');
      // "关"在检索串里是第 0 个字符，在源域里是第 3 个（前面三个缩进字符不绘制但占位）。
      expect(index.resolve(0)!.localOffset, 3);
      expect(index.resolve(2)!.localOffset, 5);
    });
  });
  group('章内搜索的下标域（R10）', () {
    testWidgets('小写化会变长的字符不推走后续命中下标', (tester) async {
      // `İ`(U+0130) 小写化是 i + 组合点两个码元。旧实现先 toLowerCase 整串再
      // indexOf，得到的下标属于"变长之后的串"，拿去切原串就整体偏一位：
      // 高亮框住的是别人的字，跳转也落到错的位置。
      const plainText = 'İstanbul yolda İstanbul 见路不止';
      final selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 640,
              child: ReaderFindPanel(
                plainText: plainText,
                settings: ReaderViewSettings(),
                onSelect: selected.add,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'İstanbul');
      await tester.pump();

      expect(find.byType(ListTile), findsNWidgets(2));
      await tester.tap(find.byType(ListTile).last);
      await tester.pump();

      expect(selected, [15], reason: '第二个 İstanbul 在原串的第 15 个码元，不在变长后的 16/17');
    });
  });
}
