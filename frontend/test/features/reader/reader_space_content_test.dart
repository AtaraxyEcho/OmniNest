import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_space_content.dart';

ReaderItem _item(String id, String title, String author, {double? progress}) {
  return ReaderItem(
    id: id,
    itemType: 'EPUB',
    title: title,
    updatedAt: DateTime(2026, 10, 1),
    authorName: author,
    progressPercent: progress,
  );
}

Widget _host(ReaderSpaceContent content) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: SingleChildScrollView(child: content)),
  );
}

void main() {
  testWidgets('Reader 空间四段齐备：特写/洞察/书轨/最近笔记', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var resumed = false;
    await tester.pumpWidget(
      _host(
        ReaderSpaceContent(
          featureItem: _item(
            'a',
            'The Art of Stillness',
            'Pico Iyer',
            progress: 0.64,
          ),
          railItems: [
            _item('b', 'Designing for Calm', 'John Maeda', progress: 0.38),
            _item('c', 'Norwegian Wood', 'Haruki Murakami'),
          ],
          notes: const [
            ReaderSpaceNote(
              annotationId: 'n1',
              itemId: 'a',
              quote: 'Attention is the rarest form of generosity.',
            ),
          ],
          bookTitles: const {'a': 'The Art of Stillness'},
          insightMinutes: 144,
          insightBooksFinished: 3,
          insightStreakDays: 4,
          onResume: (_) => resumed = true,
          onOpenItem: (_) {},
          onOpenBookshelf: () {},
        ),
      ),
    );

    // 特写：眉标 + 进度百分比 + 续读按钮。
    expect(find.text('CONTINUE READING'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('Continue chapter'), findsOneWidget);

    // 洞察：眉标常驻 + 时长 + 累计读完本数（不是章数，也不是本周量）。
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('2:24 in focus this week'), findsOneWidget);
    expect(
      find.text('3 books finished in total · 4-day streak'),
      findsOneWidget,
    );

    // 书轨：标题（纸封 + 标签行各一处）与作者。
    expect(find.text('Designing for Calm'), findsNWidgets(2));
    expect(find.text('John Maeda'), findsOneWidget);

    // 最近笔记：引用 + 书名副文案（纸封/特写标题/笔记副文案共三处同名）。
    expect(
      find.text('"Attention is the rarest form of generosity."'),
      findsOneWidget,
    );
    expect(find.text('The Art of Stillness'), findsNWidgets(3));

    // 续读按钮回调。
    await tester.tap(find.text('Continue chapter'));
    await tester.pump();
    expect(resumed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无续读条目时特写退让最近条目且不渲染进度', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var shelfOpened = false;
    await tester.pumpWidget(
      _host(
        ReaderSpaceContent(
          featureItem: _item('a', 'Norwegian Wood', 'Haruki Murakami'),
          railItems: const [],
          notes: const [],
          bookTitles: const {},
          insightMinutes: null,
          insightBooksFinished: 0,
          onResume: (_) {},
          onOpenItem: (_) {},
          onOpenBookshelf: () => shelfOpened = true,
        ),
      ),
    );

    // 特写标题与纸封书名同名（封面 + 拷贝各一处）。
    expect(find.text('Norwegian Wood'), findsNWidgets(2));
    // 无进度数据时不渲染百分比。
    expect(find.text('0%'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is OmniIcon && widget.icon == OmniIcons.sparkle,
      ),
      findsOneWidget,
    );
    // 书架入口常驻：样例的 YOUR SHELVES 小节恒在，动作位就是它。
    // 此前小节被空的 rail 一起跳过，移动侧唯一的书架入口随之消失。
    expect(find.text('Bookshelf'), findsOneWidget);
    await tester.tap(find.text('Bookshelf'));
    await tester.pump();
    expect(shelfOpened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
